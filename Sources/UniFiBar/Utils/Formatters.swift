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

    /// Compact duration like "1d 4h", "2h 15m", or "30m". Negative input clamps to "0m".
    nonisolated static func duration(seconds: Int) -> String {
        let clamped = max(seconds, 0)
        let days = clamped / 86400
        let hours = (clamped % 86400) / 3600
        let minutes = (clamped % 3600) / 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
