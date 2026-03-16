import SwiftUI

struct WiFiExperienceSection: View {
    let wifiStatus: WiFiStatus

    var body: some View {
        SectionHeader(title: "WiFi Experience")

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(wifiStatus.qualityLabel)
                    .font(.title3)
                    .fontWeight(.medium)
                if let satisfaction = wifiStatus.satisfaction {
                    Text("· \(satisfaction)%")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if wifiStatus.satisfactionTrend != .stable {
                        Text(wifiStatus.satisfactionTrend.symbol)
                            .font(.title3)
                            .foregroundStyle(wifiStatus.satisfactionTrend == .up ? .green : .red)
                    }

                    if let avg = wifiStatus.wifiExperienceAverage {
                        Text("(avg \(avg)%)")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }

            if let satisfaction = wifiStatus.satisfaction {
                ProgressBarView(
                    fraction: Double(satisfaction) / 100.0,
                    color: wifiStatus.statusBarColor
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}
