import CryptoKit
import Foundation
import os
@preconcurrency import Security

protocol UniFiClientProtocol: Sendable {
    func fetchSiteId() async throws -> String
    func fetchSelfV2() async throws -> SelfInfo
    func fetchDevices(siteId: String) async throws -> [DeviceDTO]
    func fetchVPNTunnels(siteId: String) async -> [VPNTunnelDTO]?
    func fetchWANHealth() async -> WANHealth?
    func fetchGatewayStats(deviceId: String, siteId: String) async -> GatewayStats?
    func fetchAPStats(deviceId: String, siteId: String) async -> APStats?
    func fetchDeviceStats(deviceId: String, siteId: String) async -> DeviceStatsSnapshot?
    func fetchSessionHistory(mac: String) async -> [SessionDTO]?
    func fetchDDNSStatus() async -> (data: [DDNSStatusDTO]?, errorDetail: String?)
    func fetchPortForwards() async -> (data: [PortForwardDTO]?, errorDetail: String?)
    func fetchRogueAPs() async -> (data: [RogueAPDTO]?, errorDetail: String?)
    var certificateChanged: Bool { get async }
    func resetCertificatePin() async throws
    func resetSiteCache() async
    func invalidate() async
}

extension UniFiClientProtocol {
    /// Default: fetch the two projections separately. `UniFiClient` overrides this with a
    /// single request, since both projections decode from the same payload.
    func fetchDeviceStats(deviceId: String, siteId: String) async -> DeviceStatsSnapshot? {
        async let apStats = fetchAPStats(deviceId: deviceId, siteId: siteId)
        async let gatewayStats = fetchGatewayStats(deviceId: deviceId, siteId: siteId)
        let ap = await apStats
        let gateway = await gatewayStats
        guard ap != nil || gateway != nil else { return nil }
        return DeviceStatsSnapshot(
            apStats: ap ?? APStats(cpuUtilizationPct: nil, memoryUtilizationPct: nil),
            gatewayStats: gateway ?? GatewayStats(uptimeSec: nil, cpuUtilizationPct: nil, memoryUtilizationPct: nil)
        )
    }
}

actor UniFiClient: UniFiClientProtocol {
    /// Cap on nearby APs fetched by fetchRogueAPs; the menu title mirrors this value.
    static let nearbyAPsLimit = 10

    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private let redirectDelegate: SameOriginRedirectDelegate
    private let pinnedCertDelegate: PinnedCertDelegate?
    private struct Site: Decodable, Sendable {
        let id: String
        let internalReference: String
    }
    private var site: Site?
    private let decoder = JSONDecoder()
    private let fixtureTransport: (@Sendable (URLRequest) async throws -> Data)?
    private let localAddresses: @Sendable () -> [String]
    private var invalidated = false

    /// Clears the cached site ID so the next fetchSiteId() will rediscover it.
    func resetSiteCache() {
        site = nil
    }

    private static let requestTimeout: TimeInterval = 15
    private static let logger = Logger(subsystem: "com.unifbar.app", category: "UniFiClient")

    /// Ephemeral: the controller never needs cookies or credential persistence, and
    /// the shared stores would outlive session invalidation and leak across reconfiguration.
    private static func makeSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = 30
        return config
    }

    init(baseURL: URL, apiKey: String, allowSelfSigned: Bool = false,
         confirmCertificate: (@Sendable (PinnedCertDelegate.CertificateDetails) async -> Bool)? = nil,
         pinStore: CertificatePinStore = .keychain) {
        if case .success(let validated) = URLValidator.normalizeAndValidate(baseURL.absoluteString) {
            self.baseURL = validated
        } else {
            self.baseURL = baseURL
        }
        self.fixtureTransport = nil
        self.localAddresses = { DeviceDetector.activeIPv4Addresses() }
        // Strip control characters to prevent HTTP header injection
        self.apiKey = apiKey.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init).joined()

        if allowSelfSigned {
            let config = Self.makeSessionConfiguration()
            let delegate = PinnedCertDelegate(host: baseURL.host() ?? "", pinStore: pinStore, confirmCertificate: confirmCertificate)
            self.pinnedCertDelegate = delegate
            self.redirectDelegate = SameOriginRedirectDelegate(certificateDelegate: delegate)
            self.session = URLSession(
                configuration: config,
                delegate: delegate,
                delegateQueue: nil
            )
        } else {
            let config = Self.makeSessionConfiguration()
            self.pinnedCertDelegate = nil
            self.redirectDelegate = SameOriginRedirectDelegate()
            self.session = URLSession(configuration: config)
        }
    }

    /// Offline contract tests: no native pins, credentials, interface lookup or network fallback.
    init(fixtureTransport: @escaping @Sendable (URLRequest) async throws -> Data,
         localAddresses: @escaping @Sendable () -> [String] = { [] }) {
        baseURL = URL(string: "https://controller.invalid")!
        apiKey = "synthetic-key"
        self.fixtureTransport = fixtureTransport
        self.localAddresses = localAddresses
        pinnedCertDelegate = nil
        redirectDelegate = SameOriginRedirectDelegate()
        session = URLSession(configuration: .ephemeral)
    }

    /// Whether the certificate pin has detected a mismatch (cert changed since first pin).
    /// Check this when requests fail to distinguish "cert changed" from "controller unreachable".
    var certificateChanged: Bool {
        pinnedCertDelegate?.certChanged ?? false
    }

    /// Clear the stored certificate pin so the next connection re-pins.
    /// Call this after the user confirms they renewed their controller certificate.
    func resetCertificatePin() throws {
        guard !invalidated else { throw CancellationError() }
        if let pinnedCertDelegate {
            try pinnedCertDelegate.resetPin()
        } else if let host = baseURL.host() {
            try CertificatePinStore.keychain.remove(host: host)
        }
    }

    /// Invalidate the URLSession so in-flight requests are cancelled and the delegate is released.
    func invalidate() {
        invalidated = true
        pinnedCertDelegate?.invalidate()
        session.invalidateAndCancel()
    }

    // MARK: - Core Requests

    private func request(_ path: String, body: [String: Any]? = nil, query: [URLQueryItem] = []) async throws -> Data {
        guard !invalidated else { throw CancellationError() }
        try Task.checkCancellation()
        // The whole trust model assumes HTTPS. Never send the API key in cleartext,
        // even if a future caller skips URLValidator.
        guard baseURL.scheme?.lowercased() == "https" else { throw UniFiError.invalidURL }
        let url = baseURL.appending(path: path).appending(queryItems: query)
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if let fixtureTransport { return try await fixtureTransport(req) }
        do {
            return try await responseData(for: req)
        } catch {
            try Task.checkCancellation()
            // No URLSession task is running while the user verifies the fingerprint.
            // Retry once, only after approval; TLS rechecks validity and the pinned key.
            guard let delegate = pinnedCertDelegate, await delegate.approvePendingCertificate() else {
                throw pinnedCertDelegate?.failure ?? error
            }
            try Task.checkCancellation()
            guard !invalidated else { throw CancellationError() }
            return try await responseData(for: req)
        }
    }

    private func responseData(for req: URLRequest) async throws -> Data {
        // Download to a temporary file: one suspension per chunk instead of one per
        // byte, and the delegate enforces the size cap while the body streams in.
        do {
            return try await Self.boundedResponse(
                for: req, using: session, delegate: redirectDelegate
            )
        } catch {
            try Task.checkCancellation()
            // URLSession reports a rejected trust challenge as an opaque cancellation (-999).
            if let failure = pinnedCertDelegate?.failure { throw failure }
            throw error
        }
    }

    nonisolated static func boundedResponse(
        for request: URLRequest, using session: URLSession,
        delegate: URLSessionTaskDelegate, limit: Int = responseBodyLimit
    ) async throws -> Data {
        guard limit >= 0 else { throw URLError(.dataLengthExceedsMaximum) }
        let (fileURL, response) = try await session.download(for: request, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UniFiError.httpError(statusCode: -1)
        }
        guard httpResponse.statusCode == 200 else {
            throw UniFiError.httpError(statusCode: httpResponse.statusCode)
        }
        return try Data(contentsOf: fileURL)
    }

    static let responseBodyLimit = 16 * 1_024 * 1_024

    /// ponytail: 16 MiB per controller response; large sites need bounded pagination, not a larger silent cap.
    /// Used by UpdateChecker and tests; the production path caps via CappedDownloadDelegate.
    nonisolated static func boundedResponseData<Bytes: AsyncSequence>(
        _ bytes: Bytes, response: URLResponse, limit: Int = 16 * 1_024 * 1_024
    ) async throws -> Data where Bytes.Element == UInt8 {
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UniFiError.httpError(statusCode: -1)
        }
        guard httpResponse.statusCode == 200 else {
            throw UniFiError.httpError(statusCode: httpResponse.statusCode)
        }
        guard limit >= 0, response.expectedContentLength <= Int64(limit) else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }

    // MARK: - Site Discovery

    func fetchSiteId() async throws -> String {
        guard !invalidated else { throw CancellationError() }
        if let site { return site.id }
        let sites = try await fetchPages(Site.self, path: "/proxy/network/integration/v1/sites", id: { $0.id })
        guard !sites.isEmpty else { throw UniFiError.noSitesFound }
        guard sites.allSatisfy({ Self.isValidIdentifier($0.internalReference) }),
              Set(sites.map(\.internalReference)).count == sites.count else {
            throw UniFiError.incompleteResponse
        }
        // Keep the existing default-site product scope, never arbitrary response ordering.
        guard let selected = sites.first(where: { $0.internalReference == "default" })
                ?? (sites.count == 1 ? sites.first : nil) else { throw UniFiError.ambiguousSite }
        guard !invalidated else { throw CancellationError() }
        site = selected
        return selected.id
    }

    private func olderSiteReference() async throws -> String {
        _ = try await fetchSiteId()
        guard let site else { throw UniFiError.noSitesFound }
        return site.internalReference
    }

    private struct Page<T: Decodable & Sendable>: Decodable, Sendable {
        let data: [T]
        let count: Int
        let offset: Int
        let limit: Int
        let totalCount: Int
    }

    /// ponytail: at most 5,000 entries, 100 pages and 16 MiB per collection.
    /// Exceeding the budget fails visibly; larger deployments need a deliberate product limit.
    private func fetchPages<T: Decodable & Sendable>(
        _ type: T.Type, path: String, id: @Sendable (T) -> String?
    ) async throws -> [T] {
        var result: [T] = []
        var ids = Set<String>()
        var total: Int?
        var bytesRemaining = 16 * 1_024 * 1_024
        for _ in 0..<100 {
            let data = try await request(path, query: [
                URLQueryItem(name: "offset", value: String(result.count)),
                URLQueryItem(name: "limit", value: "200")
            ])
            try Task.checkCancellation()
            guard data.count <= bytesRemaining else { throw UniFiError.incompleteResponse }
            bytesRemaining -= data.count
            let page = try decoder.decode(Page<T>.self, from: data)
            guard page.offset == result.count, page.count == page.data.count,
                  (0...200).contains(page.limit), page.count <= page.limit,
                  (0...5_000).contains(page.totalCount),
                  page.count <= page.totalCount - result.count,
                  total == nil || total == page.totalCount else { throw UniFiError.incompleteResponse }
            total = page.totalCount
            for item in page.data {
                guard let identifier = id(item), Self.isValidIdentifier(identifier),
                      ids.insert(identifier).inserted else { throw UniFiError.incompleteResponse }
            }
            result.append(contentsOf: page.data)
            if result.count == page.totalCount { return result }
            guard page.count > 0 else { throw UniFiError.incompleteResponse }
        }
        throw UniFiError.incompleteResponse
    }

    // MARK: - v2 Active Clients (primary data source)

    func fetchSelfV2() async throws -> SelfInfo {
        let reference = try await olderSiteReference()
        let data = try await request("/proxy/network/v2/api/site/\(reference)/clients/active")
        let clients = try decoder.decode([V2ClientDTO].self, from: data)
        // ponytail: reject over 10,000 returned clients; never silently search a prefix.
        guard clients.count <= 10_000 else { throw UniFiError.incompleteResponse }

        // Try each active interface IP against the UniFi client list.
        // Interface-name order is deterministic, not a guarantee of Wi-Fi or default-route priority.
        let myIPs = localAddresses()
        for ip in myIPs {
            if let me = clients.first(where: { $0.ip == ip }) {
                let totalClients = clients.count
                let clientsOnSameAP: Int
                if let myAP = me.apMac {
                    clientsOnSameAP = clients.filter { $0.apMac == myAP }.count
                } else {
                    clientsOnSameAP = 1
                }
                return SelfInfo(
                    client: me,
                    totalClients: totalClients,
                    clientsOnSameAP: clientsOnSameAP
                )
            }
        }

        // Absence from this site's list does not establish Ethernet connectivity.
        throw UniFiError.selfNotFound
    }

    // MARK: - AP Statistics

    /// Latest device statistics. Both the AP and gateway projections decode from this one
    /// payload, so a caller that knows the IDs match can derive both from a single request.
    private func fetchDeviceStatsResponse(deviceId: String, siteId: String) async -> GatewayStatsResponse? {
        guard Self.isValidIdentifier(deviceId), Self.isValidIdentifier(siteId) else {
            Self.logger.warning("Invalid identifier for device statistics request")
            return nil
        }
        do {
            let data = try await request(
                "/proxy/network/integration/v1/sites/\(siteId)/devices/\(deviceId)/statistics/latest"
            )
            return try decoder.decode(GatewayStatsResponse.self, from: data)
        } catch {
            Self.logger.error("Failed to fetch device statistics: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    func fetchAPStats(deviceId: String, siteId: String) async -> APStats? {
        await fetchDeviceStatsResponse(deviceId: deviceId, siteId: siteId)?.toAPStats
    }

    func fetchDeviceStats(deviceId: String, siteId: String) async -> DeviceStatsSnapshot? {
        guard let response = await fetchDeviceStatsResponse(deviceId: deviceId, siteId: siteId) else { return nil }
        return DeviceStatsSnapshot(apStats: response.toAPStats, gatewayStats: response.toGatewayStats)
    }

    // MARK: - Session History (POST-based)

    /// Decodes a UniFi API response that may be wrapped in `{ "data": [...] }`
    /// or `{ "data": null }`, or may be a bare array `[...]`.
    /// Tries LegacyResponse first, then direct array.
    static func decodeFlexibleArray<T: Decodable & Sendable>(
        _ type: T.Type,
        from data: Data,
        endpoint: String
    ) -> [T]? {
        let array: [T]?
        if let response = try? JSONDecoder().decode(LegacyResponse<T>.self, from: data) {
            array = response.data ?? []
        } else {
            array = try? JSONDecoder().decode([T].self, from: data)
        }
        // ponytail: 5,000 legacy entries; larger lists fail visibly instead of freezing the menu or truncating it.
        if let array, array.count <= 5_000 {
            return array
        }
        // Log diagnostic info about the response (avoid logging raw data to prevent credential/data leaks)
        Self.logger.error("Failed to decode \(endpoint) or exceeded 5,000 entries. Response size: \(data.count) bytes")
        return nil
    }

    func fetchSessionHistory(mac: String) async -> [SessionDTO]? {
        let oneDayAgo = Int(Date.now.timeIntervalSince1970) - 86400
        do {
            let body: [String: Any] = ["macs": [mac], "start": oneDayAgo]
            let reference = try await olderSiteReference()
            let data = try await request("/proxy/network/api/s/\(reference)/stat/session", body: body)
            let sessions = Self.decodeFlexibleArray(SessionDTO.self, from: data, endpoint: "session_history")
            return sessions
        } catch {
            Self.logger.error("Failed to fetch session history: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Devices

    func fetchDevices(siteId: String) async throws -> [DeviceDTO] {
        guard Self.isValidIdentifier(siteId) else { throw UniFiError.invalidURL }
        return try await fetchPages(DeviceDTO.self, path: "/proxy/network/integration/v1/sites/\(siteId)/devices", id: { $0.id })
    }

    // MARK: - VPN Tunnels

    func fetchVPNTunnels(siteId: String) async -> [VPNTunnelDTO]? {
        guard Self.isValidIdentifier(siteId) else { return nil }
        do {
            return try await fetchPages(VPNTunnelDTO.self,
                path: "/proxy/network/integration/v1/sites/\(siteId)/vpn/site-to-site-tunnels", id: { $0.officialId })
        } catch {
            Self.logger.error("Failed to fetch VPN tunnels: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - WAN Health (legacy stat/health)

    func fetchWANHealth() async -> WANHealth? {
        do {
            let reference = try await olderSiteReference()
            let data = try await request("/proxy/network/api/s/\(reference)/stat/health")
            let response = try decoder.decode(WANHealthResponse.self, from: data)
            return response.toWANHealth()
        } catch {
            Self.logger.error("Failed to fetch WAN health: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Gateway Statistics

    func fetchGatewayStats(deviceId: String, siteId: String) async -> GatewayStats? {
        await fetchDeviceStatsResponse(deviceId: deviceId, siteId: siteId)?.toGatewayStats
    }

    // MARK: - Dynamic DNS

    func fetchDDNSStatus() async -> (data: [DDNSStatusDTO]?, errorDetail: String?) {
        do {
            let reference = try await olderSiteReference()
            let data = try await request("/proxy/network/api/s/\(reference)/rest/dynamicdns")
            guard let results = Self.decodeFlexibleArray(DDNSStatusDTO.self, from: data, endpoint: "ddns") else {
                return (nil, "decode failed, \(data.count) bytes")
            }
            return (results, nil)
        } catch {
            return (nil, Self.safeErrorDescription(error))
        }
    }

    // MARK: - Port Forwards

    func fetchPortForwards() async -> (data: [PortForwardDTO]?, errorDetail: String?) {
        do {
            let reference = try await olderSiteReference()
            let data = try await request("/proxy/network/api/s/\(reference)/stat/portforward")
            guard let results = Self.decodeFlexibleArray(PortForwardDTO.self, from: data, endpoint: "portforwards") else {
                return (nil, "decode failed, \(data.count) bytes")
            }
            let active = results.filter { $0.enabled == true }
            return (active, nil)
        } catch {
            return (nil, Self.safeErrorDescription(error))
        }
    }

    // MARK: - Rogue / Neighboring APs

    func fetchRogueAPs() async -> (data: [RogueAPDTO]?, errorDetail: String?) {
        do {
            let body: [String: Any] = ["within": 24]
            let reference = try await olderSiteReference()
            let data = try await request("/proxy/network/api/s/\(reference)/stat/rogueap", body: body)
            guard let results = Self.decodeFlexibleArray(RogueAPDTO.self, from: data, endpoint: "rogueaps") else {
                return (nil, "decode failed, \(data.count) bytes")
            }
            // Return the strongest APs (prefer dBm signal, fall back to rssi)
            let sorted = results.sorted {
                ($0.signalDBm ?? -200) > ($1.signalDBm ?? -200)
            }
            return (Array(sorted.prefix(Self.nearbyAPsLimit)), nil)
        } catch {
            return (nil, Self.safeErrorDescription(error))
        }
    }

    // MARK: - Validation

    /// Validates that an identifier is safe for URL path interpolation (alphanumeric, hyphens, underscores, colons).
    private static func isValidIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ":") }
    }

    /// Returns a safe error description for logging (strips URLs and potential credential fragments).
    private static func safeErrorDescription(_ error: Error) -> String {
        if let error = error as? CertificateConnectionError { return error.localizedDescription }
        if let unifiError = error as? UniFiError {
            switch unifiError {
            case .httpError(let code): return "HTTP \(code)"
            case .noSitesFound: return "no sites found"
            case .selfNotFound: return "self not found"
            case .invalidURL: return "invalid URL"
            case .incompleteResponse: return "incomplete or inconsistent collection"
            case .ambiguousSite: return "multiple sites without a default"
            case .throttled: return "connect attempts throttled"
            }
        }
        // For URLSession errors, only log the code/domain — not the full description which may contain URLs
        let nsError = error as NSError
        return "\(nsError.domain) code=\(nsError.code)"
    }

}

/// Custom API-key headers must never follow a redirect to another origin or HTTP.
final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let certificateDelegate: PinnedCertDelegate?

    init(certificateDelegate: PinnedCertDelegate? = nil) {
        self.certificateDelegate = certificateDelegate
    }

    // A per-task delegate supplied to bytes(for:) owns authentication too; Foundation
    // does not forward its default handling to the session's pinning delegate.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let certificateDelegate else { return (.performDefaultHandling, nil) }
        return await certificateDelegate.urlSession(session, didReceive: challenge)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let original = task.originalRequest?.url, let target = request.url,
              original.scheme?.lowercased() == "https", target.scheme?.lowercased() == "https",
              let host = original.host, target.host?.lowercased() == host.lowercased(),
              (original.port ?? 443) == (target.port ?? 443),
              target.user == nil, target.password == nil
        else { return nil }
        return request
    }
}

/// Enforces the response body cap while a download streams, and forwards the
/// task-level trust and redirect decisions to the shared redirect delegate.
final class CappedDownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let limit: Int
    private let redirectAndTrust: SameOriginRedirectDelegate
    private let exceeded = OSAllocatedUnfairLock(initialState: false)
    private let adopted = OSAllocatedUnfairLock<URL?>(initialState: nil)

    init(limit: Int, forwardingTo redirectAndTrust: SameOriginRedirectDelegate) {
        self.limit = limit
        self.redirectAndTrust = redirectAndTrust
    }

    var exceededLimit: Bool { exceeded.withLock { $0 } }

    /// Non-nil once the body has been moved out of the download temp file.
    var adoptedLocation: URL? { adopted.withLock { $0 } }

    /// The system removes the temp file when `didFinishDownloadingTo` returns, so the
    /// delegate must move it somewhere it owns before reading.
    static func adoptDownload(at location: URL) throws -> URL {
        let owned = FileManager.default.temporaryDirectory
            .appendingPathComponent("unifibar-response-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: location, to: owned)
        return owned
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let capped = Int64(limit)
        // totalBytesExpectedToWrite is NSURLResponseUnknownLength (-1) when unknown.
        let advertised = totalBytesExpectedToWrite < 0 ? 0 : totalBytesExpectedToWrite
        guard max(advertised, totalBytesWritten) <= capped else {
            exceeded.withLock { $0 = true }
            downloadTask.cancel()
            return
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let owned = try? Self.adoptDownload(at: location) else { return }
        adopted.withLock { $0 = owned }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await redirectAndTrust.urlSession(session, task: task, didReceive: challenge)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        await redirectAndTrust.urlSession(session, task: task,
                                          willPerformHTTPRedirection: response, newRequest: request)
    }
}

// MARK: - Certificate Pinning Delegate (Trust-On-First-Use)

/// Pins the server certificate on first connection. Subsequent connections must present
/// the same certificate public key. On mismatch (e.g. cert renewal or MITM), the connection
/// is rejected and a specific error is surfaced so the user can intentionally reset the pin.
final class PinnedCertDelegate: NSObject, URLSessionDelegate, Sendable {
    private let expectedHost: String
    private let pinStore: CertificatePinStore
    private let confirmCertificate: (@Sendable (CertificateDetails) async -> Bool)?
    private let state: OSAllocatedUnfairLock<PinState>

    struct CertificateDetails: Sendable {
        let host: String
        let fingerprint: String
    }

    enum PinState: Sendable {
        case unpinned
        case pinned(Data)
        case certChanged
        case storageFailed
        case awaitingApproval(Data, CertificateDetails)
        case rejected(CertificateConnectionError)
        case invalidated
    }

    /// Whether a certificate mismatch was detected (set after a failed handshake).
    /// Check this when a request fails with URLError.cancelledAuthenticationChallenge.
    var certChanged: Bool {
        state.withLock { if case .certChanged = $0 { return true }; return false }
    }

    var failure: CertificateConnectionError? {
        state.withLock {
            switch $0 {
            case .certChanged: .changedKey
            case .storageFailed: .pinStorageFailed
            case .awaitingApproval: .nameMismatch
            case .rejected(let reason): reason
            default: nil
            }
        }
    }

    init(host: String, pinStore: CertificatePinStore = .keychain,
         confirmCertificate: (@Sendable (CertificateDetails) async -> Bool)? = nil) {
        self.expectedHost = host
        self.pinStore = pinStore
        self.confirmCertificate = confirmCertificate
        do {
            let pin = try pinStore.load(host: host)
            self.state = OSAllocatedUnfairLock(initialState: pin.map(PinState.pinned) ?? .unpinned)
        } catch {
            self.state = OSAllocatedUnfairLock(initialState: .storageFailed)
        }
    }

    func resetPin() throws {
        try state.withLock {
            try pinStore.remove(host: expectedHost)
            // The caller recreates the delegate; this old session must not silently re-pin.
            $0 = .invalidated
        }
    }

    func invalidate() {
        state.withLock { $0 = .invalidated }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            return (.performDefaultHandling, nil)
        }

        guard challenge.protectionSpace.host.lowercased() == expectedHost.lowercased() else {
            return (.performDefaultHandling, nil)
        }

        guard let serverKeyHash = Self.publicKeyHash(from: serverTrust) else {
            reject(.invalidCertificate)
            return (.cancelAuthenticationChallenge, nil)
        }

        let nameMatches = Self.validateCertificate(serverTrust, for: expectedHost)
        // A known public key or explicit first-use approval can identify a controller
        // whose factory certificate names unifi.local instead of its LAN IP. Expiry,
        // key usage and HTTPS suitability remain mandatory, even after approval.
        guard nameMatches || Self.validateCertificate(serverTrust, for: nil) else {
            reject(.invalidCertificate)
            return (.cancelAuthenticationChallenge, nil)
        }

        let needsApproval = state.withLock { if case .unpinned = $0 { return !nameMatches }; return false }
        if needsApproval {
            guard let leaf = (SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate])?.first
            else {
                reject(.invalidCertificate)
                return (.cancelAuthenticationChallenge, nil)
            }
            let fingerprint = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
                .map { String(format: "%02X", $0) }.joined(separator: ":")
            state.withLock {
                if case .unpinned = $0 {
                    $0 = .awaitingApproval(serverKeyHash, CertificateDetails(host: expectedHost, fingerprint: fingerprint))
                }
            }
            return (.cancelAuthenticationChallenge, nil)
        }

        return state.withLock { currentState in
            switch currentState {
            case .pinned(let storedHash):
                guard serverKeyHash == storedHash else {
                    currentState = .certChanged
                    return (.cancelAuthenticationChallenge, nil)
                }
                return (.useCredential, URLCredential(trust: serverTrust))
            case .unpinned:
                do {
                    // Persist under the lock before allowing any concurrent challenge.
                    try pinStore.saveIfAbsent(serverKeyHash, host: expectedHost)
                    currentState = .pinned(serverKeyHash)
                    return (.useCredential, URLCredential(trust: serverTrust))
                } catch CertificatePinStore.Failure.conflictingPin {
                    currentState = .certChanged
                } catch {
                    currentState = .storageFailed
                }
                return (.cancelAuthenticationChallenge, nil)
            case .rejected, .storageFailed:
                // A stale failure can come from a transient cause: a wrong system clock
                // or a locked Keychain at first use. Trust is regained only when the
                // stored pin matches this exact key; a declined approval stays declined
                // and .certChanged still requires an explicit reset.
                if let stored = try? pinStore.load(host: expectedHost), stored == serverKeyHash {
                    currentState = .pinned(stored)
                    return (.useCredential, URLCredential(trust: serverTrust))
                }
                return (.cancelAuthenticationChallenge, nil)
            case .certChanged, .awaitingApproval, .invalidated:
                return (.cancelAuthenticationChallenge, nil)
            }
        }
    }

    /// Called after the rejected request ends, so network timeouts cannot expire a prompt.
    func approvePendingCertificate() async -> Bool {
        guard !Task.isCancelled, let confirmCertificate,
              case .awaitingApproval(let hash, let details) = state.withLock({ $0 }) else { return false }
        guard await confirmCertificate(details), !Task.isCancelled else {
            reject(.nameMismatch)
            return false
        }
        // Reset/invalidation and a competing pin always win over a stale approval.
        return state.withLock {
            guard case .awaitingApproval(let pendingHash, _) = $0, pendingHash == hash else { return false }
            do {
                try pinStore.saveIfAbsent(hash, host: expectedHost)
                $0 = .pinned(hash)
                return true
            } catch CertificatePinStore.Failure.conflictingPin {
                $0 = .certChanged
            } catch {
                $0 = .storageFailed
            }
            return false
        }
    }

    private func reject(_ reason: CertificateConnectionError) {
        state.withLock {
            switch $0 {
            case .unpinned, .pinned, .awaitingApproval: $0 = .rejected(reason)
            default: break // Preserve pin/storage failures and invalidation.
            }
        }
    }

    /// Trust only this leaf for this evaluation. A nil name still enforces SSL validity.
    private static func validateCertificate(_ trust: SecTrust, for host: String?) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let notBefore = SecCertificateCopyNotValidBeforeDate(leaf),
              let notAfter = SecCertificateCopyNotValidAfterDate(leaf)
        else { return false }
        let date = verificationDate(for: SecTrustGetVerifyTime(trust))
        guard (notBefore as Date) <= date, date <= (notAfter as Date) else { return false }

        // Evaluate a fresh trust object: the challenge's trust belongs to Foundation,
        // and mutating its policies or anchors would outlive this evaluation.
        // Anchoring on the leaf alone means only self-signed certificates pass; that is
        // the TOFU intent for LAN controllers.
        let policy = SecPolicyCreateSSL(true, host.map { $0 as CFString })
        var optionalTrust: SecTrust?
        guard SecTrustCreateWithCertificates(leaf, policy, &optionalTrust) == errSecSuccess,
              let freshTrust = optionalTrust,
              SecTrustSetAnchorCertificates(freshTrust, [leaf] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(freshTrust, true) == errSecSuccess
        else { return false }
        // Carry over an explicit verification time; zero means "now" and needs no copy.
        let verifyTime = SecTrustGetVerifyTime(trust)
        if verifyTime != 0 {
            let verifyDate = Date(timeIntervalSinceReferenceDate: verifyTime) as CFDate
            guard SecTrustSetVerifyDate(freshTrust, verifyDate) == errSecSuccess else { return false }
        }
        // Never let AIA or CRL lookups block the TLS challenge on network I/O.
        SecTrustSetNetworkFetchAllowed(freshTrust, false)
        return SecTrustEvaluateWithError(freshTrust, nil)
    }

    static func verificationDate(for time: CFAbsoluteTime) -> Date {
        // SecTrustGetVerifyTime documents zero as an implicit current verification time.
        time == 0 ? Date() : Date(timeIntervalSinceReferenceDate: time)
    }

    /// Extracts SHA-256 hash of the public key from a server trust.
    private static func publicKeyHash(from trust: SecTrust) -> Data? {
        guard let certChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let cert = certChain.first,
              let publicKey = SecCertificateCopyKey(cert),
              let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as? Data
        else {
            return nil
        }
        let digest = SHA256.hash(data: keyData)
        return Data(digest)
    }

}
