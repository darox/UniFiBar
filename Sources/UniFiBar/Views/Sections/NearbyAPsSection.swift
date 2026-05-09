import SwiftUI

struct NearbyAPsSection: View {
    let rogueAPs: [RogueAPDTO]

    var body: some View {
        CollapsibleSectionWithBadge(
            title: "Nearby APs",
            badge: rogueAPs.count,
            badgeColor: .secondary,
            defaultExpanded: false
        ) {
            ForEach(rogueAPs) { ap in
                HStack(spacing: 6) {
                    Image(systemName: ap.isRogue == true ? "wifi.exclamationmark" : "wifi")
                        .foregroundStyle(ap.isRogue == true ? .orange : .secondary)
                        .frame(width: 20, alignment: .center)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ap.displayName)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let ch = ap.channel {
                            Text("Ch \(ch)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Text(ap.signalDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }
        }
    }
}
