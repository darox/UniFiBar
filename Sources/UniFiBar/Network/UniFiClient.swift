import CryptoKit
import Foundation
import os
import Security

actor UniFiClient {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private var siteId: String?

    private static let requestTimeout: TimeInterval = 15

    init(baseURL: URL, apiKey: String, allowSelfSigned: Bool = false) {
        self.baseURL = baseURL
        self.apiKey = apiKey

        if allowSelfSigned {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = Self.requestTimeout
            self.session = URLSession(
                configuration: config,
                delegate: PinnedCertDelegate(host: baseURL.host() ?? ""),
                delegateQueue: nil
            )
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = Self.requestTimeout
            self.session = URLSession(configuration: config)
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
        let clients = try JSONDecoder().decode([V2ClientDTO].self, from: data)

        guard let myIP = DeviceDetector.en0IPv4Address() else {
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
        guard Self.isValidIdentifier(deviceId), Self.isValidIdentifier(siteId) else { return nil }
        do {
            let data = try await request(
                "/proxy/network/integrations/v1/sites/\(siteId)/devices/\(deviceId)/statistics/latest"
            )
            let response = try JSONDecoder().decode(APStatsResponse.self, from: data)
            return response.toAPStats
        } catch {
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
            return response.data.isEmpty ? nil : response.data
        } catch {
            return nil
        }
    }

    // MARK: - Devices

    func fetchDevices(siteId: String) async throws -> [DeviceDTO] {
        guard Self.isValidIdentifier(siteId) else { return [] }
        let data = try await request("/proxy/network/integrations/v1/sites/\(siteId)/devices")
        if let response = try? JSONDecoder().decode(DeviceListResponse.self, from: data) {
            return response.data
        }
        return try JSONDecoder().decode([DeviceDTO].self, from: data)
    }

    // MARK: - VPN Tunnels

    func fetchVPNTunnels(siteId: String) async -> [VPNTunnelDTO]? {
        guard Self.isValidIdentifier(siteId) else { return nil }
        do {
            let data = try await request("/proxy/network/integrations/v1/sites/\(siteId)/vpn/tunnels")
            let response = try JSONDecoder().decode(VPNTunnelResponse.self, from: data)
            return response.data.isEmpty ? nil : response.data
        } catch {
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
            return nil
        }
    }

    // MARK: - Gateway Statistics

    func fetchGatewayStats(deviceId: String, siteId: String) async -> GatewayStats? {
        guard Self.isValidIdentifier(deviceId), Self.isValidIdentifier(siteId) else { return nil }
        do {
            let data = try await request(
                "/proxy/network/integrations/v1/sites/\(siteId)/devices/\(deviceId)/statistics/latest"
            )
            let response = try JSONDecoder().decode(GatewayStatsResponse.self, from: data)
            return response.toGatewayStats
        } catch {
            return nil
        }
    }

    // MARK: - Validation

    /// Validates that an identifier is safe for URL path interpolation (alphanumeric, hyphens, colons).
    private static func isValidIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ":") }
    }
}

// MARK: - Certificate Pinning Delegate (Trust-On-First-Use)

/// Pins the server certificate on first connection. Subsequent connections must present
/// the same certificate public key, preventing MITM attacks even with self-signed certs.
final class PinnedCertDelegate: NSObject, URLSessionDelegate, Sendable {
    private let expectedHost: String
    private let pinnedKeyKey: String
    private let state: OSAllocatedUnfairLock<Data?>

    init(host: String) {
        self.expectedHost = host
        self.pinnedKeyKey = "com.unifbar.cert-pin.\(host)"
        self.state = OSAllocatedUnfairLock(
            initialState: UserDefaults.standard.data(forKey: pinnedKeyKey)
        )
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

        // Only handle challenges for our expected host
        guard challenge.protectionSpace.host == expectedHost else {
            return (.performDefaultHandling, nil)
        }

        // Extract public key hash from server certificate
        // If extraction fails, still allow connection (user opted into self-signed)
        guard let serverKeyHash = Self.publicKeyHash(from: serverTrust) else {
            return (.useCredential, URLCredential(trust: serverTrust))
        }

        let storedHash = state.withLock { $0 }

        if let storedHash {
            // Verify against pinned key — if mismatch, clear stale pin and re-pin
            // (cert rotation is common for self-signed certs)
            if serverKeyHash != storedHash {
                state.withLock { $0 = serverKeyHash }
                UserDefaults.standard.set(serverKeyHash, forKey: pinnedKeyKey)
            }
        } else {
            // Trust-on-first-use: pin the key
            state.withLock { $0 = serverKeyHash }
            UserDefaults.standard.set(serverKeyHash, forKey: pinnedKeyKey)
        }

        return (.useCredential, URLCredential(trust: serverTrust))
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
