import Foundation
import Testing
@testable import UniFiBar

@MainActor
struct StatusBarControllerTests {

    private actor FakeClient: UniFiClientProtocol {
        let siteFetches = AsyncStream<Void>.makeStream()
        private(set) var siteFetchCount = 0
        private(set) var invalidationCount = 0

        var siteIdToReturn: String = "site-123"
        var selfInfoToReturn = SelfInfo(
            client: V2ClientDTO(ip: "192.168.1.5", mac: "aa:bb:cc", hostname: nil, displayName: "MacBook", signal: -50, rssi: nil, noise: -92, satisfaction: nil, wifiExperienceScore: 85, wifiExperienceAverage: 82, wifiTxRetriesPercentage: 0.5, channel: 36, channelWidth: 80, radioProto: "ax", radio: "5g", essid: "HomeWiFi", apMac: "11:22:33", lastUplinkName: "U7 Pro", rxRate: 480_000, txRate: 360_000, rxBytes: 1_500_000, txBytes: 500_000, uptime: 7200, mimo: "MIMO_2", roamCount: 3, ccq: nil, gwMac: nil),
            totalClients: 12,
            clientsOnSameAP: 5
        )
        var devicesToReturn: [DeviceDTO] = [
            DeviceDTO(id: "d1", macAddress: "11:22:33", name: "U7 Pro", model: "U7-Pro", state: "ONLINE", firmwareUpdatable: nil, features: nil, firmwareVersion: nil, ipAddress: nil),
            DeviceDTO(id: "d2", macAddress: "44:55:66", name: "U7 In-Wall", model: nil, state: "ONLINE", firmwareUpdatable: nil, features: nil, firmwareVersion: nil, ipAddress: nil),
        ]
        var wanHealthToReturn = WANHealth(ispName: "Comcast", wanIP: "203.0.113.1", status: "ok", latencyMs: 12, availability: 99.9, drops: 0, rxBytesRate: 1_500_000, txBytesRate: 800_000, speedTest: nil)
        var vpnTunnelsToReturn: [VPNTunnelDTO]? = nil
        var apStatsToReturn = APStats(uptimeSec: 3600, cpuUtilizationPct: 5.0, memoryUtilizationPct: 30.0)
        var gatewayStatsToReturn = GatewayStats(uptimeSec: 86400, cpuUtilizationPct: 12.0, memoryUtilizationPct: 45.0, uplinkTxRateBps: nil, uplinkRxRateBps: nil)
        var sessionsToReturn: [SessionDTO]? = nil
        var ddnsResult: (data: [DDNSStatusDTO]?, errorDetail: String?) = (nil, nil)
        var pfResult: (data: [PortForwardDTO]?, errorDetail: String?) = (nil, nil)
        var rogueResult: (data: [RogueAPDTO]?, errorDetail: String?) = (nil, nil)
        var certChangedFlag: Bool = false

        private var _fetchSiteError: Error? = nil
        private var _fetchSelfError: Error? = nil
        private var _fetchDevicesError: Error? = nil

        func setFetchSiteError(_ error: Error?) { _fetchSiteError = error }
        func setFetchSelfError(_ error: Error?) { _fetchSelfError = error }
        func setFetchDevicesError(_ error: Error?) { _fetchDevicesError = error }
        func setCertChanged(_ flag: Bool) { certChangedFlag = flag }

        func fetchSiteId() async throws -> String {
            siteFetchCount += 1
            siteFetches.continuation.yield(())
            if let e = _fetchSiteError { throw e }
            return siteIdToReturn
        }

        func fetchSelfV2() async throws -> SelfInfo {
            if let e = _fetchSelfError { throw e }
            return selfInfoToReturn
        }

        func fetchDevices(siteId: String) async throws -> [DeviceDTO] {
            if let e = _fetchDevicesError { throw e }
            return devicesToReturn
        }

        func fetchVPNTunnels(siteId: String) async -> [VPNTunnelDTO]? { vpnTunnelsToReturn }
        func fetchWANHealth() async -> WANHealth? { wanHealthToReturn }
        func fetchGatewayStats(deviceId: String, siteId: String) async -> GatewayStats? { gatewayStatsToReturn }
        func fetchAPStats(deviceId: String, siteId: String) async -> APStats? { apStatsToReturn }
        func fetchSessionHistory(mac: String) async -> [SessionDTO]? { sessionsToReturn }
        func fetchDDNSStatus() async -> (data: [DDNSStatusDTO]?, errorDetail: String?) { ddnsResult }
        func fetchPortForwards() async -> (data: [PortForwardDTO]?, errorDetail: String?) { pfResult }
        func fetchRogueAPs() async -> (data: [RogueAPDTO]?, errorDetail: String?) { rogueResult }
        var certificateChanged: Bool { certChangedFlag }
        func resetCertificatePin() async {}
        func resetSiteCache() async {}
        func invalidate() async { invalidationCount += 1 }
    }

    private func withDefaults(_ check: (UserDefaults) async throws -> Void) async rethrows {
        let suite = "UniFiBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await check(defaults)
    }

    private func makeController(fake: FakeClient, defaults: UserDefaults) -> StatusBarController {
        StatusBarController(
            fixturePreferences: PreferencesManager(defaults: defaults, keychain: FakeKeychain()),
            clientLoader: { fake }
        )
    }

    /// Exercise the real lifecycle, then drain its cancelled loop before inspecting state.
    private func refresh(_ controller: StatusBarController) async {
        await controller.reconfigure()
        let poll = controller.pollTask
        controller.stopPolling()
        await poll?.value
    }

    @Test(.timeLimit(.minutes(1)))
    func testFixtureStartupReconfigureAndTeardown() async throws {
        try await withDefaults { defaults in
            let keychain = FakeKeychain()
            let prefs = PreferencesManager(defaults: defaults, keychain: keychain)
            let first = FakeClient()
            let second = FakeClient()
            var loads = 0
            let controller = StatusBarController(fixturePreferences: prefs) {
                loads += 1
                return loads == 1 ? first : (loads == 2 ? second : nil)
            }
            defer { controller.tearDown() }

            var fetches = first.siteFetches.stream.makeAsyncIterator()
            await controller.start()
            #expect(!controller.hasSystemObservers)
            let poll = try #require(controller.pollTask)
            await fetches.next() // Explicit first poll event, not a timing guess.
            controller.tearDown()
            await poll.value

            #expect(poll.isCancelled)
            #expect(controller.pollTask == nil)
            #expect(await first.siteFetchCount == 1)
            #expect(controller.wifiStatus.isConnected)
            #expect(prefs.isConfigured)
            #expect(!controller.hasSystemObservers)
            #expect(controller.updateChecker.checkNow() == nil)
            #expect(controller.updateChecker.schedulePeriodicCheck() == nil)

            await controller.start() // Idempotent, even after teardown.
            #expect(loads == 1)

            await refresh(controller)
            #expect(loads == 2)
            #expect(await first.invalidationCount == 1)
            #expect(await second.siteFetchCount == 1)
            #expect(controller.wifiStatus.isConnected)
            #expect(!controller.hasSystemObservers)
            #expect(await keychain.readCount == 0)

            await refresh(controller) // A later nil also cannot replace the fixture with a real client.
            #expect(loads == 3)
            #expect(await second.invalidationCount == 1)
            #expect(!prefs.isConfigured)
            #expect(controller.pollTask == nil)
            #expect(await keychain.readCount == 0)
        }
    }

    @Test func testNilFixtureNeverLoadsPreferencesClient() async throws {
        try await withDefaults { defaults in
            let keychain = FakeKeychain()
            // Credentials exist only in the fake: a fallback would be observable as reads.
            try await keychain.save("https://fixture.invalid", for: .controllerURL)
            try await keychain.save("fixture-key", for: .apiKey)
            let prefs = PreferencesManager(defaults: defaults, keychain: keychain)
            prefs.isConfigured = true
            var loads = 0
            let controller = StatusBarController(fixturePreferences: prefs) {
                loads += 1
                return nil
            }
            defer { controller.tearDown() }

            await controller.start()
            #expect(!prefs.isConfigured)
            #expect(controller.pollTask == nil)
            await controller.reconfigure()
            #expect(!prefs.isConfigured)
            #expect(controller.pollTask == nil)
            controller.resetState()
            await controller.start()
            #expect(loads == 3)
            #expect(!prefs.isConfigured)
            #expect(controller.pollTask == nil)
            #expect(!controller.hasSystemObservers)
            #expect(await keychain.readCount == 0)
        }
    }

    // MARK: - Site discovery errors

    @Test func testSiteDiscoveryAuthFailure() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setFetchSiteError(UniFiError.httpError(statusCode: 401))
            let controller = makeController(fake: fake, defaults: defaults)

            await refresh(controller)

            #expect(controller.wifiStatus.errorState == .invalidAPIKey(httpCode: 401))
            #expect(controller.wifiStatus.isConnected == false)
        }
    }

    @Test func testSiteDiscoveryTransientError() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setFetchSiteError(UniFiError.httpError(statusCode: 500))
            let controller = makeController(fake: fake, defaults: defaults)

            await refresh(controller)

            #expect(controller.wifiStatus.errorState == .controllerUnreachable(reason: "UniFiBar.UniFiError code=0"))
            #expect(controller.consecutiveErrorCount == 1)
        }
    }

    @Test func testSiteDiscoveryCertChanged() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setCertChanged(true)
            await fake.setFetchSiteError(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
            let controller = makeController(fake: fake, defaults: defaults)

            await refresh(controller)

            #expect(controller.wifiStatus.errorState == .certChanged)
        }
    }

    // MARK: - Self fetch errors

    @Test func testSelfFetchAuthFailure() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setFetchSelfError(UniFiError.httpError(statusCode: 403))
            let controller = makeController(fake: fake, defaults: defaults)

            await refresh(controller)

            #expect(controller.wifiStatus.errorState == .invalidAPIKey(httpCode: 403))
        }
    }

    @Test func testSelfFetchNotFound() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setFetchSelfError(UniFiError.selfNotFound)
            let controller = makeController(fake: fake, defaults: defaults)

            await refresh(controller)

            #expect(controller.wifiStatus.errorState == .notConnected)
        }
    }

    @Test func testSelfFetchCertChanged() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setCertChanged(true)
            await fake.setFetchSelfError(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
            let controller = makeController(fake: fake, defaults: defaults)

            await refresh(controller)

            #expect(controller.wifiStatus.errorState == .certChanged)
        }
    }

    // MARK: - Successful refresh

    @Test func testSuccessfulRefresh() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            let controller = makeController(fake: fake, defaults: defaults)

            await refresh(controller)

            #expect(!controller.hasSystemObservers) // Reconfigure before start also stays isolated.
            #expect(controller.updateChecker.checkNow() == nil)
            #expect(controller.updateChecker.schedulePeriodicCheck() == nil)
            #expect(controller.wifiStatus.isConnected == true)
            #expect(controller.wifiStatus.isWired == false)
            #expect(controller.wifiStatus.satisfaction == 85)
            #expect(controller.wifiStatus.signal == -50)
            #expect(controller.wifiStatus.apName == "U7 Pro")
            #expect(controller.wifiStatus.essid == "HomeWiFi")
            #expect(controller.wifiStatus.channel == 36)
            #expect(controller.wifiStatus.ip == "192.168.1.5")
            #expect(controller.wifiStatus.wanIsUp == true)
            #expect(controller.wifiStatus.wanISP == "Comcast")
            #expect(controller.wifiStatus.gatewayName == nil)
            #expect(controller.wifiStatus.apCPU == 5.0)
            #expect(controller.wifiStatus.errorState == nil)
            #expect(controller.consecutiveErrorCount == 0)
        }
    }

    @Test func testSuccessfulRefreshDevicesError() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setFetchDevicesError(UniFiError.httpError(statusCode: 500))
            let controller = makeController(fake: fake, defaults: defaults)

            await refresh(controller)

            #expect(controller.wifiStatus.isConnected == true)
            #expect(controller.wifiStatus.satisfaction == 85)
            #expect(controller.wifiStatus.wanIsUp == true)
            #expect(controller.wifiStatus.totalDevices == nil)
        }
    }

    // MARK: - Poll interval

    @Test func testPollIntervalNoErrors() async {
        await withDefaults { defaults in
            let controller = makeController(fake: FakeClient(), defaults: defaults)
            controller.preferences.setPollInterval(30)
            #expect(controller.currentPollInterval == 30)
        }
    }
}
