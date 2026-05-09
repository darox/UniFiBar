import Foundation

/// @MainActor-isolated formatting helpers.
/// RelativeDateTimeFormatter is not Sendable, so shared instances must not
/// escape the MainActor. Views call these from the UI layer where
/// MainActor isolation is guaranteed.
@MainActor
enum Formatters {
    private static let relativeTime: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func relativeTime(from date: Date) -> String {
        relativeTime.localizedString(for: date, relativeTo: Date())
    }
}