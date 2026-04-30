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
    let preferences = PreferencesManager()
    let diagnosticsLog = DiagnosticsLog()
    let updateChecker = UpdateChecker()

    private static let logger = Logger(subsystem: "com.unifbar.app", category: "StatusBarController")

    private var pollTask: Task<Void, Never>?
    private var client: UniFiClient?
    private var pathMonitor: NWPathMonitor?
    private var wakeObserver: NSObjectProtocol?
    private var hasStarted = false
    private var consecutiveErrors = 0
    private var authFailed = false
    private var lastManualRefresh: Date = .distantPast
    private var successCount = 0
    private var isRefreshing = false
    private var refreshGeneration = 0

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
        guard !hasStarted else { return }
        hasStarted = true

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString
        diagnosticsLog.record(.system, level: .info, message: "UniFiBar started", detail: "v\(version) macOS \(macOS)")

        await preferences.checkConfiguration()
        guard preferences.isConfigured else { return }
        client = await preferences.loadClient()
        startPolling()
        observeSystemEvents()
    }

    func reconfigure() async {
        stopPolling()
        // Reset error state so new credentials get a clean start
        authFailed = false
        consecutiveErrors = 0
        // Invalidate old URLSession to release delegate and cancel in-flight requests
        if let oldClient = client {
            await oldClient.invalidate()
        }
        client = await preferences.loadClient()
        if client != nil {
            await refresh()
            startPolling()
            if !hasStarted {
                observeSystemEvents()
            }
        }
        hasStarted = true
    }

    func refreshNow() {
        let now = Date()
        guard now.timeIntervalSince(lastManualRefresh) >= 5 else { return }
        lastManualRefresh = now
        authFailed = false
        let gen = refreshGeneration
        Task {
            await refresh(generation: gen)
        }
    }

    func resetCertPin() async {
        guard let client else { return }
        await client.resetCertificatePin()
        // Reconfigure to get a fresh URLSession with a fresh delegate
        await reconfigure()
    }

    /// Resets all controller and WiFi state (called after preferences resetAll).
    func resetState() {
        stopPolling()
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
        pathMonitor?.cancel()
        pathMonitor = nil
        // Invalidate URLSession to release delegate and cancel in-flight requests
        let oldClient = client
        client = nil
        if let oldClient {
            Task { await oldClient.invalidate() }
        }
        authFailed = false
        consecutiveErrors = 0
        successCount = 0
        isRefreshing = false
        refreshGeneration += 1
        hasStarted = false
        wifiStatus.clearState()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
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
        // Wake from sleep — wait for network, then refresh with reset backoff
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.consecutiveErrors = 0
                // Wait longer for Wi-Fi to reassociate after wake
                try? await Task.sleep(for: .seconds(8))
                await self.refresh()
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
                self.consecutiveErrors = 0
                await self.refresh()
                // If polling had stopped (auth failure), don't restart
                if !self.authFailed && self.pollTask == nil {
                    self.startPolling()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.unifbar.pathmonitor"))
        pathMonitor = monitor
    }

    private func refresh(generation: Int? = nil) async {
        // Guard against overlapping refresh calls from poll loop + wake/network events
        guard !isRefreshing else { return }
        isRefreshing = true
        let gen = generation ?? refreshGeneration
        defer { if gen == refreshGeneration { isRefreshing = false } }

        guard let client else {
            wifiStatus.markError(.controllerUnreachable(reason: "Not configured"))
            return
        }

        // Ensure site is discovered (needed for all site-scoped calls)
        let siteId: String
        do {
            siteId = try await client.fetchSiteId()
            if preferences.siteId != siteId {
                preferences.siteId = siteId
            }
        } catch let error as UniFiError {
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
            if await client.certificateChanged {
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
            if await client.certificateChanged {
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

        consecutiveErrors = 0
        authFailed = false
        guard gen == refreshGeneration else { return }
        wifiStatus.update(from: selfInfo)

        successCount += 1
        if successCount % 10 == 0 {
            diagnosticsLog.record(.connection, level: .info, message: "Poll succeeded", detail: "\(successCount) consecutive")
        }

        if successCount == 1 {
            updateChecker.schedulePeriodicCheck()
        }

        let me = selfInfo.client

        // Parallel batch 1: devices, WAN health, VPN tunnels, session history
        async let devicesTask = client.fetchDevices(siteId: siteId)
        async let wanHealthTask = client.fetchWANHealth()
        async let vpnTask = client.fetchVPNTunnels(siteId: siteId)
        let myMac = me.mac
        let sessionsTask: Task<[SessionDTO]?, Never>
        if let mac = myMac {
            sessionsTask = Task { await client.fetchSessionHistory(mac: mac) }
        } else {
            sessionsTask = Task { nil }
        }

        let devices = (try? await devicesTask) ?? []
        let wanHealth = await wanHealthTask
        let tunnels = await vpnTask
        let sessions = await sessionsTask.value

        guard gen == refreshGeneration else { return }
        wifiStatus.updateDevices(devices)
        wifiStatus.updateWANHealth(wanHealth)
        wifiStatus.updateVPN(tunnels)
        wifiStatus.updateSessions(sessions, devices: devices)

        // Parallel batch 2: AP stats + gateway stats (depend on devices result)
        let apDevice = me.apMac.flatMap { apMac in
            devices.first(where: { $0.mac?.lowercased() == apMac.lowercased() })
        }
        let gwDevice = devices.first(where: \.isGateway)
            ?? devices.first(where: { $0.mac?.lowercased() == me.gwMac?.lowercased() })

        let apId = apDevice?.id
        let gwId = gwDevice?.id
        let apStatsTask: Task<APStats?, Never>
        let gwStatsTask: Task<GatewayStats?, Never>
        if let apId {
            apStatsTask = Task { await client.fetchAPStats(deviceId: apId, siteId: siteId) }
        } else {
            apStatsTask = Task { nil }
        }
        if let gwId {
            gwStatsTask = Task { await client.fetchGatewayStats(deviceId: gwId, siteId: siteId) }
        } else {
            gwStatsTask = Task { nil }
        }

        let apStats = await apStatsTask.value
        let gwStats = await gwStatsTask.value

        guard gen == refreshGeneration else { return }
        wifiStatus.updateAPStats(apStats)
        wifiStatus.updateGateway(gwStats, device: gwDevice)

        // Parallel batch 3: monitoring data (only fetch enabled sections)
        guard gen == refreshGeneration else { return }
        await fetchMonitoringData(client: client)
    }

    /// Maps network errors to human-readable reasons for the UI.
    private static func reasonFromError(_ error: Error) -> String? {
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
    /// Each call is independent and fails silently — monitoring data is best-effort.
    private func fetchMonitoringData(client: UniFiClient) async {
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
            ddns: ddns.data,
            portForwards: pf.data,
            rogueAPs: rogue.data
        )
    }
}
