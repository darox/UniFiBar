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

@MainActor
@Observable
final class StatusBarController {
    let wifiStatus = WiFiStatus()
    let preferences: PreferencesManager
    let diagnosticsLog = DiagnosticsLog()
    let updateChecker: UpdateChecker
    private let loadClient: @MainActor () async -> UniFiClientProtocol?
    private let observesSystemEvents: Bool

    init(preferences: PreferencesManager = PreferencesManager()) {
        self.preferences = preferences
        loadClient = { await preferences.loadClient() }
        updateChecker = UpdateChecker()
        observesSystemEvents = true
    }

    /// Unit fixtures must supply isolated defaults, a fake Keychain, and only fake clients.
    /// A nil loader result stays unconfigured; it never falls back to native services.
    init(
        fixturePreferences: PreferencesManager,
        updateChecker: UpdateChecker? = nil,
        clientLoader: @escaping @MainActor () async -> UniFiClientProtocol?
    ) {
        preferences = fixturePreferences
        loadClient = clientLoader
        self.updateChecker = updateChecker ?? UpdateChecker(checksEnabled: false)
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
    func connect(using testClient: UniFiClientProtocol, url: URL, apiKey: String, allowSelfSigned: Bool) async throws {
        guard !preferences.isResetting else {
            await testClient.invalidate()
            throw CancellationError()
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
        let siteId = try validation.get()
        // Once persistence starts, cancellation is not a rollback of already-written credentials.
        try await preferences.save(controllerURL: url.absoluteString, apiKey: apiKey, allowSelfSigned: allowSelfSigned,
                                   isCurrent: { generation == self.connectionGeneration })
        try Task.checkCancellation()
        guard generation == connectionGeneration else { throw CancellationError() }
        preferences.siteId = siteId
        await reconfigure()
    }

    @discardableResult
    func refreshNow() -> Task<Void, Never>? {
        guard preferences.automaticConnectionAllowed else { return nil }
        let now = Date()
        guard now.timeIntervalSince(lastManualRefresh) >= 5 else { return nil }
        lastManualRefresh = now
        authFailed = false
        let gen = refreshGeneration
        return Task {
            await refresh(generation: gen)
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
        // Reconfigure to get a fresh URLSession with a fresh delegate
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
        isRefreshing = false
        refreshGeneration += 1
        hasStarted = false
        wifiStatus.clearState()
        guard !oldClients.isEmpty else { return nil }
        return Task { for oldClient in oldClients { await oldClient.invalidate() } }
    }

    private func startPolling() {
        guard preferences.automaticConnectionAllowed, client != nil else { return }
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
                try? await Task.sleep(for: .seconds(delay))
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
                self.consecutiveErrors = 0
                // Wait longer for Wi-Fi to reassociate after wake
                try? await Task.sleep(for: .seconds(8))
                guard gen == self.refreshGeneration else { return }
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
                self.consecutiveErrors = 0
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

        // Parallel batch 1: devices, WAN health, VPN tunnels, session history
        async let devicesTask = client.fetchDevices(siteId: siteId)
        async let wanHealthTask = client.fetchWANHealth()
        async let vpnTask = client.fetchVPNTunnels(siteId: siteId)
        async let sessionsTask: [SessionDTO]? = {
            guard let mac = me.mac else { return nil }
            return await client.fetchSessionHistory(mac: mac)
        }()

        let devices = try? await devicesTask
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
        async let apStatsTask: APStats? = {
            guard let apId else { return nil }
            return await client.fetchAPStats(deviceId: apId, siteId: siteId)
        }()
        async let gwStatsTask: GatewayStats? = {
            guard let gwId else { return nil }
            return await client.fetchGatewayStats(deviceId: gwId, siteId: siteId)
        }()

        let apStats = await apStatsTask
        let gwStats = await gwStatsTask

        guard gen == refreshGeneration, !Task.isCancelled else { return }
        wifiStatus.updateAPStats(apStats)
        wifiStatus.updateGateway(gwStats, device: gwDevice)
        if selfInfo.isWired { wifiStatus.dataAvailability[.accessPoint] = .notApplicable }
        if devices != nil, gwDevice == nil { wifiStatus.dataAvailability[.gateway] = .notApplicable }

        // Parallel batch 3: monitoring data (only fetch enabled sections)
        await fetchMonitoringData(client: client, generation: gen)
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
