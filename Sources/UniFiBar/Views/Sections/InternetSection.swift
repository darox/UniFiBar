import SwiftUI

struct InternetSection: View {
    let wifiStatus: WiFiStatus

    var body: some View {
        SectionHeader(title: "Internet", showDivider: false)

        if let isUp = wifiStatus.wanIsUp {
            HStack(spacing: 6) {
                Image(systemName: isUp ? "globe" : "globe.badge.chevron.backward")
                    .foregroundStyle(isUp ? .green : .red)
                    .frame(width: 20, alignment: .center)
                Text(isUp ? "Connected" : "Disconnected")
                    .foregroundStyle(.primary)
                Spacer()
                if let wanIP = wifiStatus.wanIP {
                    Text(wanIP)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        }

        if let isp = wifiStatus.wanISP {
            MetricRow(label: "ISP", value: isp, systemImage: "building.2")
        }

        if let latency = wifiStatus.formattedWANLatency {
            MetricRow(label: "Latency", value: latency, systemImage: "stopwatch")
        }

        if let availability = wifiStatus.formattedWANAvailability {
            MetricRow(label: "Availability", value: availability, systemImage: "checkmark.shield")
        }

        if let drops = wifiStatus.wanDrops {
            MetricRow(label: "Drops", value: "\(drops)", systemImage: "exclamationmark.triangle")
        }

        if let throughput = wifiStatus.formattedWANThroughput {
            MetricRow(label: "Throughput", value: throughput, systemImage: "arrow.up.arrow.down")
        }

        // Gateway health
        if let gwName = wifiStatus.gatewayName {
            SubSectionHeader(title: "Gateway")
            MetricRow(label: "Device", value: gwName, systemImage: "server.rack")
        }

        if let load = wifiStatus.formattedGatewayLoad {
            MetricRow(label: "Load", value: load, systemImage: "cpu")
        }

        if let uptime = wifiStatus.formattedGatewayUptime {
            MetricRow(label: "Uptime", value: uptime, systemImage: "timer")
        }
    }
}
