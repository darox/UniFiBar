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

    private static let logger = Logger(subsystem: "com.unifbar.app", category: "StatusBarController")

    private var pollTask: Task<Void, Never>?
    private var client: UniFiClient?
    private var pathMonitor: NWPathMonitor?
    private var wakeObserver: NSObjectProtocol?
    private var hasStarted = false
    private var consecutiveErrors = 0
    private var authFailed = false
    private var lastManualRefresh: Date = .distantPast

    /// Tears down observers. Must be called on @MainActor before the object is released,
    /// since `deinit` is nonisolated in Swift 6 and cannot safely access actor-isolated state.
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

        await preferences.checkConfiguration()
        guard preferences.isConfigured else { return }
        client = await preferences.loadClient()
        startPolling()
        observeSystemEvents()
    }

    func reconfigure() async {
        stopPolling()
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
        Task {
            await refresh()
        }
    }

    func resetCertPin() async {
        guard let client else { return }
        await client.resetCertificatePin()
        // Reconfigure to get a fresh URLSession with a fresh delegate
        await reconfigure()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                // Stop polling if auth has permanently failed — user must fix credentials
                if self.authFailed { return }
                let delay = self.pollInterval
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Returns poll interval: 30s normally, backs off up to 5 minutes on transient errors.
    /// Auth failures don't back off — they stop polling entirely.
    private var pollInterval: Int {
        guard consecutiveErrors > 0 else { return 30 }
        return min(30 * (1 << min(consecutiveErrors, 4)), 300)
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
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

    private func refresh() async {
        guard let client else {
            wifiStatus.markError(.controllerUnreachable)
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
                authFailed = true
                consecutiveErrors = 0
                wifiStatus.markError(.invalidAPIKey)
            default:
                Self.logger.error("Site discovery failed: \((error as NSError).domain) code=\((error as NSError).code)")
                consecutiveErrors = min(consecutiveErrors + 1, 4)
                wifiStatus.markError(.controllerUnreachable)
            }
            return
        } catch {
            if await client.certificateChanged {
                Self.logger.warning("Certificate pin mismatch detected — cert may have been renewed")
                wifiStatus.markError(.certChanged)
                return
            }
            Self.logger.error("Site discovery failed: \((error as NSError).domain) code=\((error as NSError).code)")
            consecutiveErrors = min(consecutiveErrors + 1, 4)
            wifiStatus.markError(.controllerUnreachable)
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
                authFailed = true
                consecutiveErrors = 0
                wifiStatus.markError(.invalidAPIKey)
            case .selfNotFound:
                Self.logger.info("This device not found in active clients — likely disconnected")
                wifiStatus.markDisconnected()
            default:
                Self.logger.error("Failed to fetch self: \((error as NSError).domain) code=\((error as NSError).code)")
                consecutiveErrors = min(consecutiveErrors + 1, 4)
                wifiStatus.markError(.controllerUnreachable)
            }
            return
        } catch {
            if await client.certificateChanged {
                Self.logger.warning("Certificate pin mismatch detected — cert may have been renewed")
                wifiStatus.markError(.certChanged)
                return
            }
            consecutiveErrors = min(consecutiveErrors + 1, 4)
            Self.logger.error("Failed to fetch self: \((error as NSError).domain) code=\((error as NSError).code)")
            wifiStatus.markError(.controllerUnreachable)
            return
        }

        consecutiveErrors = 0
        authFailed = false
        wifiStatus.update(from: selfInfo)

        let me = selfInfo.client

        // Parallel batch 1: devices, WAN health, VPN tunnels, session history
        async let devicesTask = client.fetchDevices(siteId: siteId)
        async let wanHealthTask = client.fetchWANHealth()
        async let vpnTask = client.fetchVPNTunnels(siteId: siteId)
        async let sessionsTask: [SessionDTO]? = {
            if let mac = me.mac {
                return await client.fetchSessionHistory(mac: mac)
            }
            return nil
        }()

        let devices = (try? await devicesTask) ?? []
        let wanHealth = await wanHealthTask
        let tunnels = await vpnTask
        let sessions = await sessionsTask

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

        async let apStatsTask: APStats? = {
            if let deviceId = apDevice?.id {
                return await client.fetchAPStats(deviceId: deviceId, siteId: siteId)
            }
            return nil
        }()
        async let gwStatsTask: GatewayStats? = {
            if let gwId = gwDevice?.id {
                return await client.fetchGatewayStats(deviceId: gwId, siteId: siteId)
            }
            return nil
        }()

        let apStats = await apStatsTask
        let gwStats = await gwStatsTask

        wifiStatus.updateAPStats(apStats)
        wifiStatus.updateGateway(gwStats, device: gwDevice)

        // Parallel batch 3: monitoring data (only fetch enabled sections)
        await fetchMonitoringData(client: client)
    }

    /// Fetches optional monitoring data based on which sections are enabled in preferences.
    /// Each call is independent and fails silently — monitoring data is best-effort.
    private func fetchMonitoringData(client: UniFiClient) async {
        // Evaluate section visibility on @MainActor before spawning child tasks
        let wantAlarms = preferences.isSectionEnabled(.alerts)
        let wantTraffic = preferences.isSectionEnabled(.traffic)
        let wantSecurity = preferences.isSectionEnabled(.security)
        let wantDDNS = preferences.isSectionEnabled(.ddns)
        let wantPF = preferences.isSectionEnabled(.portForwards)
        let wantRogue = preferences.isSectionEnabled(.nearbyAPs)

        async let alarmsTask: [AlarmDTO]? = wantAlarms ? await client.fetchAlarms() : nil
        async let dpiTask: [DPICategoryDTO]? = wantTraffic ? await client.fetchDPIStats() : nil
        async let ipsTask: [IPSEventDTO]? = wantSecurity ? await client.fetchIPSEvents() : nil
        async let anomaliesTask: [AnomalyDTO]? = wantSecurity ? await client.fetchAnomalies() : nil
        async let ddnsTask: [DDNSStatusDTO]? = wantDDNS ? await client.fetchDDNSStatus() : nil
        async let pfTask: [PortForwardDTO]? = wantPF ? await client.fetchPortForwards() : nil
        async let rogueTask: [RogueAPDTO]? = wantRogue ? await client.fetchRogueAPs() : nil

        let alarms = await alarmsTask
        let dpi = await dpiTask
        let ips = await ipsTask
        let anomalies = await anomaliesTask
        let ddns = await ddnsTask
        let pf = await pfTask
        let rogue = await rogueTask

        wifiStatus.updateMonitoring(
            alarms: alarms,
            dpi: dpi,
            ips: ips,
            anomalies: anomalies,
            ddns: ddns,
            portForwards: pf,
            rogueAPs: rogue
        )
    }
}
