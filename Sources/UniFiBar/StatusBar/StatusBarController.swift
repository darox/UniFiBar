import Foundation
import Network
import os
import SwiftUI

/// Thread-safe flag that returns false on the first call, true on subsequent calls.
private final class SkipFirstFlag: Sendable {
    private let hasFired = OSAllocatedUnfairLock(initialState: false)
    func check() -> Bool {
        hasFired.withLock { fired in
            if !fired {
                fired = true
                return false
            }
            return true
        }
    }
}

/// Allows the polling client to ask the user to trust a certificate only after an
/// explicit pin reset. The permission is consumed by the first challenge, so normal
/// background polling never prompts and a changed key still fails closed.
final class TrustPromptGate: Sendable {
    private struct State: Sendable { var armed = false }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let prompt: @Sendable (PinnedCertDelegate.CertificateDetails) async -> Bool

    init(prompt: @escaping @Sendable (PinnedCertDelegate.CertificateDetails) async -> Bool) {
        self.prompt = prompt
    }

    func arm() {
        state.withLock { $0.armed = true }
    }

    func consume(_ details: PinnedCertDelegate.CertificateDetails) async -> Bool {
        let allowed = state.withLock { state -> Bool in
            guard state.armed else { return false }
            state.armed = false
            return true
        }
        guard allowed else { return false }
        return await prompt(details)
    }
}

@MainActor
@Observable
final class StatusBarController {
    let wifiStatus = WiFiStatus()
    let preferences: PreferencesManager
    let diagnosticsLog = DiagnosticsLog()
    let updateChecker: UpdateChecker
    private let loadClient: @MainActor () async -> UniFiClientProtocol?
    private let trustPrompt: TrustPromptGate?
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date
    private let observesSystemEvents: Bool

    init(
        preferences: PreferencesManager = PreferencesManager(),
        certificatePrompt: (@Sendable (PinnedCertDelegate.CertificateDetails) async -> Bool)? = { details in
            await confirmControllerCertificate(details)
        }
    ) {
        self.preferences = preferences
        let gate = certificatePrompt.map(TrustPromptGate.init(prompt:))
        trustPrompt = gate
        if let gate {
            let confirm: @Sendable (PinnedCertDelegate.CertificateDetails) async -> Bool = { details in
                await gate.consume(details)
            }
            loadClient = { await preferences.loadClient(confirmCertificate: confirm) }
        } else {
            loadClient = { await preferences.loadClient() }
        }
        updateChecker = UpdateChecker()
        sleep = { try await Task.sleep(for: $0) }
        now = { Date() }
        observesSystemEvents = true
    }

    /// Unit fixtures must supply isolated defaults, a fake Keychain, and only fake clients.
    /// A nil loader result stays unconfigured; it never falls back to native services.
    init(
        fixturePreferences: PreferencesManager,
        updateChecker: UpdateChecker? = nil,
        sleep: (@Sendable (Duration) async throws -> Void)? = nil,
        now: (@Sendable () -> Date)? = nil,
        clientLoader: @escaping @MainActor () async -> UniFiClientProtocol?
    ) {
        preferences = fixturePreferences
        trustPrompt = nil
        loadClient = clientLoader
        self.updateChecker = updateChecker ?? UpdateChecker(checksEnabled: false)
        self.sleep = sleep ?? { try await Task.sleep(for: $0) }
        self.now = now ?? { Date() }
        observesSystemEvents = false
    }

    private static let logger = Logger(subsystem: "com.unifbar.app", category: "StatusBarController")

    private(set) var pollTask: Task<Void, Never>?
    private var client: UniFiClientProtocol?

    private var pathMonitor: NWPathMonitor?
    private var wakeObserver: NSObjectProtocol?
    var hasSystemObservers: Bool { pathMonitor != nil || wakeObserver != nil }
    private var hasStarted = false
    private var consecutiveErrors = 0
    private var failedConnectAttempts = 0
    private var connectRetryAvailableAt: Date?
    private var hasTornDown = false
    private var authFailed = false
    private var lastManualRefresh: Date = .distantPast
    private var successCount = 0
    private var isRefreshing = false
    private var refreshGeneration = 0
    private var connectionGeneration = 0
    private var validationClients: [Int: UniFiClientProtocol] = [:]

    var consecutiveErrorCount: Int { consecutiveErrors }
    var currentPollInterval: Int { pollInterval }

    /// Tears down observers. Must be called on @MainActor before the object is released,
    /// since @Observable types have nonisolated deinit which cannot access actor-isolated state.
    func tearDown() {
        // Pending wake, path, and manual-refresh tasks re-check these generations and
        // must observe the teardown instead of writing state or restarting polling.
        // A handler task that starts after the bump would read the new generation, so
        // the flag is the part that survives that race.
        hasTornDown = true
        connectionGeneration += 1
        refreshGeneration += 1
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
        pathMonitor?.cancel()
        pathMonitor = nil
        pollTask?.cancel()
        pollTask = nil
    }

    func start() async {
        guard !hasStarted, preferences.automaticConnectionAllowed else { return }
        hasStarted = true

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString
        diagnosticsLog.record(.system, level: .info, message: "UniFiBar started", detail: "v\(version) macOS \(macOS)")

        let gen = refreshGeneration
        let loadedClient = await loadClient()
        guard gen == refreshGeneration else {
            await loadedClient?.invalidate()
            return
        }
        client = loadedClient
        preferences.isConfigured = client != nil
        guard client != nil else { return }
        startPolling()
        observeSystemEvents()
    }

    func reconfigure() async {
        guard preferences.automaticConnectionAllowed else { return }
        stopPolling()
        refreshGeneration += 1
        let gen = refreshGeneration
        isRefreshing = false
        successCount = 0
        wifiStatus.clearState()
        // Reset error state so new credentials get a clean start
        authFailed = false
        consecutiveErrors = 0
        // Invalidate old URLSession to release delegate and cancel in-flight requests
        let oldClient = client
        client = nil
        await oldClient?.invalidate()
        guard gen == refreshGeneration else { return }
        let loadedClient = await loadClient()
        guard gen == refreshGeneration else {
            await loadedClient?.invalidate()
            return
        }
        client = loadedClient
        preferences.isConfigured = client != nil
        if client != nil {
            await refresh(generation: gen)
            guard gen == refreshGeneration else { return }
            startPolling()
            observeSystemEvents()
        }
        hasStarted = true
    }

    /// Shared setup/preferences flow. Callers supply the temporary validation client.
    /// Auth failures are throttled client-side after five attempts; both the setup and
    /// preferences connect flows go through here, so neither can hammer the endpoint.
    func connect(using testClient: UniFiClientProtocol, url: URL, apiKey: String, allowSelfSigned: Bool) async throws {
        guard !preferences.isResetting else {
            await testClient.invalidate()
            throw CancellationError()
        }
        let now = self.now()
        if let until = connectRetryAvailableAt, now < until {
            await testClient.invalidate()
            throw UniFiError.throttled(retryInSeconds: max(1, Int(until.timeIntervalSince(now))))
        }
        connectionGeneration += 1
        let generation = connectionGeneration
        validationClients[generation] = testClient
        let validation: Result<String, Error>
        do {
            try Task.checkCancellation()
            validation = .success(try await testClient.fetchSiteId())
        } catch {
            validation = .failure(error)
        }
        await testClient.invalidate()
        validationClients[generation] = nil
        try Task.checkCancellation()
        guard generation == connectionGeneration else { throw CancellationError() }
        let siteId: String
        do {
            siteId = try validation.get()
        } catch {
            noteFailedConnectAttempt(error)
            throw error
        }
        failedConnectAttempts = 0
        connectRetryAvailableAt = nil
        // Once persistence starts, cancellation is not a rollback of already-written credentials.
        try await preferences.save(controllerURL: url.absoluteString, apiKey: apiKey, allowSelfSigned: allowSelfSigned,
                                   isCurrent: { generation == self.connectionGeneration })
        try Task.checkCancellation()
        guard generation == connectionGeneration else { throw CancellationError() }
        preferences.siteId = siteId
        await reconfigure()
    }

    /// After five consecutive authentication failures, delay further attempts with a
    /// small exponential backoff capped at 30 seconds.
    private func noteFailedConnectAttempt(_ error: Error) {
        guard case UniFiError.httpError(let code) = error, code == 401 || code == 403 else { return }
        failedConnectAttempts += 1
        guard failedConnectAttempts >= 5 else { return }
        let delay = min(pow(2.0, Double(failedConnectAttempts - 4)), 30.0)
        connectRetryAvailableAt = now().addingTimeInterval(delay)
    }

    /// When a connect attempt is throttled, the time the next attempt opens up.
    var connectRetryDeadline: Date? { connectRetryAvailableAt }

    /// Maps connect-flow errors to user-facing copy. Shared by SetupView and PreferencesView.
    nonisolated static func connectionErrorMessage(for error: Error) -> String {
        switch error {
        case let error as UniFiError:
            switch error {
            case .httpError(let code) where code == 401 || code == 403:
                return "Authentication failed. Check your API key."
            case .httpError(let code):
                return "Server returned HTTP \(code). Check your controller URL."
            case .noSitesFound:
                return "Connected, but no sites found on this controller."
            default:
                return error.errorDescription ?? error.localizedDescription
            }
        case let error as CertificateConnectionError:
            return error.errorDescription ?? error.localizedDescription
        case is URLError:
            return "Could not reach the controller. Check the URL and your network connection."
        case let error as KeychainError:
            return error.errorDescription ?? error.localizedDescription
        default:
            return "Connection failed. Check your URL and network settings."
        }
    }

    @discardableResult
    func refreshNow() -> Task<Void, Never>? {
        guard preferences.automaticConnectionAllowed else { return nil }
        let now = Date()
        guard now.timeIntervalSince(lastManualRefresh) >= 5 else { return nil }
        lastManualRefresh = now
        authFailed = false
        let gen = refreshGeneration
        return Task { [weak self] in
            guard let self else { return }
            await refresh(generation: gen)
            // A manual refresh that succeeds after the loop stopped (auth failure)
            // must bring polling back; the wake/path handlers already do this.
            guard gen == refreshGeneration, !Task.isCancelled, !authFailed, pollTask == nil else { return }
            startPolling()
        }
    }

    func resetCertPin() async {
        guard preferences.automaticConnectionAllowed, let client else { return }
        let generation = refreshGeneration
        do {
            try await client.resetCertificatePin()
        } catch {
            diagnosticsLog.record(.certificate, level: .error, message: "Could not reset certificate pin; existing trust preserved")
            return
        }
        guard generation == refreshGeneration, preferences.automaticConnectionAllowed else { return }
        // A name-mismatched self-signed certificate cannot re-pin without a prompt, so
        // arm exactly one for the fresh delegate the user just asked for.
        trustPrompt?.arm()
        await reconfigure()
    }

    /// Used by both reset UI and fixtures; admission closes before returning the cleanup task.
    func resetConfiguration() -> Task<Void, Error> {
        if preferences.isResetting { return preferences.resetAll() }
        let invalidation = resetState()
        return preferences.resetAll(after: invalidation)
    }

    @discardableResult
    func resetState() -> Task<Void, Never>? {
        connectionGeneration += 1
        stopPolling()
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
        pathMonitor?.cancel()
        pathMonitor = nil
        // Invalidate URLSession to release delegate and cancel in-flight requests
        var oldClients = Array(validationClients.values)
        validationClients.removeAll()
        if let client { oldClients.append(client) }
        client = nil
        authFailed = false
        consecutiveErrors = 0
        successCount = 0
        failedConnectAttempts = 0
        connectRetryAvailableAt = nil
        isRefreshing = false
        refreshGeneration += 1
        hasStarted = false
        wifiStatus.clearState()
        guard !oldClients.isEmpty else { return nil }
        return Task { for oldClient in oldClients { await oldClient.invalidate() } }
    }

    private func startPolling() {
        guard !hasTornDown, preferences.automaticConnectionAllowed, client != nil else { return }
        pollTask?.cancel()
        let gen = refreshGeneration
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && gen == self.refreshGeneration {
                await self.refresh(generation: gen)
                guard !Task.isCancelled, gen == self.refreshGeneration else { return }
                // Stop polling if auth has permanently failed — user must fix credentials
                if self.authFailed {
                    // Clear the stale reference so wake/network handlers can restart polling
                    // after credentials are fixed via reconfigure()
                    self.pollTask = nil
                    return
                }
                let delay = self.pollInterval
                try? await self.sleep(.seconds(delay))
            }
        }
    }

    /// Returns poll interval: user-configured normally, backs off up to 5 minutes on transient errors.
    /// Auth failures don't back off — they stop polling entirely.
    private var pollInterval: Int {
        guard consecutiveErrors > 0 else { return preferences.pollIntervalSeconds }
        return min(preferences.pollIntervalSeconds * (1 << min(consecutiveErrors, 4)), 300)
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Restarts the polling loop so a new poll interval takes effect immediately.
    func restartPolling() {
        guard pollTask != nil else { return }
        stopPolling()
        startPolling()
    }

    private func observeSystemEvents() {
        guard preferences.automaticConnectionAllowed, observesSystemEvents, !hasSystemObservers else { return }
        // Wake from sleep — wait for network, then refresh with reset backoff
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let gen = self.refreshGeneration
                // Backoff resets on successful refresh only; clearing it here would
                // let a flapping network poll an unreachable controller at full cadence.
                // The 8 s wait lets Wi-Fi reassociate after wake before refreshing.
                try? await self.sleep(.seconds(8))
                guard gen == self.refreshGeneration, !self.hasTornDown, self.client != nil else { return }
                await self.refresh(generation: gen)
                guard gen == self.refreshGeneration else { return }
                // If still failing, restart normal polling
                if !self.authFailed && self.pollTask == nil {
                    self.startPolling()
                }
            }
        }

        // Network path changes — skip the initial fire, only react to actual changes
        let monitor = NWPathMonitor()
        let skipFirst = SkipFirstFlag()
        monitor.pathUpdateHandler = { [weak self] path in
            guard skipFirst.check() else { return }
            guard let self, path.status == .satisfied else { return }
            Task { @MainActor in
                let gen = self.refreshGeneration
                guard !self.hasTornDown, self.client != nil else { return }
                await self.refresh(generation: gen)
                guard gen == self.refreshGeneration else { return }
                // If polling had stopped (auth failure), don't restart
                if !self.authFailed && self.pollTask == nil {
                    self.startPolling()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.unifbar.pathmonitor"))
        pathMonitor = monitor
    }

    private func refresh(generation: Int) async {
        // Guard against overlapping refresh calls from poll loop + wake/network events
        let gen = generation
        guard preferences.automaticConnectionAllowed, gen == refreshGeneration, !isRefreshing else { return }
        isRefreshing = true
        defer { if gen == refreshGeneration { isRefreshing = false } }

        updateChecker.schedulePeriodicCheck()

        guard let client else {
            wifiStatus.markError(.controllerUnreachable(reason: "Not configured"))
            return
        }

        // Ensure site is discovered (needed for all site-scoped calls)
        let siteId: String
        do {
            siteId = try await client.fetchSiteId()
            guard gen == refreshGeneration else { return }
            if preferences.siteId != siteId {
                preferences.siteId = siteId
            }
        } catch let error as UniFiError {
            guard gen == refreshGeneration else { return }
            switch error {
            case .httpError(let code) where code == 401 || code == 403:
                Self.logger.error("Auth failed during site discovery (HTTP \(code))")
                diagnosticsLog.record(.authentication, level: .error, message: "Auth failed during site discovery", detail: "HTTP \(code)")
                authFailed = true
                consecutiveErrors = 0
                wifiStatus.markError(.invalidAPIKey(httpCode: code))
            default:
                Self.logger.error("Site discovery failed: \((error as NSError).domain) code=\((error as NSError).code)")
                let detail = "\((error as NSError).domain) code=\((error as NSError).code)"
                diagnosticsLog.record(.connection, level: .error, message: "Site discovery failed", detail: detail)
                consecutiveErrors = min(consecutiveErrors + 1, 4)
                wifiStatus.markError(.controllerUnreachable(reason: Self.reasonFromError(error)))
            }
            await client.resetSiteCache()
            return
        } catch {
            let certChanged = await client.certificateChanged
            guard gen == refreshGeneration else { return }
            if certChanged {
                Self.logger.warning("Certificate pin mismatch detected — cert may have been renewed")
                diagnosticsLog.record(.certificate, level: .warning, message: "Certificate pin mismatch detected")
                consecutiveErrors = min(consecutiveErrors + 1, 4)
                wifiStatus.markError(.certChanged)
                await client.resetSiteCache()
                return
            }
            let detail = "\((error as NSError).domain) code=\((error as NSError).code)"
            Self.logger.error("Site discovery failed: \(detail)")
            diagnosticsLog.record(.connection, level: .error, message: "Site discovery failed", detail: detail)
            consecutiveErrors = min(consecutiveErrors + 1, 4)
            wifiStatus.markError(.controllerUnreachable(reason: Self.reasonFromError(error)))
            await client.resetSiteCache()
            return
        }

        // Primary call: get this Mac's WiFi details + network overview
        let selfInfo: SelfInfo
        do {
            selfInfo = try await client.fetchSelfV2()
        } catch let error as UniFiError {
            guard gen == refreshGeneration else { return }
            switch error {
            case .httpError(let code) where code == 401 || code == 403:
                Self.logger.error("Authentication failed (HTTP \(code))")
                diagnosticsLog.record(.authentication, level: .error, message: "Authentication failed", detail: "HTTP \(code)")
                authFailed = true
                consecutiveErrors = 0
                wifiStatus.markError(.invalidAPIKey(httpCode: code))
            case .selfNotFound:
                Self.logger.info("This device not found in active clients — likely disconnected")
                diagnosticsLog.record(.connection, level: .info, message: "Device not found in active clients")
                wifiStatus.markDisconnected()
            default:
                Self.logger.error("Failed to fetch self: \((error as NSError).domain) code=\((error as NSError).code)")
                let detail = "\((error as NSError).domain) code=\((error as NSError).code)"
                diagnosticsLog.record(.connection, level: .error, message: "Failed to fetch self", detail: detail)
                consecutiveErrors = min(consecutiveErrors + 1, 4)
                wifiStatus.markError(.controllerUnreachable(reason: Self.reasonFromError(error)))
            }
            return
        } catch {
            let certChanged = await client.certificateChanged
            guard gen == refreshGeneration else { return }
            if certChanged {
                Self.logger.warning("Certificate pin mismatch detected — cert may have been renewed")
                diagnosticsLog.record(.certificate, level: .warning, message: "Certificate pin mismatch detected")
                consecutiveErrors = min(consecutiveErrors + 1, 4)
                wifiStatus.markError(.certChanged)
                return
            }
            consecutiveErrors = min(consecutiveErrors + 1, 4)
            let detail = "\((error as NSError).domain) code=\((error as NSError).code)"
            Self.logger.error("Failed to fetch self: \(detail)")
            diagnosticsLog.record(.connection, level: .error, message: "Failed to fetch self", detail: detail)
            wifiStatus.markError(.controllerUnreachable(reason: Self.reasonFromError(error)))
            return
        }

        guard gen == refreshGeneration else { return }
        consecutiveErrors = 0
        authFailed = false
        wifiStatus.update(from: selfInfo)
        wifiStatus.beginSupplementalRefresh()

        successCount += 1
        if successCount % 10 == 0 {
            diagnosticsLog.record(.connection, level: .info, message: "Poll succeeded", detail: "\(successCount) consecutive")
        }

        let me = selfInfo.client

        // Skip the network work for sections the user hid. Hidden sections never display data.
        let wantWAN = preferences.isSectionEnabled(.internet)
        let wantVPN = preferences.isSectionEnabled(.vpn)
        let wantSessions = preferences.isSectionEnabled(.sessionHistory)
        let wantAP = preferences.isSectionEnabled(.wifi)
        let wantDevices = wantWAN || wantAP || preferences.isSectionEnabled(.network)

        // Parallel batch 1: devices, WAN health, VPN tunnels, session history
        async let devicesTask: [DeviceDTO]? = wantDevices ? await fetchDevicesLogged(client: client, siteId: siteId) : nil
        async let wanHealthTask: WANHealth? = wantWAN ? await client.fetchWANHealth() : nil
        async let vpnTask: [VPNTunnelDTO]? = wantVPN ? await client.fetchVPNTunnels(siteId: siteId) : nil
        async let sessionsTask: [SessionDTO]? = {
            // A wired client has no AP session to summarize; skip the request rather than discard it.
            guard wantSessions, let mac = me.mac, !selfInfo.isWired else { return nil }
            return await client.fetchSessionHistory(mac: mac)
        }()

        let devices = await devicesTask
        let wanHealth = await wanHealthTask
        let tunnels = await vpnTask
        let sessions = await sessionsTask

        guard gen == refreshGeneration, !Task.isCancelled else { return }
        wifiStatus.updateDevices(devices)
        wifiStatus.updateWANHealth(wanHealth)
        wifiStatus.updateVPN(tunnels)
        wifiStatus.updateSessions(sessions, devices: devices ?? [])
        if me.mac == nil || selfInfo.isWired { wifiStatus.dataAvailability[.sessions] = .notApplicable }

        // Parallel batch 2: AP stats + gateway stats (depend on devices result)
        let apDevice = me.apMac.flatMap { apMac in
            devices?.first(where: { $0.mac?.lowercased() == apMac.lowercased() })
        }
        let gwDevice = devices?.first(where: \.isGateway)
            ?? devices?.first(where: { me.gwMac != nil && $0.mac?.lowercased() == me.gwMac?.lowercased() })

        let apId = apDevice?.id
        let gwId = gwDevice?.id
        let wantAPStats = wantAP && apId != nil
        let wantGWStats = wantWAN && gwId != nil

        let apStats: APStats?
        let gwStats: GatewayStats?
        if let apId, let gwId, apId == gwId, wantAPStats || wantGWStats {
            // Integrated gateways expose the AP as the same device. One payload yields both projections.
            let snapshot = await client.fetchDeviceStats(deviceId: apId, siteId: siteId)
            apStats = wantAPStats ? snapshot?.apStats : nil
            gwStats = wantGWStats ? snapshot?.gatewayStats : nil
        } else {
            async let apStatsTask: APStats? = {
                guard wantAPStats, let apId else { return nil }
                return await client.fetchAPStats(deviceId: apId, siteId: siteId)
            }()
            async let gwStatsTask: GatewayStats? = {
                guard wantGWStats, let gwId else { return nil }
                return await client.fetchGatewayStats(deviceId: gwId, siteId: siteId)
            }()
            apStats = await apStatsTask
            gwStats = await gwStatsTask
        }

        guard gen == refreshGeneration, !Task.isCancelled else { return }
        wifiStatus.updateAPStats(apStats)
        wifiStatus.updateGateway(gwStats, device: gwDevice)
        if selfInfo.isWired { wifiStatus.dataAvailability[.accessPoint] = .notApplicable }
        if devices != nil, gwDevice == nil { wifiStatus.dataAvailability[.gateway] = .notApplicable }

        // A hidden section keeps a disabled marker even though nothing rendered it.
        if !wantWAN {
            wifiStatus.dataAvailability[.wan] = .disabled
            wifiStatus.dataAvailability[.gateway] = .disabled
        }
        if !wantVPN { wifiStatus.dataAvailability[.vpn] = .disabled }
        if !wantSessions { wifiStatus.dataAvailability[.sessions] = .disabled }
        if !wantAP { wifiStatus.dataAvailability[.accessPoint] = .disabled }
        if !wantDevices { wifiStatus.dataAvailability[.devices] = .disabled }

        // Parallel batch 3: monitoring data (only fetch enabled sections)
        await fetchMonitoringData(client: client, generation: gen)
    }

    /// Devices fetch with its failure recorded; returns nil so a caller can still render the rest.
    private func fetchDevicesLogged(client: UniFiClientProtocol, siteId: String) async -> [DeviceDTO]? {
        do {
            return try await client.fetchDevices(siteId: siteId)
        } catch {
            let detail = "\((error as NSError).domain) code=\((error as NSError).code)"
            Self.logger.error("Devices fetch failed: \(detail)")
            diagnosticsLog.record(.connection, level: .error, message: "Devices fetch failed", detail: detail)
            return nil
        }
    }

    /// Maps network errors to human-readable reasons for the UI.
    private static func reasonFromError(_ error: Error) -> String? {
        if let error = error as? CertificateConnectionError { return error.errorDescription }
        if let error = error as? UniFiError { return error.errorDescription }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return "\(nsError.domain) code=\(nsError.code)"
        }
        switch nsError.code {
        case NSURLErrorCannotFindHost: return "DNS lookup failed"
        case NSURLErrorDNSLookupFailed: return "DNS lookup failed"
        case NSURLErrorTimedOut: return "Connection timed out"
        case NSURLErrorCannotConnectToHost: return "Connection refused"
        case NSURLErrorNetworkConnectionLost: return "Network connection lost"
        case NSURLErrorNotConnectedToInternet: return "No internet connection"
        case NSURLErrorSecureConnectionFailed: return "TLS handshake failed"
        case NSURLErrorServerCertificateHasBadDate: return "Server certificate expired"
        case NSURLErrorServerCertificateUntrusted: return "Server certificate untrusted"
        case NSURLErrorServerCertificateHasUnknownRoot: return "Self-signed certificate"
        case NSURLErrorClientCertificateRejected: return "Client certificate rejected"
        default: return "Network error (\(nsError.code))"
        }
    }

    /// Fetches optional monitoring data based on which sections are enabled in preferences.
    /// Each call is independent; unavailable data is shown separately from empty responses.
    private func fetchMonitoringData(client: UniFiClientProtocol, generation: Int) async {
        // Evaluate section visibility on @MainActor before spawning child tasks
        let wantDDNS = preferences.isSectionEnabled(.ddns)
        let wantPF = preferences.isSectionEnabled(.portForwards)
        let wantRogue = preferences.isSectionEnabled(.nearbyAPs)

        async let ddnsResult = wantDDNS ? await client.fetchDDNSStatus() : (data: nil as [DDNSStatusDTO]?, errorDetail: nil)
        async let pfResult = wantPF ? await client.fetchPortForwards() : (data: nil as [PortForwardDTO]?, errorDetail: nil)
        async let rogueResult = wantRogue ? await client.fetchRogueAPs() : (data: nil as [RogueAPDTO]?, errorDetail: nil)

        let ddns = await ddnsResult
        let pf = await pfResult
        let rogue = await rogueResult
        guard generation == refreshGeneration, !Task.isCancelled else { return }

        if wantDDNS, let error = ddns.errorDetail {
            diagnosticsLog.record(.monitoring, level: .error, message: "DDNS fetch failed", detail: error)
        }
        if wantPF, let error = pf.errorDetail {
            diagnosticsLog.record(.monitoring, level: .error, message: "Port forwards fetch failed", detail: error)
        }
        if wantRogue, let error = rogue.errorDetail {
            diagnosticsLog.record(.monitoring, level: .error, message: "Rogue APs fetch failed", detail: error)
        }

        wifiStatus.updateMonitoring(
            ddns: ddns.errorDetail == nil ? ddns.data : nil,
            portForwards: pf.errorDetail == nil ? pf.data : nil,
            rogueAPs: rogue.errorDetail == nil ? rogue.data : nil
        )
        if !wantDDNS { wifiStatus.dataAvailability[.ddns] = .disabled }
        if !wantPF { wifiStatus.dataAvailability[.portForwards] = .disabled }
        if !wantRogue { wifiStatus.dataAvailability[.nearbyAPs] = .disabled }
    }
}
