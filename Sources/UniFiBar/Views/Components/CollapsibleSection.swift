import SwiftUI

struct CollapsibleSection<Content: View>: View {
    let title: String
    let showDivider: Bool
    let defaultExpanded: Bool
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool

    init(title: String, showDivider: Bool = true, defaultExpanded: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.showDivider = showDivider
        self.defaultExpanded = defaultExpanded
        self.content = content
        self._isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showDivider {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.callout)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.top, showDivider ? 8 : 12)
                .padding(.bottom, 4)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            if isExpanded {
                content()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

/// Variant with a badge count next to the title
struct CollapsibleSectionWithBadge<Content: View>: View {
    let title: String
    let badge: Int
    let badgeColor: Color
    let showDivider: Bool
    let defaultExpanded: Bool
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool

    init(title: String, badge: Int, badgeColor: Color = .red, showDivider: Bool = true, defaultExpanded: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.badge = badge
        self.badgeColor = badgeColor
        self.showDivider = showDivider
        self.defaultExpanded = defaultExpanded
        self.content = content
        self._isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showDivider {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(badgeColor == Color.secondary ? Color.primary : Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(badgeColor, in: Capsule())
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.top, showDivider ? 8 : 12)
                .padding(.bottom, 4)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            if isExpanded {
                content()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}