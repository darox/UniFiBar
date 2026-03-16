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

    @ViewBuilder
    private var connectedView: some View {
        // Internet — WAN status, throughput, gateway
        if controller.wifiStatus.wanIsUp != nil {
            InternetSection(wifiStatus: controller.wifiStatus)
        }

        // VPN tunnels
        if let tunnels = controller.wifiStatus.vpnTunnels {
            VPNSection(tunnels: tunnels)
        }

        // WiFi — experience, signal, AP, link, session, session history
        WiFiExperienceSection(wifiStatus: controller.wifiStatus)
        SignalSection(wifiStatus: controller.wifiStatus)
        AccessPointSection(wifiStatus: controller.wifiStatus)
        LinkSection(wifiStatus: controller.wifiStatus)
        SessionSection(wifiStatus: controller.wifiStatus)
        if let sessions = controller.wifiStatus.sessions {
            SessionTimeSection(sessions: sessions)
        }

        // Network — clients, devices, firmware
        NetworkSection(wifiStatus: controller.wifiStatus)

        if let lastUpdated = controller.wifiStatus.lastUpdated {
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
        Button {
            controller.refreshNow()
        } label: {
            Label("Refresh Now", systemImage: "arrow.clockwise")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)

        Button {
            activateAndOpenWindow("preferences")
        } label: {
            Label("Preferences...", systemImage: "gearshape")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)

        Divider()
            .padding(.vertical, 4)

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit UniFiBar", systemImage: "xmark")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }
}
