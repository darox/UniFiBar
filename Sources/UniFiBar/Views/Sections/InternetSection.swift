import SwiftUI

struct InternetSection: View {
    let wifiStatus: WiFiStatus

    var body: some View {
        SectionHeader(title: "Internet", showDivider: false)

        wanStatusGroup
        speedTestGroup
        gatewayGroup
    }

    @ViewBuilder
    private var wanStatusGroup: some View {
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
    }

    @ViewBuilder
    private var speedTestGroup: some View {
        if let speedTest = wifiStatus.speedTest, !speedTest.isRunning {
            SubSectionHeader(title: "Speed Test")

            if let dl = speedTest.formattedDownload {
                MetricRow(label: "Download", value: dl, systemImage: "arrow.down.circle")
            }
            if let ul = speedTest.formattedUpload {
                MetricRow(label: "Upload", value: ul, systemImage: "arrow.up.circle")
            }
            if let ping = speedTest.formattedPing {
                MetricRow(label: "Ping", value: ping, systemImage: "stopwatch")
            }
            if let lastRun = speedTest.formattedLastRun {
                MetricRow(label: "Tested", value: lastRun, systemImage: "clock")
            }
        } else if let speedTest = wifiStatus.speedTest, speedTest.isRunning {
            SubSectionHeader(title: "Speed Test")
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, alignment: .center)
                Text("Speed test running...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private var gatewayGroup: some View {
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
