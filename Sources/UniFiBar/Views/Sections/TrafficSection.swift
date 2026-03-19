import SwiftUI

struct TrafficSection: View {
    let categories: [DPICategoryDTO]

    var body: some View {
        CollapsibleSection(title: "Traffic", defaultExpanded: false) {
            ForEach(categories.prefix(6)) { cat in
                HStack(spacing: 6) {
                    Image(systemName: iconForCategory(cat.name))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)
                    Text(cat.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(cat.formattedTotal)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }

            if categories.count > 6 {
                Text("+\(categories.count - 6) more categories")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }
        }
    }

    private func iconForCategory(_ name: String) -> String {
        switch name {
        case "Web": return "safari"
        case "Streaming", "Video": return "tv"
        case "Gaming": return "gamecontroller"
        case "Social": return "person.2"
        case "Email": return "envelope"
        case "File Transfer": return "doc.on.doc"
        case "VPN/Tunnel": return "lock.shield"
        case "Instant Messaging": return "message"
        case "P2P": return "arrow.triangle.swap"
        case "Shopping": return "cart"
        case "Productivity": return "doc.text"
        case "IoT": return "house"
        case "Apple": return "app.badge"
        case "Microsoft": return "desktopcomputer"
        default: return "chart.pie"
        }
    }
}
