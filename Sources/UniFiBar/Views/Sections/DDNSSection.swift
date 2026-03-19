import SwiftUI

struct DDNSSection: View {
    let statuses: [DDNSStatusDTO]

    var body: some View {
        CollapsibleSection(title: "Dynamic DNS", defaultExpanded: false) {
            ForEach(Array(statuses.enumerated()), id: \.offset) { _, ddns in
                HStack(spacing: 6) {
                    Image(systemName: ddns.isActive ? "link" : "link.badge.plus")
                        .foregroundStyle(ddns.isActive ? .green : .red)
                        .frame(width: 20, alignment: .center)
                    VStack(alignment: .leading, spacing: 1) {
                        if let hostname = ddns.hostname {
                            Text(hostname)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        if let ip = ddns.ip {
                            Text(ip)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                    Spacer()
                    Text(ddns.displayStatus)
                        .font(.callout)
                        .foregroundStyle(ddns.isActive ? .secondary : .red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }
        }
    }
}
