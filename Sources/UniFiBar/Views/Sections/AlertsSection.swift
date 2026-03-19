import SwiftUI

struct AlertsSection: View {
    let alarms: [AlarmDTO]

    var body: some View {
        CollapsibleSectionWithBadge(title: "Alerts", badge: alarms.count, badgeColor: .orange) {
            ForEach(alarms.prefix(5)) { alarm in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 20, alignment: .center)
                    Text(alarm.displayMessage)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .font(.callout)
                    Spacer()
                    Text(alarm.relativeTime)
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }

            if alarms.count > 5 {
                Text("+\(alarms.count - 5) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }
        }
    }
}
