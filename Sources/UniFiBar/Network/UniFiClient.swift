import CryptoKit
import Foundation
import os
@preconcurrency import Security

actor UniFiClient {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private let pinnedCertDelegate: PinnedCertDelegate?
    private var siteId: String?

    private static let requestTimeout: TimeInterval = 15
    private static let logger = Logger(subsystem: "com.unifbar.app", category: "UniFiClient")

    init(baseURL: URL, apiKey: String, allowSelfSigned: Bool = false) {
        self.baseURL = baseURL
        // Strip control characters to prevent HTTP header injection
        self.apiKey = apiKey.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init).joined()

        if allowSelfSigned {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = Self.requestTimeout
            let delegate = PinnedCertDelegate(host: baseURL.host() ?? "")
            self.pinnedCertDelegate = delegate
            self.session = URLSession(
                configuration: config,
                delegate: delegate,
                delegateQueue: nil
            )
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = Self.requestTimeout
            self.pinnedCertDelegate = nil
            self.session = URLSession(configuration: config)
        }
    }

    /// Whether the certificate pin has detected a mismatch (cert changed since first pin).
    /// Check this when requests fail to distinguish "cert changed" from "controller unreachable".
    var certificateChanged: Bool {
        pinnedCertDelegate?.certChanged ?? false
    }

    /// Clear the stored certificate pin so the next connection re-pins.
    /// Call this after the user confirms they renewed their controller certificate.
    func resetCertificatePin() {
        if let host = baseURL.host() {
            PinnedCertDelegate.deletePinFromKeychain(host: host)
        }
    }

    // MARK: - Core Requests

    private func request(_ path: String) async throws -> Data {
        let url = baseURL.appending(path: path)
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UniFiError.httpError(statusCode: -1)
        }
        guard httpResponse.statusCode == 200 else {
            throw UniFiError.httpError(statusCode: httpResponse.statusCode)
        }
        return data
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        let url = baseURL.appending(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UniFiError.httpError(statusCode: -1)
        }
        guard httpResponse.statusCode == 200 else {
            throw UniFiError.httpError(statusCode: httpResponse.statusCode)
        }
        return data
    }

    // MARK: - Site Discovery

    func fetchSiteId() async throws -> String {
        if let cached = siteId { return cached }

        struct SitesResponse: Decodable, Sendable {
            let data: [SiteEntry]
            struct SiteEntry: Decodable, Sendable {
                let id: String
                let name: String?
            }
        }

        let data = try await request("/proxy/network/integrations/v1/sites")
        let response = try JSONDecoder().decode(SitesResponse.self, from: data)
        guard let site = response.data.first else {
            throw UniFiError.noSitesFound
        }
        siteId = site.id
        return site.id
    }

    // MARK: - v2 Active Clients (primary data source)

    func fetchSelfV2() async throws -> SelfInfo {
        let data = try await request("/proxy/network/v2/api/site/default/clients/active")
        let allClients = try JSONDecoder().decode([V2ClientDTO].self, from: data)
        // Sanity cap to prevent memory exhaustion from a compromised controller
        let clients = allClients.count > 5_000 ? Array(allClients.prefix(5_000)) : allClients

        guard let myIP = DeviceDetector.activeIPv4Address() else {
            throw UniFiError.selfNotFound
        }

        guard let me = clients.first(where: { $0.ip == myIP }) else {
            throw UniFiError.selfNotFound
        }

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

    // MARK: - AP Statistics

    func fetchAPStats(deviceId: String, siteId: String) async -> APStats? {
        guard Self.isValidIdentifier(deviceId), Self.isValidIdentifier(siteId) else {
            Self.logger.warning("Invalid identifier for AP stats request")
            return nil
        }
        do {
            let data = try await request(
                "/proxy/network/integrations/v1/sites/\(siteId)/devices/\(deviceId)/statistics/latest"
            )
            let response = try JSONDecoder().decode(APStatsResponse.self, from: data)
            return response.toAPStats
        } catch {
            Self.logger.error("Failed to fetch AP stats: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Session History (POST-based)

    struct LegacyResponse<T: Decodable & Sendable>: Decodable, Sendable {
        let data: [T]
    }

    func fetchSessionHistory(mac: String) async -> [SessionDTO]? {
        let oneDayAgo = Int(Date.now.timeIntervalSince1970) - 86400
        do {
            let body: [String: Any] = ["macs": [mac], "start": oneDayAgo]
            let data = try await post("/proxy/network/api/s/default/stat/session", body: body)
            let response = try JSONDecoder().decode(LegacyResponse<SessionDTO>.self, from: data)
            let sessions = response.data
            return sessions.isEmpty ? nil : Array(sessions.prefix(1_000))
        } catch {
            Self.logger.error("Failed to fetch session history: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Devices

    func fetchDevices(siteId: String) async throws -> [DeviceDTO] {
        guard Self.isValidIdentifier(siteId) else { return [] }
        let data = try await request("/proxy/network/integrations/v1/sites/\(siteId)/devices")
        var devices: [DeviceDTO]
        if let response = try? JSONDecoder().decode(DeviceListResponse.self, from: data) {
            devices = response.data
        } else {
            devices = try JSONDecoder().decode([DeviceDTO].self, from: data)
        }
        return devices.count > 500 ? Array(devices.prefix(500)) : devices
    }

    // MARK: - VPN Tunnels

    func fetchVPNTunnels(siteId: String) async -> [VPNTunnelDTO]? {
        guard Self.isValidIdentifier(siteId) else { return nil }
        do {
            let data = try await request("/proxy/network/integrations/v1/sites/\(siteId)/vpn/tunnels")
            let response = try JSONDecoder().decode(VPNTunnelResponse.self, from: data)
            return response.data.isEmpty ? nil : response.data
        } catch {
            Self.logger.error("Failed to fetch VPN tunnels: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - WAN Health (legacy stat/health)

    func fetchWANHealth() async -> WANHealth? {
        do {
            let data = try await request("/proxy/network/api/s/default/stat/health")
            let response = try JSONDecoder().decode(WANHealthResponse.self, from: data)
            return response.toWANHealth()
        } catch {
            Self.logger.error("Failed to fetch WAN health: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Gateway Statistics

    func fetchGatewayStats(deviceId: String, siteId: String) async -> GatewayStats? {
        guard Self.isValidIdentifier(deviceId), Self.isValidIdentifier(siteId) else {
            Self.logger.warning("Invalid identifier for gateway stats request")
            return nil
        }
        do {
            let data = try await request(
                "/proxy/network/integrations/v1/sites/\(siteId)/devices/\(deviceId)/statistics/latest"
            )
            let response = try JSONDecoder().decode(GatewayStatsResponse.self, from: data)
            return response.toGatewayStats
        } catch {
            Self.logger.error("Failed to fetch gateway stats: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Alarms

    func fetchAlarms() async -> [AlarmDTO]? {
        do {
            let data = try await request("/proxy/network/api/s/default/rest/alarm")
            let response = try JSONDecoder().decode(LegacyResponse<AlarmDTO>.self, from: data)
            let active = response.data.filter { $0.archived != true }
            return active.isEmpty ? nil : Array(active.prefix(10))
        } catch {
            Self.logger.error("Failed to fetch alarms: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - DPI Stats

    func fetchDPIStats() async -> [DPICategoryDTO]? {
        do {
            let body: [String: Any] = ["type": "by_cat"]
            let data = try await post("/proxy/network/api/s/default/stat/sitedpi", body: body)
            let response = try JSONDecoder().decode(DPIStatsResponse.self, from: data)
            let categories = response.toCategories()
            return categories.isEmpty ? nil : Array(categories.prefix(8))
        } catch {
            Self.logger.error("Failed to fetch DPI stats: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - IDS/IPS Events

    func fetchIPSEvents() async -> [IPSEventDTO]? {
        do {
            let data = try await request("/proxy/network/api/s/default/stat/ips/event")
            let response = try JSONDecoder().decode(LegacyResponse<IPSEventDTO>.self, from: data)
            return response.data.isEmpty ? nil : Array(response.data.prefix(10))
        } catch {
            Self.logger.error("Failed to fetch IPS events: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Anomalies

    func fetchAnomalies() async -> [AnomalyDTO]? {
        do {
            let data = try await request("/proxy/network/api/s/default/stat/anomalies")
            let response = try JSONDecoder().decode(LegacyResponse<AnomalyDTO>.self, from: data)
            return response.data.isEmpty ? nil : Array(response.data.prefix(10))
        } catch {
            Self.logger.error("Failed to fetch anomalies: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Dynamic DNS

    func fetchDDNSStatus() async -> [DDNSStatusDTO]? {
        do {
            let data = try await request("/proxy/network/api/s/default/rest/dynamicdns")
            let response = try JSONDecoder().decode(LegacyResponse<DDNSStatusDTO>.self, from: data)
            return response.data.isEmpty ? nil : Array(response.data.prefix(10))
        } catch {
            Self.logger.error("Failed to fetch DDNS status: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Port Forwards

    func fetchPortForwards() async -> [PortForwardDTO]? {
        do {
            let data = try await request("/proxy/network/api/s/default/stat/portforward")
            let response = try JSONDecoder().decode(LegacyResponse<PortForwardDTO>.self, from: data)
            let active = response.data.filter { $0.enabled == true }
            return active.isEmpty ? nil : Array(active.prefix(50))
        } catch {
            Self.logger.error("Failed to fetch port forwards: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Rogue / Neighboring APs

    func fetchRogueAPs() async -> [RogueAPDTO]? {
        do {
            let body: [String: Any] = ["within": 24]
            let data = try await post("/proxy/network/api/s/default/stat/rogueap", body: body)
            let response = try JSONDecoder().decode(LegacyResponse<RogueAPDTO>.self, from: data)
            guard !response.data.isEmpty else { return nil }
            // Return top 10 by signal strength (prefer dBm signal, fall back to rssi)
            let sorted = response.data.sorted {
                let lhs = $0.signal ?? ($0.rssi.map { $0 - 95 } ?? -200)
                let rhs = $1.signal ?? ($1.rssi.map { $0 - 95 } ?? -200)
                return lhs > rhs
            }
            return Array(sorted.prefix(10))
        } catch {
            Self.logger.error("Failed to fetch rogue APs: \(Self.safeErrorDescription(error))")
            return nil
        }
    }

    // MARK: - Validation

    /// Validates that an identifier is safe for URL path interpolation (alphanumeric, hyphens, colons).
    private static func isValidIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ":") }
    }

    /// Returns a safe error description for logging (strips URLs and potential credential fragments).
    private static func safeErrorDescription(_ error: Error) -> String {
        if let unifiError = error as? UniFiError {
            switch unifiError {
            case .httpError(let code): return "HTTP \(code)"
            case .noSitesFound: return "no sites found"
            case .selfNotFound: return "self not found"
            case .invalidURL: return "invalid URL"
            case .notConfigured: return "not configured"
            }
        }
        // For URLSession errors, only log the code/domain — not the full description which may contain URLs
        let nsError = error as NSError
        return "\(nsError.domain) code=\(nsError.code)"
    }
}

// MARK: - Certificate Pinning Delegate (Trust-On-First-Use)

/// Pins the server certificate on first connection. Subsequent connections must present
/// the same certificate public key. On mismatch (e.g. cert renewal or MITM), the connection
/// is rejected and a specific error is surfaced so the user can intentionally reset the pin.
final class PinnedCertDelegate: NSObject, URLSessionDelegate, Sendable {
    private let expectedHost: String
    private let keychainKey: String
    private let state: OSAllocatedUnfairLock<PinState>

    enum PinState: Sendable {
        case unpinned
        case pinned(Data)
        case certChanged
    }

    /// Whether a certificate mismatch was detected (set after a failed handshake).
    /// Check this when a request fails with URLError.cancelledAuthenticationChallenge.
    var certChanged: Bool {
        state.withLock { if case .certChanged = $0 { return true }; return false }
    }

    init(host: String) {
        self.expectedHost = host
        self.keychainKey = "com.unifbar.cert-pin.\(host)"
        let existingPin = Self.loadPinFromKeychain(key: "com.unifbar.cert-pin.\(host)")
        if let pin = existingPin {
            self.state = OSAllocatedUnfairLock(initialState: .pinned(pin))
        } else {
            self.state = OSAllocatedUnfairLock(initialState: .unpinned)
        }
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

        guard challenge.protectionSpace.host == expectedHost else {
            return (.performDefaultHandling, nil)
        }

        guard let serverKeyHash = Self.publicKeyHash(from: serverTrust) else {
            return (.cancelAuthenticationChallenge, nil)
        }

        // Validate certificate hasn't expired and hostname matches.
        // We allow self-signed roots (the whole point of this delegate) but reject expired certs.
        guard Self.validateCertificate(serverTrust, for: expectedHost) else {
            return (.cancelAuthenticationChallenge, nil)
        }

        let (decision, shouldPersist): ((URLSession.AuthChallengeDisposition, URLCredential?), Bool) = state.withLock { currentState in
            switch currentState {
            case .pinned(let storedHash):
                if serverKeyHash == storedHash {
                    return ((.useCredential, URLCredential(trust: serverTrust)), false)
                } else {
                    // Cert changed — could be renewal or MITM. Reject and flag it.
                    currentState = .certChanged
                    return ((.cancelAuthenticationChallenge, nil), false)
                }

            case .unpinned:
                currentState = .pinned(serverKeyHash)
                return ((.useCredential, URLCredential(trust: serverTrust)), true)

            case .certChanged:
                return ((.cancelAuthenticationChallenge, nil), false)
            }
        }

        if shouldPersist {
            Self.savePinToKeychain(key: keychainKey, data: serverKeyHash)
        }

        return decision
    }

    /// Validates certificate expiration and hostname while allowing self-signed roots.
    private static func validateCertificate(_ trust: SecTrust, for host: String) -> Bool {
        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(trust, policy)
        // Evaluate — this checks expiration, hostname, etc.
        // Self-signed certs will fail standard evaluation, which is expected;
        // the pin check (done separately) is what authorizes them.
        var error: CFError?
        let valid = SecTrustEvaluateWithError(trust, &error)
        // If evaluation fails, check if it's solely due to a self-signed root (which we allow).
        // A valid pin already confirmed the cert identity, so we only need to reject expired leafs.
        if !valid, let error, CFErrorGetCode(error) != errSecNotTrusted {
            return false
        }
        return true
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

    // MARK: - Keychain storage for certificate pins

    private static func loadPinFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unifbar.cert-pins",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func savePinToKeychain(key: String, data: Data) {
        // Delete any existing item first to ensure kSecAttrAccessible is always set correctly
        // (SecItemUpdate cannot change the accessibility attribute of existing items)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unifbar.cert-pins",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unifbar.cert-pins",
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func deletePinFromKeychain(host: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unifbar.cert-pins",
            kSecAttrAccount as String: "com.unifbar.cert-pin.\(host)",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
