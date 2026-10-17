import SwiftUI

struct DDNSSection: View {
    let statuses: [DDNSStatusDTO]

    var body: some View {
        CollapsibleSection(title: "Dynamic DNS", defaultExpanded: false) {
            ForEach(statuses.prefix(DisplayLimits.rows)) { ddns in
                DetailRow(
                    systemImage: ddns.isActive ? "link" : "link.badge.plus",
                    iconColor: ddns.isActive ? .green : .red,
                    title: String((ddns.hostName ?? "DDNS").prefix(64)),
                    subtitle: ddns.service.flatMap { $0.isEmpty ? nil : $0.capitalized },
                    trailing: ddns.displayStatus,
                    trailingColor: ddns.isActive ? .secondary : .red
                )
            }

            if statuses.count > DisplayLimits.rows {
                TruncationNote(hiddenCount: statuses.count - DisplayLimits.rows, noun: "hosts")
                    .padding(.top, 0)
            }
        }
    }
}
