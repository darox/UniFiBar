import SwiftUI

/// Shared row cap for sections that would otherwise render an unbounded server list.
enum DisplayLimits {
    static let rows = 20
}

/// The "+N more" line that follows a capped list.
struct TruncationNote: View {
    let hiddenCount: Int
    let noun: String

    var body: some View {
        Text("+\(hiddenCount) more \(noun)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.top, 2)
    }
}
