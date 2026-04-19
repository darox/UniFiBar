import SwiftUI

struct MenuContentView: View {
    let controller: StatusBarController

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !controller.preferences.isConfigured {
                NotConfiguredView(onSetup: { activateAndOpenWindow("setup") })
            } else if let errorState = controller.wifiStatus.errorState {
                MenuErrorView(
                    errorState: errorState,
                    consecutiveErrors: controller.consecutiveErrorCount,
                    pollInterval: controller.currentPollInterval,
                    onOpenPreferences: { activateAndOpenWindow("preferences") },
                    onResetCertPin: { Task { await controller.resetCertPin() } },
                    onCopyDiagnostics: { copyDiagnostics() }
                )
            } else if controller.wifiStatus.isConnected {
                connectedView
            } else {
                Text("Loading...")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Divider()
                .padding(.vertical, 4)

            MenuFooterView(controller: controller, onRefresh: { controller.refreshNow() }, onPreferences: { activateAndOpenWindow("preferences") })
        }
        .padding(.vertical, 8)
        .frame(height: controller.preferences.compactMode ? nil : screenUsableHeight)
    }

    // MARK: - Computed Properties

    private var screenUsableHeight: CGFloat {
        guard let screen = NSScreen.main else { return 600 }
        return screen.visibleFrame.height - 40
    }

    private var prefs: PreferencesManager { controller.preferences }
    private var status: WiFiStatus { controller.wifiStatus }

    // MARK: - Connected View

    @ViewBuilder
    private var connectedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                coreSections
                monitoringSections
                footerTimestamp
            }
        }
    }

    // MARK: - Core Sections

    @ViewBuilder
    private var coreSections: some View {
        if prefs.isSectionEnabled(.internet), status.wanIsUp != nil {
            InternetSection(
                wanIsUp: status.wanIsUp,
                wanIP: status.wanIP,
                wanISP: status.wanISP,
                formattedWANLatency: status.formattedWANLatency,
                formattedWANAvailability: status.formattedWANAvailability,
                wanDrops: status.wanDrops,
                formattedWANThroughput: status.formattedWANThroughput,
                speedTest: status.speedTest,
                gatewayName: status.gatewayName,
                formattedGatewayLoad: status.formattedGatewayLoad,
                formattedGatewayUptime: status.formattedGatewayUptime
            )
        }

        if prefs.isSectionEnabled(.vpn), let tunnels = status.vpnTunnels {
            VPNSection(tunnels: tunnels)
        }

        if prefs.isSectionEnabled(.wifi) {
            connectionContent
        }

        if prefs.isSectionEnabled(.sessionHistory), !status.isWired,
           let sessions = status.sessions {
            SessionTimeSection(sessions: sessions)
        }

        if prefs.isSectionEnabled(.network) {
            NetworkSection(
                formattedNetworkOverview: status.formattedNetworkOverview,
                formattedDeviceOverview: status.formattedDeviceOverview,
                offlineDeviceNames: status.offlineDeviceNames,
                firmwareBadge: status.firmwareBadge
            )
        }
    }

    @ViewBuilder
    private var connectionContent: some View {
        if status.isWired {
            SectionHeader(title: "Connection")
            HStack(spacing: 6) {
                Image(systemName: "cable.connector.horizontal")
                    .foregroundStyle(.blue)
                    .frame(width: 20, alignment: .center)
                Text("Connected via Ethernet")
                    .foregroundStyle(.primary)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 1)

            if let ip = status.ip {
                MetricRow(label: "IP", value: ip, systemImage: "network")
            }
        } else {
            WiFiExperienceSection(
                qualityLabel: status.qualityLabel,
                satisfaction: status.satisfaction,
                satisfactionTrend: status.satisfactionTrend,
                wifiExperienceAverage: status.wifiExperienceAverage,
                accentColor: status.statusBarColor
            )
            SignalSection(
                signalTrend: status.signalTrend,
                signalDescription: status.signalDescription,
                noiseFloor: status.noiseFloor
            )
            AccessPointSection(
                apName: status.apName,
                essid: status.essid,
                formattedAPLoad: status.formattedAPLoad,
                channel: status.channel,
                formattedChannelWidth: status.formattedChannelWidth,
                wifiStandard: status.wifiStandard,
                mimoDescription: status.mimoDescription,
                recentlyRoamed: status.recentlyRoamed,
                roamedFrom: status.roamedFrom
            )
            LinkSection(
                formattedRxRate: status.formattedRxRate,
                formattedTxRate: status.formattedTxRate,
                formattedTxRetries: status.formattedTxRetries,
                formattedSessionData: status.formattedSessionData
            )
            SessionSection(
                ip: status.ip,
                uptime: status.uptime,
                formattedUptime: status.formattedUptime,
                formattedRoamCount: status.formattedRoamCount
            )
        }
    }

    // MARK: - Monitoring Sections

    @ViewBuilder
    private var monitoringSections: some View {
        if prefs.isSectionEnabled(.ddns), let ddns = status.ddnsStatuses {
            DDNSSection(statuses: ddns)
        }

        if prefs.isSectionEnabled(.portForwards), let pf = status.portForwards {
            PortForwardsSection(portForwards: pf)
        }

        if prefs.isSectionEnabled(.nearbyAPs), let aps = status.nearbyAPs {
            NearbyAPsSection(rogueAPs: aps)
        }
    }

    @ViewBuilder
    private var footerTimestamp: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let lastUpdated = status.lastUpdated {
                Text("Last updated: \(lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if controller.updateChecker.updateAvailable, let latest = controller.updateChecker.latestVersion {
                Button {
                    if let url = controller.updateChecker.releaseURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("v\(latest) available", systemImage: "arrow.down.circle")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func activateAndOpenWindow(_ id: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func copyDiagnostics() {
        let report = controller.diagnosticsLog.exportText(
            errorState: controller.wifiStatus.errorState,
            consecutiveErrors: controller.consecutiveErrorCount,
            pollInterval: controller.currentPollInterval,
            controllerHost: controller.preferences.controllerURL?.host,
            allowSelfSignedCerts: controller.preferences.allowSelfSignedCerts,
            wifiStatus: controller.wifiStatus
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}

// MARK: - Not Configured View

private struct NotConfiguredView: View {
    let onSetup: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("UniFiBar Not Configured")
                .font(.headline)
            Text("Set up your UniFi controller to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Setup", action: onSetup)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Error View

private struct MenuErrorView: View {
    let errorState: WiFiStatus.ErrorState
    let consecutiveErrors: Int
    let pollInterval: Int
    let onOpenPreferences: () -> Void
    let onResetCertPin: () -> Void
    let onCopyDiagnostics: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            switch errorState {
            case .controllerUnreachable(let reason):
                Label("Controller Unreachable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                if let reason {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if consecutiveErrors > 0 {
                    Text("Retry in \(pollInterval)s · \(consecutiveErrors) error\(consecutiveErrors == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            case .invalidAPIKey(let httpCode):
                Label("Invalid API Key", systemImage: "key.slash")
                    .foregroundStyle(.red)
                if let code = httpCode {
                    Text("Server returned HTTP \(code)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Open Preferences", action: onOpenPreferences)
                    .buttonStyle(.borderedProminent)
            case .certChanged:
                Label("Certificate Changed", systemImage: "lock.shield")
                    .foregroundStyle(.orange)
                Text("The controller certificate has changed.\nReset the pin if you renewed it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Reset Certificate Pin", action: onResetCertPin)
                    .buttonStyle(.borderedProminent)
            case .notConnected:
                Label("Not Connected", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
                Text("This Mac is not connected to a UniFi network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: onCopyDiagnostics) {
                Label("Copy Diagnostics", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Footer View

private struct MenuFooterView: View {
    let controller: StatusBarController
    let onRefresh: () -> Void
    let onPreferences: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Refresh")

            Button(action: onPreferences) {
                Image(systemName: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Preferences")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Quit")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }
}