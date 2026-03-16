import SwiftUI

struct SessionTimeSection: View {
    let sessions: [WiFiStatus.SessionEntry]

    var body: some View {
        SectionHeader(title: "Session Time (Today)")

        ForEach(sessions) { session in
            HStack(spacing: 8) {
                Text(session.apName)
                    .font(.callout)
                    .frame(width: 90, alignment: .leading)
                    .lineLimit(1)

                ProgressBarView(fraction: session.fraction, color: .accentColor)

                Text(formattedDuration(session.duration))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
