import SwiftUI

struct WiFiExperienceSection: View {
    let qualityLabel: String
    let satisfaction: Int?
    let satisfactionTrend: WiFiStatus.TrendDirection
    let wifiExperienceAverage: Int?
    let accentColor: Color

    var body: some View {
        SectionHeader(title: "WiFi")

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(qualityLabel)
                    .font(.title3)
                    .fontWeight(.medium)
                if let satisfaction {
                    Text("· \(satisfaction)%")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if satisfactionTrend != .stable {
                        Text(satisfactionTrend.symbol)
                            .font(.title3)
                            .foregroundStyle(satisfactionTrend == .up ? .green : .red)
                    }

                    if let avg = wifiExperienceAverage {
                        Text("(avg \(avg)%)")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }

            if let satisfaction {
                ProgressBarView(
                    fraction: Double(satisfaction) / 100.0,
                    color: accentColor
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}