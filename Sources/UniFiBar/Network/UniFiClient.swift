import Foundation

actor UniFiClient {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private var siteId: String?

    init(baseURL: URL, apiKey: String, allowSelfSigned: Bool = false) {
        self.baseURL = baseURL
        self.apiKey = apiKey

        if allowSelfSigned {
            let config = URLSessionConfiguration.default
            self.session = URLSession(
                configuration: config,
                delegate: SelfSignedCertDelegate(),
                delegateQueue: nil
            )
        } else {
            self.session = URLSession.shared
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

    func fetchDevices() async throws -> [DeviceDTO] {
        let id = try await fetchSiteId()
        let data = try await request("/proxy/network/integrations/v1/sites/\(id)/devices")
        if let response = try? JSONDecoder().decode(DeviceListResponse.self, from: data) {
            return response.data
        }
        return try JSONDecoder().decode([DeviceDTO].self, from: data)
    }

    // MARK: - VPN Tunnels

    func fetchVPNTunnels() async -> [VPNTunnelDTO]? {
        do {
            let id = try await fetchSiteId()
            let data = try await request("/proxy/network/integrations/v1/sites/\(id)/vpn/tunnels")
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
}

// MARK: - Self-Signed Certificate Delegate

final class SelfSignedCertDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: serverTrust))
    }
}
