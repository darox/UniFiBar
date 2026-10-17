import SwiftUI

struct SessionTimeSection: View {
    let sessions: [WiFiStatus.SessionEntry]

    var body: some View {
        SubSectionHeader(title: "Session Time")

        ForEach(sessions.prefix(DisplayLimits.rows)) { session in
            HStack(spacing: 8) {
                Text(session.apName)
                    .font(.callout)
                    .frame(width: 90, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)

                ProgressBarView(fraction: session.fraction, color: .accentColor)

                Text(Formatters.duration(seconds: session.duration))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        }

        if sessions.count > DisplayLimits.rows {
            TruncationNote(hiddenCount: sessions.count - DisplayLimits.rows, noun: "APs")
        }
    }
}
