import SwiftUI

struct SecuritySection: View {
    let ipsEvents: [IPSEventDTO]?
    let anomalies: [AnomalyDTO]?

    private var totalThreats: Int { ipsEvents?.count ?? 0 }
    private var totalAnomalies: Int { anomalies?.count ?? 0 }
    private var totalBadge: Int { totalThreats + totalAnomalies }

    var body: some View {
        CollapsibleSectionWithBadge(
            title: "Security",
            badge: totalBadge,
            badgeColor: totalThreats > 0 ? .red : .yellow,
            defaultExpanded: false
        ) {
            if totalThreats > 0 {
                MetricRow(
                    label: "Threats Blocked",
                    value: "\(totalThreats)",
                    systemImage: "shield.lefthalf.filled.slash"
                )
            }

            if totalAnomalies > 0 {
                MetricRow(
                    label: "Anomalies",
                    value: "\(totalAnomalies)",
                    systemImage: "waveform.path.ecg"
                )
            }

            if let events = ipsEvents, !events.isEmpty {
                SubSectionHeader(title: "Recent Threats")
                ForEach(events.prefix(3)) { event in
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.shield.fill")
                            .foregroundStyle(.red)
                            .frame(width: 20, alignment: .center)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.displayMessage)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let src = event.srcIP {
                                Text(src)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                        Text(event.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 1)
                }
            }

            if totalThreats == 0 && totalAnomalies == 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .frame(width: 20, alignment: .center)
                    Text("No threats detected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }
        }
    }
}
