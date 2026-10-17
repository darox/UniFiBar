import SwiftUI

struct PortForwardsSection: View {
    let portForwards: [PortForwardDTO]

    var body: some View {
        CollapsibleSection(title: "Port Forwards", defaultExpanded: false) {
            ForEach(portForwards.prefix(8)) { pf in
                DetailRow(
                    systemImage: "arrow.right.arrow.left",
                    title: pf.displayName,
                    trailing: pf.summary,
                    trailingColor: Color(nsColor: .tertiaryLabelColor),
                    trailingFont: .caption
                )
            }

            if portForwards.count > 8 {
                TruncationNote(hiddenCount: portForwards.count - 8, noun: "rules")
            }
        }
    }
}
