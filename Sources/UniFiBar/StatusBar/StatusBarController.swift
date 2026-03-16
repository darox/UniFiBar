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

    private var pollTask: Task<Void, Never>?
    private var client: UniFiClient?
    private var pathMonitor: NWPathMonitor?
    private var wakeObserver: NSObjectProtocol?
    private var hasStarted = false

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
        Task {
            await refresh()
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func observeSystemEvents() {
        // Wake from sleep — immediate refresh
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                await self.refresh()
            }
        }

        // Network path changes — skip the initial fire, only react to actual changes
        let monitor = NWPathMonitor()
        let skipFirst = SkipFirstFlag()
        monitor.pathUpdateHandler = { [weak self] path in
            guard skipFirst.check() else { return }
            guard let self, path.status == .satisfied else { return }
            Task { @MainActor in
                await self.refresh()
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
        } catch {
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
                wifiStatus.markError(.invalidAPIKey)
            case .selfNotFound:
                wifiStatus.markDisconnected()
            default:
                wifiStatus.markError(.controllerUnreachable)
            }
            return
        } catch {
            wifiStatus.markError(.controllerUnreachable)
            return
        }

        wifiStatus.update(from: selfInfo)

        let me = selfInfo.client

        // Parallel batch: devices, WAN health, VPN tunnels, session history
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

        // Parallel batch: AP stats + gateway stats (depend on devices result)
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
    }
}
