import SwiftUI

struct ConnectionSection: View {
    let wifiStatus: WiFiStatus

    var body: some View {
        SectionHeader(title: "Connection")

        // RSSI with trend
        HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
            Text("RSSI")
                .foregroundStyle(.primary)
            if wifiStatus.signalTrend != .stable {
                Text(wifiStatus.signalTrend.symbol)
                    .foregroundStyle(wifiStatus.signalTrend == .up ? .green : .red)
            }
            Spacer()
            Text(wifiStatus.signalDescription)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 1)

        if let noise = wifiStatus.noiseFloor {
            MetricRow(label: "Noise Floor", value: "\(noise) dBm", systemImage: "waveform.path")
        }

        if let apName = wifiStatus.apName {
            let networkSuffix = wifiStatus.essid.map { "  (\($0))" } ?? ""
            MetricRow(label: "AP", value: apName + networkSuffix, systemImage: "wifi.router")
        } else if let essid = wifiStatus.essid {
            MetricRow(label: "Network", value: essid, systemImage: "wifi.router")
        }

        // Roam indicator
        if wifiStatus.recentlyRoamed, let from = wifiStatus.roamedFrom {
            MetricRow(label: "Roamed from", value: from, systemImage: "arrow.triangle.swap")
        }

        if let apLoad = wifiStatus.formattedAPLoad {
            MetricRow(label: "AP Load", value: apLoad, systemImage: "cpu")
        }

        if let channel = wifiStatus.channel {
            MetricRow(label: "Channel", value: channelDescription(channel), systemImage: "dot.radiowaves.right")
        }

        if let standard = wifiStatus.wifiStandard {
            MetricRow(label: "Standard", value: standardDescription(standard), systemImage: "cellularbars")
        }

        MetricRow(label: "Rx", value: wifiStatus.formattedRxRate, systemImage: "arrow.down")
        MetricRow(label: "Tx", value: wifiStatus.formattedTxRate, systemImage: "arrow.up")

        if let sessionData = wifiStatus.formattedSessionData {
            MetricRow(label: "Data", value: sessionData, systemImage: "chart.bar")
        }

        if let ip = wifiStatus.ip {
            MetricRow(label: "IP", value: ip, systemImage: "network")
        }

        if let uptime = wifiStatus.uptime, uptime > 0 {
            MetricRow(label: "Uptime", value: wifiStatus.formattedUptime, systemImage: "timer")
        }

        if let roamCountText = wifiStatus.formattedRoamCount {
            MetricRow(label: "Roams", value: roamCountText, systemImage: "repeat")
        }

        // Network overview
        if let overview = wifiStatus.formattedNetworkOverview {
            SectionHeader(title: "Network")
            MetricRow(label: "Clients", value: overview, systemImage: "person.2")
        }
    }

    // MARK: - Helpers

    private func channelDescription(_ channel: Int) -> String {
        let band = channel > 14 ? "5 GHz" : "2.4 GHz"
        let base = "\(channel) · \(band)"
        if let width = wifiStatus.formattedChannelWidth {
            return "\(base) · \(width)"
        }
        return base
    }

    private func standardDescription(_ standard: String) -> String {
        if let mimo = wifiStatus.mimoDescription {
            return "\(standard) · \(mimo) MIMO"
        }
        return standard
    }
}
