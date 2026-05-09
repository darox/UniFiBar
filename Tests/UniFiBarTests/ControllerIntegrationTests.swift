import Foundation
import Security
import Testing
@testable import UniFiBar

struct ControllerIntegrationTests {
    private static let controllerURL = readKeychain("com.unifbar.controller-url")
    private static let apiKey = readKeychain("com.unifbar.api-key")

    private static let sharedClient: UniFiClient = {
        guard let urlString = controllerURL,
              let url = URL(string: urlString),
              let key = apiKey
        else {
            fatalError("UniFiBar credentials not found in Keychain")
        }
        return UniFiClient(baseURL: url, apiKey: key, allowSelfSigned: true)
    }()

    private static func readKeychain(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unifbar.app",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    // MARK: - Site Discovery

    @Test func testSiteDiscovery() async throws {
        let siteId = try await Self.sharedClient.fetchSiteId()
        #expect(!siteId.isEmpty)
    }

    @Test func testSiteDiscoveryCaching() async throws {
        let first = try await Self.sharedClient.fetchSiteId()
        let cached = try await Self.sharedClient.fetchSiteId()
        #expect(first == cached)
    }

    // MARK: - Self Detection

    @Test func testSelfDetection() async throws {
        let info = try await Self.sharedClient.fetchSelfV2()
        #expect(!info.client.ip!.isEmpty)
        #expect(info.totalClients > 0)
    }

    @Test func testSelfInfoHasWiFiOrWiredData() async throws {
        let info = try await Self.sharedClient.fetchSelfV2()
        if info.client.apMac != nil {
            #expect(info.client.essid != nil || info.client.signal != nil)
        }
    }

    // MARK: - Devices

    @Test func testDevices() async throws {
        let siteId = try await Self.sharedClient.fetchSiteId()
        let devices = try await Self.sharedClient.fetchDevices(siteId: siteId)
        #expect(!devices.isEmpty)
        let withNames = devices.filter { $0.name != nil }
        #expect(!withNames.isEmpty)
    }

    @Test func testDevicesContainOnlineDevices() async throws {
        let siteId = try await Self.sharedClient.fetchSiteId()
        let devices = try await Self.sharedClient.fetchDevices(siteId: siteId)
        let online = devices.filter { $0.isOnline }
        #expect(!online.isEmpty)
    }

    // MARK: - WAN Health

    @Test func testWANHealth() async throws {
        let health = await Self.sharedClient.fetchWANHealth()
        #expect(health != nil)
        #expect(health?.status == "ok")
    }

    @Test func testWANHealthHasISP() async throws {
        let health = await Self.sharedClient.fetchWANHealth()
        #expect(health?.ispName != nil)
    }

    // MARK: - VPN Tunnels

    @Test func testVPNTunnels() async throws {
        let siteId = try await Self.sharedClient.fetchSiteId()
        let tunnels = await Self.sharedClient.fetchVPNTunnels(siteId: siteId)
        if let tunnels {
            #expect(!tunnels.isEmpty)
            #expect(tunnels.first?.name != nil)
        }
    }

    // MARK: - AP Statistics

    @Test func testAPStats() async throws {
        let siteId = try await Self.sharedClient.fetchSiteId()
        let info = try await Self.sharedClient.fetchSelfV2()

        guard let apMac = info.client.apMac else { return }
        let devices = try await Self.sharedClient.fetchDevices(siteId: siteId)
        guard let apDevice = devices.first(where: {
            $0.macAddress?.lowercased() == apMac.lowercased()
        }),
        let apId = apDevice.id else { return }

        let stats = await Self.sharedClient.fetchAPStats(deviceId: apId, siteId: siteId)
        #expect(stats != nil)
    }

    // MARK: - Gateway Statistics

    @Test func testGatewayStats() async throws {
        let siteId = try await Self.sharedClient.fetchSiteId()
        let devices = try await Self.sharedClient.fetchDevices(siteId: siteId)

        guard let gw = devices.first(where: \.isGateway),
              let gwId = gw.id else { return }

        let stats = await Self.sharedClient.fetchGatewayStats(deviceId: gwId, siteId: siteId)
        #expect(stats != nil)
        #expect(stats?.uptimeSec ?? 0 > 0)
    }

    // MARK: - Session History

    @Test func testSessionHistory() async throws {
        let info = try await Self.sharedClient.fetchSelfV2()

        guard let mac = info.client.mac else { return }

        let sessions = await Self.sharedClient.fetchSessionHistory(mac: mac)
        #expect(sessions != nil)
        #expect(!sessions!.isEmpty)
    }

    // MARK: - Monitoring: DDNS

    @Test func testDDNSStatus() async throws {
        let (data, error) = await Self.sharedClient.fetchDDNSStatus()
        #expect(error == nil)
        if let data {
            #expect(!data.isEmpty)
        }
    }

    // MARK: - Monitoring: Port Forwards

    @Test func testPortForwards() async throws {
        let (data, error) = await Self.sharedClient.fetchPortForwards()
        #expect(error == nil)
        if let data {
            #expect(!data.isEmpty)
        }
    }

    // MARK: - Monitoring: Rogue APs

    @Test func testRogueAPs() async throws {
        let (data, error) = await Self.sharedClient.fetchRogueAPs()
        #expect(error == nil)
        if let data {
            #expect(!data.isEmpty)
        }
    }

    // MARK: - Certificate Detection

    @Test func testNoCertChangeOnNormalConnect() async throws {
        _ = try? await Self.sharedClient.fetchSiteId()
        #expect(await Self.sharedClient.certificateChanged == false)
    }

    // MARK: - Full Poll Cycle

    @Test func testFullPollCycle() async throws {
        let client = Self.sharedClient

        let siteId = try await client.fetchSiteId()
        #expect(!siteId.isEmpty)

        let info = try await client.fetchSelfV2()
        #expect(!info.client.ip!.isEmpty)
        #expect(info.totalClients > 0)

        let devices = try await client.fetchDevices(siteId: siteId)
        #expect(!devices.isEmpty)

        let health = await client.fetchWANHealth()
        #expect(health != nil)

        if let mac = info.client.mac {
            let sessions = await client.fetchSessionHistory(mac: mac)
            #expect(sessions != nil)
        }
    }
}
