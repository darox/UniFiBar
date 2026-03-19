import SwiftUI

struct MenuContentView: View {
    let controller: StatusBarController

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !controller.preferences.isConfigured {
                notConfiguredView
            } else if let errorState = controller.wifiStatus.errorState {
                errorView(errorState)
            } else if controller.wifiStatus.isConnected {
                connectedView
            } else {
                Text("Loading...")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Divider()
                .padding(.vertical, 4)

            footerActions
        }
        .padding(.vertical, 8)
    }

    private func activateAndOpenWindow(_ id: String) {
        NSApplication.shared.activate()
        openWindow(id: id)
    }

    // MARK: - Connected View

    private var prefs: PreferencesManager { controller.preferences }
    private var status: WiFiStatus { controller.wifiStatus }

    @ViewBuilder
    private var connectedView: some View {
        coreSections
        monitoringSections
        footerTimestamp
    }

    // MARK: - Core sections (Internet, VPN, WiFi/Connection, Session History, Network)

    @ViewBuilder
    private var coreSections: some View {
        if prefs.isSectionEnabled(.internet), status.wanIsUp != nil {
            InternetSection(wifiStatus: status)
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
            NetworkSection(wifiStatus: status)
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
            WiFiExperienceSection(wifiStatus: status)
            SignalSection(wifiStatus: status)
            AccessPointSection(wifiStatus: status)
            LinkSection(wifiStatus: status)
            SessionSection(wifiStatus: status)
        }
    }

    // MARK: - Monitoring sections (Alerts, Security, Traffic, Events, DDNS, Port Forwards, Nearby APs)

    @ViewBuilder
    private var monitoringSections: some View {
        if prefs.isSectionEnabled(.alerts), let alarms = status.activeAlarms {
            AlertsSection(alarms: alarms)
        }

        if prefs.isSectionEnabled(.security),
           (status.ipsEvents != nil) || (status.anomalies != nil) {
            SecuritySection(ipsEvents: status.ipsEvents, anomalies: status.anomalies)
        }

        if prefs.isSectionEnabled(.traffic), let categories = status.dpiCategories {
            TrafficSection(categories: categories)
        }

        if prefs.isSectionEnabled(.events), let events = status.siteEvents {
            EventsSection(events: events)
        }

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
        if let lastUpdated = status.lastUpdated {
            Text("Last updated: \(lastUpdated.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }

    // MARK: - Error Views

    @ViewBuilder
    private var notConfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("UniFiBar Not Configured")
                .font(.headline)
            Text("Set up your UniFi controller to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Setup") {
                activateAndOpenWindow("setup")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    @ViewBuilder
    private func errorView(_ state: WiFiStatus.ErrorState) -> some View {
        VStack(spacing: 8) {
            switch state {
            case .controllerUnreachable:
                Label("Controller Unreachable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Will retry on next poll cycle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .invalidAPIKey:
                Label("Invalid API Key", systemImage: "key.slash")
                    .foregroundStyle(.red)
                Button("Open Preferences") {
                    activateAndOpenWindow("preferences")
                }
                .buttonStyle(.borderedProminent)
            case .notConnected:
                Label("Not Connected", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
                Text("This Mac is not connected to a UniFi network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerActions: some View {
        HStack(spacing: 8) {
            Button {
                controller.refreshNow()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }

            Button {
                activateAndOpenWindow("preferences")
            } label: {
                Label("Preferences", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }
}
