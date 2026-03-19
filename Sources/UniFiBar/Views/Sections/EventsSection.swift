import SwiftUI

struct EventsSection: View {
    let events: [SiteEventDTO]

    var body: some View {
        CollapsibleSection(title: "Events", defaultExpanded: false) {
            ForEach(events.prefix(5)) { event in
                HStack(spacing: 6) {
                    Image(systemName: event.subsystemIcon)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)
                    Text(event.displayMessage)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .font(.callout)
                    Spacer()
                    Text(event.relativeTime)
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }

            if events.count > 5 {
                Text("+\(events.count - 5) more events")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }
        }
    }
}
