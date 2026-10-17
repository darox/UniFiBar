import SwiftUI

struct NearbyAPsSection: View {
    let rogueAPs: [RogueAPDTO]

    var body: some View {
        CollapsibleSection(
            title: "Nearby APs (top \(UniFiClient.nearbyAPsLimit))",
            badge: rogueAPs.count,
            defaultExpanded: false
        ) {
            ForEach(rogueAPs) { ap in
                DetailRow(
                    systemImage: ap.isRogue == true ? "wifi.exclamationmark" : "wifi",
                    iconColor: ap.isRogue == true ? .orange : .secondary,
                    title: ap.displayName,
                    subtitle: ap.channel.map { "Ch \($0)" },
                    trailing: ap.signalDescription
                )
            }
        }
    }
}
