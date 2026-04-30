import SwiftUI

struct SignalSection: View {
    let signalTrend: WiFiStatus.TrendDirection
    let signalDescription: String
    let noiseFloor: Int?

    var body: some View {
        SubSectionHeader(title: "Signal")

        HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
            Text("RSSI")
                .foregroundStyle(.primary)
            if signalTrend != .stable {
                Text(signalTrend.symbol)
                    .foregroundStyle(signalTrend == .up ? .green : .red)
            }
            Spacer()
            Text(signalDescription)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 1)

        if let noiseFloor {
            MetricRow(label: "Noise Floor", value: "\(noiseFloor) dBm", systemImage: "waveform.path")
        }
    }
}

struct AccessPointSection: View {
    let apName: String?
    let essid: String?
    let formattedAPLoad: String?
    let channel: Int?
    let formattedChannelWidth: String?
    let wifiStandard: String?
    let mimoDescription: String?
    let recentlyRoamed: Bool
    let roamedFrom: String?

    var body: some View {
        SubSectionHeader(title: "Access Point")

        if let apName {
            let networkSuffix = essid.map { "  (\($0))" } ?? ""
            MetricRow(label: "AP", value: apName + networkSuffix, systemImage: "wifi.router")
        } else if let essid {
            MetricRow(label: "Network", value: essid, systemImage: "wifi.router")
        }

        if let apLoad = formattedAPLoad {
            MetricRow(label: "Load", value: apLoad, systemImage: "cpu")
        }

        if let channel {
            MetricRow(label: "Channel", value: channelDescription(channel), systemImage: "dot.radiowaves.right")
        }

        if let standard = wifiStandard {
            MetricRow(label: "Standard", value: standardDescription(standard), systemImage: "cellularbars")
        }

        if recentlyRoamed, let from = roamedFrom {
            MetricRow(label: "Roamed from", value: from, systemImage: "arrow.triangle.swap")
        }
    }

    private func channelDescription(_ channel: Int) -> String {
        let band = channel > 14 ? "5 GHz" : "2.4 GHz"
        let base = "\(channel) · \(band)"
        if let width = formattedChannelWidth {
            return "\(base) · \(width)"
        }
        return base
    }

    private func standardDescription(_ standard: String) -> String {
        if let mimo = mimoDescription {
            return "\(standard) · \(mimo) MIMO"
        }
        return standard
    }
}

struct LinkSection: View {
    let formattedRxRate: String
    let formattedTxRate: String
    let formattedTxRetries: String?
    let formattedSessionData: String?

    var body: some View {
        SubSectionHeader(title: "Link")

        MetricRow(label: "Rx", value: formattedRxRate, systemImage: "arrow.down")
        MetricRow(label: "Tx", value: formattedTxRate, systemImage: "arrow.up")

        if let retries = formattedTxRetries {
            MetricRow(label: "Tx Retries", value: retries, systemImage: "arrow.counterclockwise")
        }

        if let sessionData = formattedSessionData {
            MetricRow(label: "Data", value: sessionData, systemImage: "chart.bar")
        }
    }
}

struct SessionSection: View {
    let ip: String?
    let uptime: Int?
    let formattedUptime: String
    let formattedRoamCount: String?

    var body: some View {
        SubSectionHeader(title: "Session")

        if let ip {
            MetricRow(label: "IP", value: ip, systemImage: "network")
        }

        if let uptime, uptime > 0 {
            MetricRow(label: "Uptime", value: formattedUptime, systemImage: "timer")
        }

        if let roamCountText = formattedRoamCount {
            MetricRow(label: "Roams", value: roamCountText, systemImage: "repeat")
        }
    }
}

struct NetworkSection: View {
    let formattedNetworkOverview: String?
    let formattedDeviceOverview: String?
    let offlineDeviceNames: [String]?
    let firmwareBadge: String?

    var body: some View {
        SectionHeader(title: "Network")

        if let overview = formattedNetworkOverview {
            MetricRow(label: "Clients", value: overview, systemImage: "person.2")
        }

        if let deviceOverview = formattedDeviceOverview {
            MetricRow(label: "Devices", value: deviceOverview, systemImage: "desktopcomputer")
        }

        if let offlineNames = offlineDeviceNames {
            ForEach(offlineNames, id: \.self) { name in
                MetricRow(label: name, value: "offline", systemImage: "exclamationmark.circle")
            }
        }

        if let badge = firmwareBadge {
            MetricRow(label: "Firmware", value: badge, systemImage: "arrow.down.circle")
        }
    }
}