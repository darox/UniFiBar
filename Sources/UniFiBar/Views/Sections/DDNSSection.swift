import SwiftUI

struct DDNSSection: View {
    let statuses: [DDNSStatusDTO]

    var body: some View {
        CollapsibleSection(title: "Dynamic DNS", defaultExpanded: false) {
            ForEach(statuses) { ddns in
                HStack(spacing: 6) {
                    Image(systemName: ddns.isActive ? "link" : "link.badge.plus")
                        .foregroundStyle(ddns.isActive ? .green : .red)
                        .frame(width: 20, alignment: .center)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String((ddns.hostName ?? "DDNS").prefix(64)))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let service = ddns.service, !service.isEmpty {
                            Text(service.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Text(ddns.displayStatus)
                        .font(.callout)
                        .foregroundStyle(ddns.isActive ? Color.secondary : Color.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }
        }
    }
}
