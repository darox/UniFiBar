import SwiftUI

struct SectionHeader: View {
    let title: String
    var showDivider: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showDivider {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }

            Text(title)
                .font(.callout)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, showDivider ? 8 : 12)
                .padding(.bottom, 4)
        }
    }
}

struct SubSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 1)
    }
}
