import SwiftUI

struct DetailRow: View {
    let systemImage: String
    var iconColor: Color = .secondary
    let title: String
    var subtitle: String? = nil
    let trailing: String
    var trailingColor: Color = .secondary
    var trailingFont: Font = .callout

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(trailing)
                .font(trailingFont)
                .foregroundStyle(trailingColor)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
    }
}
