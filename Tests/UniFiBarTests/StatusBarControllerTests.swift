import Foundation
import os
import Testing
@testable import UniFiBar

@MainActor
struct StatusBarControllerTests {

    private actor FakeClient: UniFiClientProtocol {
        enum Pause: Sendable { case site, selfInfo, monitoring }
        let pausedFetches = AsyncStream<Void>.makeStream()
        private var pause: Pause?
        private var resumeFetch: CheckedContinuation<Void, Never>?
        let sessionStarted = AsyncStream<Void>.makeStream()
        private var waitForSessionCancellation = false
        private(set) var sessionWasCancelled = false
        func suspendSessionsUntilCancelled() { waitForSessionCancellation = true }
        func setMonitoringFailure(_ fails: Bool) {
            ddnsResult = fails ? (nil, "HTTP 500") : ([], nil)
            pfResult = ([], nil)
        }

        func pauseAt(_ point: Pause) { pause = point }
        func resume() {
            pause = nil
            resumeFetch?.resume()
            resumeFetch = nil
        }
        private func waitIfPaused(_ point: Pause) async {
            guard pause == point else { return }
            await withCheckedContinuation {
                resumeFetch = $0
                pausedFetches.continuation.yield(())
            }
        }
        func setSiteId(_ value: String) { siteIdToReturn = value }
        func setDDNSHost(_ host: String) {
            ddnsResult = ([DDNSStatusDTO(status: "good", service: "fixture", hostName: host, login: nil, interface: nil)], nil)
        }
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
            DeviceDTO(id: "d1", macAddress: "11:22:33", name: "U7 Pro", model: "U7-Pro", state: "ONLINE", firmwareUpdatable: nil, features: nil),
            DeviceDTO(id: "d2", macAddress: "44:55:66", name: "U7 In-Wall", model: nil, state: "ONLINE", firmwareUpdatable: nil, features: nil)
        ]
        var wanHealthToReturn = WANHealth(ispName: "Comcast", wanIP: "203.0.113.1", status: "ok", latencyMs: 12, availability: 99.9, drops: 0, rxBytesRate: 1_500_000, txBytesRate: 800_000, speedTest: nil)
        var vpnTunnelsToReturn: [VPNTunnelDTO]? = nil
        var apStatsToReturn = APStats(cpuUtilizationPct: 5.0, memoryUtilizationPct: 30.0)
        var gatewayStatsToReturn = GatewayStats(uptimeSec: 86400, cpuUtilizationPct: 12.0, memoryUtilizationPct: 45.0)
        private(set) var apStatsFetchCount = 0
        private(set) var gatewayStatsFetchCount = 0
        private(set) var deviceStatsFetchCount = 0
        private(set) var sessionFetchCount = 0
        private(set) var devicesFetchCount = 0
        private(set) var wanFetchCount = 0
        private(set) var vpnFetchCount = 0
        func setDevices(_ devices: [DeviceDTO]) { devicesToReturn = devices }
        func setSelfInfo(_ info: SelfInfo) { selfInfoToReturn = info }
        var sessionsToReturn: [SessionDTO]? = nil
        var ddnsResult: (data: [DDNSStatusDTO]?, errorDetail: String?) = (nil, nil)
        var pfResult: (data: [PortForwardDTO]?, errorDetail: String?) = (nil, nil)
        var rogueResult: (data: [RogueAPDTO]?, errorDetail: String?) = (nil, nil)
        var certChangedFlag: Bool = false

        private var _fetchSiteError: Error? = nil
        private var scriptedSiteErrors: [Error?]? = nil
        private var _fetchSelfError: Error? = nil
        private var _fetchDevicesError: Error? = nil

        func setFetchSiteError(_ error: Error?) { _fetchSiteError = error }
        /// Consumed one entry per fetchSiteId call; the fixed error applies once the script ends.
        func setScriptedSiteErrors(_ script: [Error?]) { scriptedSiteErrors = script }
        func setFetchSelfError(_ error: Error?) { _fetchSelfError = error }
        func setFetchDevicesError(_ error: Error?) { _fetchDevicesError = error }
        func setCertChanged(_ flag: Bool) { certChangedFlag = flag }

        func fetchSiteId() async throws -> String {
            siteFetchCount += 1
            siteFetches.continuation.yield(())
            await waitIfPaused(.site)
            if scriptedSiteErrors?.isEmpty == false {
                let outcome = scriptedSiteErrors?.removeFirst() ?? nil
                if let e = outcome { throw e }
                return siteIdToReturn
            }
            if let e = _fetchSiteError { throw e }
            return siteIdToReturn
        }

        func fetchSelfV2() async throws -> SelfInfo {
            await waitIfPaused(.selfInfo)
            if let e = _fetchSelfError { throw e }
            return selfInfoToReturn
        }

        func fetchDevices(siteId: String) async throws -> [DeviceDTO] {
            devicesFetchCount += 1
            if let e = _fetchDevicesError { throw e }
            return devicesToReturn
        }

        func fetchVPNTunnels(siteId: String) async -> [VPNTunnelDTO]? {
            vpnFetchCount += 1
            return vpnTunnelsToReturn
        }
        func fetchWANHealth() async -> WANHealth? {
            wanFetchCount += 1
            return wanHealthToReturn
        }
        func fetchGatewayStats(deviceId: String, siteId: String) async -> GatewayStats? {
            gatewayStatsFetchCount += 1
            return gatewayStatsToReturn
        }
        func fetchAPStats(deviceId: String, siteId: String) async -> APStats? {
            apStatsFetchCount += 1
            return apStatsToReturn
        }
        func fetchDeviceStats(deviceId: String, siteId: String) async -> DeviceStatsSnapshot? {
            deviceStatsFetchCount += 1
            return DeviceStatsSnapshot(apStats: apStatsToReturn, gatewayStats: gatewayStatsToReturn)
        }
        func fetchSessionHistory(mac: String) async -> [SessionDTO]? {
            sessionFetchCount += 1
            if waitForSessionCancellation {
                sessionStarted.continuation.yield(())
                do { try await Task.sleep(for: .seconds(60)) } catch { sessionWasCancelled = Task.isCancelled }
            }
            return sessionsToReturn
        }
        func fetchDDNSStatus() async -> (data: [DDNSStatusDTO]?, errorDetail: String?) {
            await waitIfPaused(.monitoring)
            return ddnsResult
        }
        func fetchPortForwards() async -> (data: [PortForwardDTO]?, errorDetail: String?) { pfResult }
        func fetchRogueAPs() async -> (data: [RogueAPDTO]?, errorDetail: String?) { rogueResult }
        var certificateChanged: Bool { certChangedFlag }
        private var resetError: UniFiError?
        func setResetError() { resetError = .httpError(statusCode: 500) }
        func resetCertificatePin() async throws { if let resetError { throw resetError } }
        func resetSiteCache() async {}
        func invalidate() async { invalidationCount += 1 }
    }

    private func withDefaults(_ check: (UserDefaults) async throws -> Void) async rethrows {
        let suite = "UniFiBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await check(defaults)
    }

    private func makeController(
        fake: FakeClient,
        defaults: UserDefaults,
        sleep: (@Sendable (Duration) async throws -> Void)? = nil,
        now: (@Sendable () -> Date)? = nil
    ) -> StatusBarController {
        StatusBarController(
            fixturePreferences: PreferencesManager(defaults: defaults, keychain: FakeKeychain()),
            sleep: sleep,
            now: now,
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

    @Test(arguments: [false, true])
    func testConnectionValidationAlwaysInvalidatesClient(fails: Bool) async throws {
        try await withDefaults { defaults in
            let validation = FakeClient()
            if fails { await validation.setFetchSiteError(UniFiError.httpError(statusCode: 401)) }
            let controller = makeController(fake: FakeClient(), defaults: defaults)
            let url = try #require(URL(string: "https://new.invalid"))
            do {
                try await controller.connect(using: validation, url: url, apiKey: "synthetic-key", allowSelfSigned: false)
                #expect(!fails)
            } catch { #expect(fails) }
            let poll = controller.pollTask
            controller.tearDown()
            await poll?.value
            #expect(await validation.invalidationCount == 1)
            #expect(controller.preferences.cachedURL == (fails ? nil : url.absoluteString))
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["cancel", "supersede", "reset"])
    func testObsoleteValidationCannotSave(action: String) async throws {
        try await withDefaults { defaults in
            let old = FakeClient()
            await old.pauseAt(.site)
            let prefs = PreferencesManager(defaults: defaults, keychain: FakeKeychain())
            var loads = 0
            let controller = StatusBarController(fixturePreferences: prefs) {
                loads += 1
                return nil
            }
            let url = try #require(URL(string: "https://old.invalid"))
            var paused = old.pausedFetches.stream.makeAsyncIterator()
            let operation = Task {
                try await controller.connect(using: old, url: url, apiKey: "old-key", allowSelfSigned: false)
            }
            await paused.next()
            if action == "cancel" { operation.cancel() }
            // Mirrors reset confirmation's synchronous prefix; native cleanup is not run here.
            if action == "reset" { await controller.resetState()?.value }
            if action == "supersede" {
                let newURL = try #require(URL(string: "https://new.invalid"))
                try await controller.connect(using: FakeClient(), url: newURL, apiKey: "new-key", allowSelfSigned: false)
            }
            await old.resume()
            await #expect(throws: CancellationError.self) { try await operation.value }
            #expect(await old.invalidationCount == (action == "reset" ? 2 : 1))
            #expect(prefs.cachedURL == (action == "supersede" ? "https://new.invalid" : nil))
            #expect(loads == (action == "supersede" ? 1 : 0))
            controller.tearDown()
        }
    }

    @Test func testPinResetFailureKeepsCurrentClient() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setResetError()
            var loads = 0
            let prefs = PreferencesManager(defaults: defaults, keychain: FakeKeychain())
            let controller = StatusBarController(fixturePreferences: prefs) { loads += 1; return fake }
            await controller.start()
            let poll = controller.pollTask
            controller.stopPolling()
            await poll?.value
            await controller.resetCertPin()
            #expect(loads == 1)
            #expect(await fake.invalidationCount == 0)
            #expect(controller.diagnosticsLog.recentEvents(limit: 1).first?.level == .error)
            controller.tearDown()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func testResetBlocksNewConnectionsAndDrainsValidationBeforeCleanup() async throws {
        try await withDefaults { defaults in
            let keychain = FakeKeychain()
            let prefs = PreferencesManager(defaults: defaults, keychain: keychain,
                                           removePins: {}, unregisterLoginItem: {})
            try await prefs.save(controllerURL: "https://old.invalid", apiKey: "old-key", allowSelfSigned: false)
            let active = FakeClient()
            var loads = 0
            let controller = StatusBarController(fixturePreferences: prefs) { loads += 1; return active }
            defer { controller.tearDown() }
            await controller.start()
            let oldPoll = controller.pollTask
            let validation = FakeClient()
            await validation.pauseAt(.site)
            var validationPauses = validation.pausedFetches.stream.makeAsyncIterator()
            let url = try #require(URL(string: "https://new.invalid"))
            let pending = Task {
                try await controller.connect(using: validation, url: url, apiKey: "new-key", allowSelfSigned: false)
            }
            await validationPauses.next()
            await keychain.pauseNext(.delete)
            var deletionPauses = keychain.pauses.stream.makeAsyncIterator()
            let cleanup = controller.resetConfiguration()
            #expect(prefs.isResetting)
            #expect(controller.pollTask == nil)
            let sameCleanup = controller.resetConfiguration()
            #expect(await deletionPauses.next() == .delete)
            #expect(await active.invalidationCount == 1)
            #expect(await validation.invalidationCount == 1)
            let rejected = FakeClient()
            await #expect(throws: CancellationError.self) {
                try await controller.connect(using: rejected, url: url, apiKey: "rejected-key", allowSelfSigned: false)
            }
            #expect(await rejected.siteFetchCount == 0)
            #expect(await rejected.invalidationCount == 1)
            await controller.start()
            await controller.reconfigure()
            #expect(controller.refreshNow() == nil)
            #expect(loads == 1)
            await keychain.resume()
            try await cleanup.value
            try await sameCleanup.value
            await validation.resume() // Late transport completion must not revive the old attempt.
            await #expect(throws: CancellationError.self) { try await pending.value }
            await oldPoll?.value
            #expect(await keychain.deleteCount == KeychainHelper.Key.allCases.count)
            #expect(try await keychain.read(.credentials) == nil)
            #expect(!prefs.isConfigured && !prefs.isResetting)
            #expect(prefs.cachedAPIKey == nil)
            #expect(controller.pollTask == nil && !controller.wifiStatus.isConnected)
            await controller.start()
            await controller.reconfigure()
            #expect(loads == 1) // Reset intent also blocks automatic reconnection after cleanup.
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func testCancellationAfterCommitStartsDoesNotReconnectOrSplitPair() async throws {
        try await withDefaults { defaults in
            let keychain = FakeKeychain()
            let prefs = PreferencesManager(defaults: defaults, keychain: keychain)
            var loads = 0
            let controller = StatusBarController(fixturePreferences: prefs) { loads += 1; return nil }
            let url = try #require(URL(string: "https://committed.invalid"))
            await keychain.pauseNext(.save)
            var pauses = keychain.pauses.stream.makeAsyncIterator()
            let operation = Task {
                try await controller.connect(using: FakeClient(), url: url, apiKey: "committed-key", allowSelfSigned: false)
            }
            #expect(await pauses.next() == .save)
            operation.cancel()
            await keychain.resume()
            await #expect(throws: CancellationError.self) { try await operation.value }
            #expect(loads == 0)
            #expect(controller.pollTask == nil)
            let restored = PreferencesManager(defaults: defaults, keychain: keychain)
            await restored.checkConfiguration()
            #expect(restored.cachedURL == url.absoluteString && restored.cachedAPIKey == "committed-key")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func testUpdateChecksContinueAfterFirstSuccessfulPoll() async {
        await withDefaults { defaults in
            var date = Date(timeIntervalSince1970: 1_788_825_600)
            var checks = 0
            let requests = AsyncStream<Void>.makeStream()
            defer { requests.continuation.finish() }
            var requestSignals = requests.stream.makeAsyncIterator()
            let checker = UpdateChecker(defaults: defaults, now: { date }, fetch: { request in
                checks += 1
                requests.continuation.yield(())
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                let data = Data(#"{"tag_name":"v999.0.0","html_url":"https://github.com/darox/UniFiBar/releases/tag/v999.0.0"}"#.utf8)
                return (data, response)
            })
            let fake = FakeClient()
            let controller = StatusBarController(
                fixturePreferences: PreferencesManager(defaults: defaults, keychain: FakeKeychain()),
                updateChecker: checker, clientLoader: { fake })
            await refresh(controller)
            await requestSignals.next()
            await checker.schedulePeriodicCheck()?.value
            #expect(checks == 1)
            date.addTimeInterval(86_400)
            await controller.refreshNow()?.value
            await requestSignals.next() // The controller must initiate this request, not the test.
            await checker.schedulePeriodicCheck()?.value
            #expect(checks == 2)
            controller.tearDown()
        }
    }

    // MARK: - Site discovery errors

    @Test(.timeLimit(.minutes(1)), arguments: [FakeClient.Pause.site, .selfInfo, .monitoring])
    private func testReconfigureDiscardsOldResponses(point: FakeClient.Pause) async {
        await withDefaults { defaults in
            let old = FakeClient()
            await old.pauseAt(point)
            if point == .site { await old.setFetchSiteError(UniFiError.httpError(statusCode: 401)) }
            if point == .selfInfo { await old.setFetchSelfError(UniFiError.httpError(statusCode: 401)) }
            await old.setDDNSHost("old.invalid")
            let replacement = FakeClient()
            await replacement.setSiteId("new-site")
            await replacement.setDDNSHost("new.invalid")
            let prefs = PreferencesManager(defaults: defaults, keychain: FakeKeychain())
            prefs.setSectionEnabled(.ddns, enabled: true)
            var loads = 0
            let controller = StatusBarController(fixturePreferences: prefs) {
                loads += 1
                return loads == 1 ? old : replacement
            }
            var paused = old.pausedFetches.stream.makeAsyncIterator()
            await controller.start()
            let oldPoll = controller.pollTask
            await paused.next()
            await controller.reconfigure()
            let newPoll = controller.pollTask
            controller.stopPolling()
            await newPoll?.value
            #expect(controller.wifiStatus.isConnected)
            #expect(prefs.siteId == "new-site")
            #expect(controller.wifiStatus.ddnsStatuses?.first?.hostName == "new.invalid")

            await old.resume() // Simulate a transport that completes despite cancellation.
            await oldPoll?.value
            #expect(controller.wifiStatus.isConnected)
            #expect(controller.wifiStatus.errorState == nil)
            #expect(controller.consecutiveErrorCount == 0)
            #expect(controller.wifiStatus.ddnsStatuses?.first?.hostName == "new.invalid")
            controller.tearDown()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func testResetDiscardsPendingMonitoring() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            await fake.pauseAt(.monitoring)
            await fake.setDDNSHost("old.invalid")
            let controller = makeController(fake: fake, defaults: defaults)
            controller.preferences.setSectionEnabled(.ddns, enabled: true)
            var paused = fake.pausedFetches.stream.makeAsyncIterator()
            await controller.start()
            let poll = controller.pollTask
            await paused.next()
            controller.resetState()
            await fake.resume()
            await poll?.value
            #expect(!controller.wifiStatus.isConnected)
            #expect(controller.wifiStatus.ddnsStatuses == nil)
            #expect(controller.wifiStatus.errorState == nil)
            controller.tearDown()
        }
    }

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

            #expect(controller.wifiStatus.errorState == .controllerUnreachable(reason: "Server returned HTTP 500."))
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
            #expect(controller.wifiStatus.dataAvailability[.devices] == .unavailable)
            #expect(controller.wifiStatus.dataAvailability[.gateway] == .unavailable)
            #expect(controller.wifiStatus.dataAvailability[.wan] == .available)
        }
    }

    @Test func optionalFailuresEmptyAndDisabledStatesRecoverIndependently() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            let controller = makeController(fake: fake, defaults: defaults)
            controller.preferences.setSectionEnabled(.ddns, enabled: true)
            controller.preferences.setSectionEnabled(.portForwards, enabled: true)
            await fake.setMonitoringFailure(true)
            await refresh(controller)
            #expect(controller.wifiStatus.isConnected)
            #expect(controller.wifiStatus.dataAvailability[.ddns] == .unavailable)
            #expect(controller.wifiStatus.dataAvailability[.portForwards] == .empty)
            #expect(controller.wifiStatus.dataAvailability[.nearbyAPs] == .disabled)
            await fake.setMonitoringFailure(false)
            await refresh(controller)
            #expect(controller.wifiStatus.dataAvailability[.ddns] == .empty)
            controller.resetState()
            #expect(controller.wifiStatus.dataAvailability.isEmpty)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func stoppingPollingCancelsSessionChildRequest() async throws {
        try await withDefaults { defaults in
            let fake = FakeClient()
            await fake.suspendSessionsUntilCancelled()
            let controller = makeController(fake: fake, defaults: defaults)
            defer { controller.tearDown() }
            var started = fake.sessionStarted.stream.makeAsyncIterator()
            await controller.start()
            let poll = try #require(controller.pollTask)
            await started.next()
            controller.stopPolling()
            await poll.value
            #expect(await fake.sessionWasCancelled)
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

    @Test(.timeLimit(.minutes(1)))
    func successfulPinResetReconfiguresWithFreshClient() async throws {
        try await withDefaults { defaults in
            let first = FakeClient()
            let second = FakeClient()
            var loads = 0
            let controller = StatusBarController(
                fixturePreferences: PreferencesManager(defaults: defaults, keychain: FakeKeychain())
            ) {
                loads += 1
                return loads == 1 ? first : second
            }
            defer { controller.tearDown() }

            await controller.start()
            controller.stopPolling()
            await controller.resetCertPin()

            #expect(loads == 2)
            #expect(await first.invalidationCount == 1)
            #expect(await second.invalidationCount == 0)
            #expect(controller.pollTask != nil)
            #expect(controller.wifiStatus.isConnected)
            #expect(controller.wifiStatus.errorState == nil)
        }
    }

    // MARK: - Connect throttle

    @Test(.timeLimit(.minutes(1)))
    func connectIsThrottledAfterFiveAuthFailures() async throws {
        try await withDefaults { defaults in
            let current = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000_000))
            let controller = makeController(fake: FakeClient(), defaults: defaults, now: { current.withLock { $0 } })
            defer { controller.tearDown() }
            let url = try #require(URL(string: "https://fixture.invalid"))
            let authError = UniFiError.httpError(statusCode: 401)

            for attempt in 1...5 {
                let failing = FakeClient()
                await failing.setFetchSiteError(authError)
                await #expect(throws: authError) {
                    try await controller.connect(using: failing, url: url, apiKey: "k", allowSelfSigned: false)
                }
                #expect(await failing.invalidationCount == 1)
                #expect(controller.connectRetryDeadline == nil || attempt >= 5)
            }
            #expect(controller.connectRetryDeadline != nil)

            let blocked = FakeClient()
            await #expect(throws: UniFiError.throttled(retryInSeconds: 2)) {
                try await controller.connect(using: blocked, url: url, apiKey: "k", allowSelfSigned: false)
            }
            #expect(await blocked.siteFetchCount == 0)
            #expect(await blocked.invalidationCount == 1)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func throttleLiftsAfterDeadlineAndSuccessResetsCounter() async throws {
        try await withDefaults { defaults in
            let current = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000_000))
            let controller = StatusBarController(
                fixturePreferences: PreferencesManager(defaults: defaults, keychain: FakeKeychain()),
                now: { current.withLock { $0 } },
                clientLoader: { FakeClient() }
            )
            defer { controller.tearDown() }
            let url = try #require(URL(string: "https://fixture.invalid"))
            let authError = UniFiError.httpError(statusCode: 403)

            for _ in 1...5 {
                let failing = FakeClient()
                await failing.setFetchSiteError(authError)
                await #expect(throws: authError) {
                    try await controller.connect(using: failing, url: url, apiKey: "k", allowSelfSigned: false)
                }
            }
            #expect(controller.connectRetryDeadline != nil)

            current.withLock { $0.addTimeInterval(31) }
            try await controller.connect(using: FakeClient(), url: url, apiKey: "k", allowSelfSigned: false)
            #expect(controller.connectRetryDeadline == nil)

            // The next failure starts a fresh count instead of resuming the backoff.
            let failing = FakeClient()
            await failing.setFetchSiteError(authError)
            await #expect(throws: authError) {
                try await controller.connect(using: failing, url: url, apiKey: "k", allowSelfSigned: false)
            }
            #expect(controller.connectRetryDeadline == nil)
            controller.tearDown()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func resetClearsTheConnectThrottle() async throws {
        try await withDefaults { defaults in
            let current = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000_000))
            let controller = StatusBarController(
                fixturePreferences: PreferencesManager(defaults: defaults, keychain: FakeKeychain()),
                now: { current.withLock { $0 } },
                clientLoader: { FakeClient() }
            )
            defer { controller.tearDown() }
            let url = try #require(URL(string: "https://fixture.invalid"))
            let authError = UniFiError.httpError(statusCode: 401)

            for _ in 1...5 {
                let failing = FakeClient()
                await failing.setFetchSiteError(authError)
                await #expect(throws: authError) {
                    try await controller.connect(using: failing, url: url, apiKey: "k", allowSelfSigned: false)
                }
            }
            #expect(controller.connectRetryDeadline != nil)

            _ = controller.resetState()
            #expect(controller.connectRetryDeadline == nil)

            // The fresh attempt lands inside the old throttle window and must reach the network.
            let fresh = FakeClient()
            try await controller.connect(using: fresh, url: url, apiKey: "k", allowSelfSigned: false)
            #expect(await fresh.siteFetchCount == 1)
        }
    }

    @Test func connectionErrorMessageMapsAllKnownErrors() {
        #expect(StatusBarController.connectionErrorMessage(for: UniFiError.httpError(statusCode: 401)) ==
                "Authentication failed. Check your API key.")
        #expect(StatusBarController.connectionErrorMessage(for: UniFiError.httpError(statusCode: 403)) ==
                "Authentication failed. Check your API key.")
        #expect(StatusBarController.connectionErrorMessage(for: UniFiError.httpError(statusCode: 500)) ==
                "Server returned HTTP 500. Check your controller URL.")
        #expect(StatusBarController.connectionErrorMessage(for: UniFiError.noSitesFound) ==
                "Connected, but no sites found on this controller.")
        #expect(StatusBarController.connectionErrorMessage(for: UniFiError.throttled(retryInSeconds: 4)) ==
                "Too many failed attempts. Wait 4s before retrying.")
        #expect(StatusBarController.connectionErrorMessage(for: UniFiError.selfNotFound) ==
                "This Mac was not found in the selected site's client list.")
        #expect(StatusBarController.connectionErrorMessage(for: CertificateConnectionError.changedKey) ==
                CertificateConnectionError.changedKey.errorDescription)
        #expect(StatusBarController.connectionErrorMessage(for: URLError(.cannotConnectToHost)) ==
                "Could not reach the controller. Check the URL and your network connection.")
        #expect(StatusBarController.connectionErrorMessage(for: CocoaError(.coderInvalidValue)) ==
                "Connection failed. Check your URL and network settings.")
    }

    // MARK: - Poll loop lifecycle
    //
    // The injected sleep records each requested delay; the poll loop cycles as fast as
    // the fake client answers, so every assertion below is deterministic.

    @Test(.timeLimit(.minutes(1)))
    func pollLoopBacksOffExponentiallyAndCaps() async throws {
        try await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setFetchSiteError(UniFiError.httpError(statusCode: 500))
            let recorded = AsyncStream<Duration>.makeStream()
            let controller = makeController(fake: fake, defaults: defaults) { recorded.continuation.yield($0) }
            defer { controller.tearDown() }
            controller.preferences.setPollInterval(30)
            var delays = recorded.stream.makeAsyncIterator()

            await controller.reconfigure()
            #expect(controller.pollTask != nil)
            #expect(controller.consecutiveErrorCount == 1)

            let d1 = await delays.next()
            let d2 = await delays.next()
            let d3 = await delays.next()
            let d4 = await delays.next()
            #expect(d1 == .seconds(120))
            #expect(d2 == .seconds(240))
            #expect(d3 == .seconds(300))
            #expect(d4 == .seconds(300))
            #expect(controller.consecutiveErrorCount == 4)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func pollLoopBackoffResetsAfterSuccess() async throws {
        try await withDefaults { defaults in
            let fake = FakeClient()
            // reconfigure fails, the first poll iterations fail, then recovery succeeds.
            // The script is actor-ordered, so the loop cannot race the error change.
            let transient = UniFiError.httpError(statusCode: 500)
            await fake.setScriptedSiteErrors([transient, transient, nil])
            let recorded = AsyncStream<Duration>.makeStream()
            let controller = makeController(fake: fake, defaults: defaults) { recorded.continuation.yield($0) }
            defer { controller.tearDown() }
            controller.preferences.setPollInterval(30)
            var delays = recorded.stream.makeAsyncIterator()

            await controller.reconfigure()
            #expect(await delays.next() == .seconds(120))
            #expect(await delays.next() == .seconds(30))
            #expect(controller.consecutiveErrorCount == 0)
            #expect(controller.wifiStatus.isConnected)
            #expect(controller.wifiStatus.errorState == nil)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func certificatePinMismatchBacksOffInsteadOfPollingAtFullRate() async throws {
        try await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setFetchSiteError(URLError(.serverCertificateUntrusted))
            await fake.setCertChanged(true)
            let recorded = AsyncStream<Duration>.makeStream()
            let controller = makeController(fake: fake, defaults: defaults) { recorded.continuation.yield($0) }
            defer { controller.tearDown() }
            controller.preferences.setPollInterval(30)
            var delays = recorded.stream.makeAsyncIterator()

            await controller.reconfigure()
            #expect(controller.wifiStatus.errorState == .certChanged)

            let d1 = await delays.next()
            let d2 = await delays.next()
            #expect(d1 == .seconds(120))
            #expect(d2 == .seconds(240))
            #expect(controller.wifiStatus.errorState == .certChanged)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func pollLoopStopsAfterAuthFailure() async throws {
        try await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setFetchSiteError(UniFiError.httpError(statusCode: 401))
            let controller = makeController(fake: fake, defaults: defaults)
            defer { controller.tearDown() }

            await controller.reconfigure()
            let poll = try #require(controller.pollTask)
            await poll.value

            #expect(controller.pollTask == nil)
            #expect(controller.wifiStatus.errorState == .invalidAPIKey(httpCode: 401))
            #expect(controller.consecutiveErrorCount == 0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func manualRefreshRestartsPollingAfterAuthFailureRecovery() async throws {
        try await withDefaults { defaults in
            let fake = FakeClient()
            await fake.setFetchSiteError(UniFiError.httpError(statusCode: 403))
            let controller = makeController(fake: fake, defaults: defaults) { _ in }
            defer { controller.tearDown() }

            await controller.reconfigure()
            if let poll = controller.pollTask { await poll.value }
            #expect(controller.pollTask == nil)

            await fake.setFetchSiteError(nil)
            let manual = try #require(controller.refreshNow())
            await manual.value

            #expect(controller.pollTask != nil)
            #expect(controller.wifiStatus.isConnected)
            #expect(controller.wifiStatus.errorState == nil)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func tearDownDuringInFlightRefreshDiscardsResults() async throws {
        try await withDefaults { defaults in
            let fake = FakeClient()
            await fake.pauseAt(.selfInfo)
            let controller = makeController(fake: fake, defaults: defaults)

            await controller.start()
            let poll = try #require(controller.pollTask)
            var paused = fake.pausedFetches.stream.makeAsyncIterator()
            await paused.next()

            controller.tearDown()
            await fake.resume()
            await poll.value

            #expect(controller.pollTask == nil)
            #expect(controller.wifiStatus.isConnected == false)
            #expect(controller.wifiStatus.errorState == nil)
        }
    }

    @Test func sharedAPAndGatewayDeviceIsFetchedOnce() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            // One integrated device is both this Mac's AP and the gateway.
            await fake.setDevices([
                DeviceDTO(id: "shared", macAddress: "11:22:33", name: "Dream Router", model: "UDR",
                          state: "ONLINE", firmwareUpdatable: nil, features: ["gateway"])
            ])
            let controller = makeController(fake: fake, defaults: defaults)
            await refresh(controller)

            #expect(await fake.deviceStatsFetchCount == 1)
            #expect(await fake.apStatsFetchCount == 0)
            #expect(await fake.gatewayStatsFetchCount == 0)
            #expect(controller.wifiStatus.apCPU == 5.0)
            #expect(controller.wifiStatus.gatewayCPU == 12.0)
            controller.tearDown()
        }
    }

    @Test func wiredClientDoesNotRequestSessionHistory() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            let wired = V2ClientDTO(ip: "192.168.1.5", mac: "aa:bb:cc", hostname: nil, displayName: "MacBook",
                                    signal: nil, rssi: nil, noise: nil, satisfaction: nil,
                                    wifiExperienceScore: nil, wifiExperienceAverage: nil,
                                    wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil,
                                    radioProto: nil, radio: nil, essid: nil, apMac: nil,
                                    lastUplinkName: nil, rxRate: nil, txRate: nil, rxBytes: nil,
                                    txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
            await fake.setSelfInfo(SelfInfo(client: wired, totalClients: 3, clientsOnSameAP: 1))
            let controller = makeController(fake: fake, defaults: defaults)
            await refresh(controller)

            #expect(await fake.sessionFetchCount == 0)
            #expect(controller.wifiStatus.dataAvailability[.sessions] == .notApplicable)
            controller.tearDown()
        }
    }

    @Test func credentialFlowValidatesFirstAndTrimsTheKey() async {
        await withDefaults { defaults in
            let controller = makeController(fake: FakeClient(), defaults: defaults)
            var built = 0

            let invalid = await CredentialFlow.connect(
                controller: controller, urlString: "not a url", apiKey: " key ", allowSelfSigned: false
            ) { _, _, _ in
                built += 1
                return FakeClient()
            }
            guard case .urlInvalid = invalid else {
                Issue.record("expected urlInvalid, got \(invalid)")
                return
            }
            #expect(built == 0)

            let connected = await CredentialFlow.connect(
                controller: controller, urlString: "https://controller.invalid", apiKey: " key ", allowSelfSigned: false
            ) { url, key, selfSigned in
                built += 1
                #expect(url.absoluteString == "https://controller.invalid")
                #expect(key == "key")
                #expect(selfSigned == false)
                return FakeClient()
            }
            guard case .connected = connected else {
                Issue.record("expected connected, got \(connected)")
                return
            }
            #expect(built == 1)
            #expect(controller.preferences.cachedAPIKey == "key")

            let poll = controller.pollTask
            controller.tearDown()
            await poll?.value
        }
    }

    @Test func hiddenCoreSectionsSkipTheirRequests() async {
        await withDefaults { defaults in
            let fake = FakeClient()
            let prefs = PreferencesManager(defaults: defaults, keychain: FakeKeychain())
            for section in [MenuSection.internet, .vpn, .sessionHistory, .wifi, .network] {
                prefs.setSectionEnabled(section, enabled: false)
            }
            let controller = StatusBarController(fixturePreferences: prefs, clientLoader: { fake })
            await refresh(controller)

            #expect(await fake.devicesFetchCount == 0)
            #expect(await fake.wanFetchCount == 0)
            #expect(await fake.vpnFetchCount == 0)
            #expect(await fake.sessionFetchCount == 0)
            #expect(await fake.apStatsFetchCount == 0)
            #expect(await fake.gatewayStatsFetchCount == 0)
            #expect(controller.wifiStatus.dataAvailability[.wan] == .disabled)
            #expect(controller.wifiStatus.dataAvailability[.vpn] == .disabled)
            #expect(controller.wifiStatus.dataAvailability[.sessions] == .disabled)
            #expect(controller.wifiStatus.dataAvailability[.accessPoint] == .disabled)
            #expect(controller.wifiStatus.dataAvailability[.devices] == .disabled)
            controller.tearDown()
        }
    }
}
