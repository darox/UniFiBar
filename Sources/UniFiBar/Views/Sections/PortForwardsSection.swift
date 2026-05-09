import SwiftUI

struct PortForwardsSection: View {
    let portForwards: [PortForwardDTO]

    var body: some View {
        CollapsibleSection(title: "Port Forwards", defaultExpanded: false) {
            ForEach(portForwards.prefix(8)) { pf in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.arrow.left")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)
                    Text(pf.displayName)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(pf.summary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }

            if portForwards.count > 8 {
                Text("+\(portForwards.count - 8) more rules")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }
        }
    }
}
