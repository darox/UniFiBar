import Foundation

@MainActor
@Observable
final class DiagnosticsLog {
    struct Event: Identifiable, Sendable {
        let id: UUID
        let timestamp: Date
        let category: Category
        let level: Level
        let message: String
        let detail: String?

        init(category: Category, level: Level, message: String, detail: String? = nil) {
            self.id = UUID()
            self.timestamp = Date()
            self.category = category
            self.level = level
            self.message = message
            self.detail = detail
        }
    }

    enum Category: String, Sendable, CaseIterable {
        case connection
        case authentication
        case certificate
        case monitoring
        case configuration
        case system
    }

    enum Level: String, Sendable, CaseIterable {
        case error
        case warning
        case info
    }

    private var events: [Event] = []
    private let maxEvents = 200

    var recentEvents: [Event] {
        events.reversed()
    }

    var errorCount: Int {
        events.filter { $0.level == .error }.count
    }

    func record(_ category: Category, level: Level, message: String, detail: String? = nil) {
        let event = Event(category: category, level: level, message: message, detail: detail)
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    func clear() {
        events.removeAll()
    }

    func exportText(
        errorState: WiFiStatus.ErrorState?,
        consecutiveErrors: Int,
        pollInterval: Int,
        controllerHost: String?,
        allowSelfSignedCerts: Bool
    ) -> String {
        var lines: [String] = []
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString

        lines.append("UniFiBar Diagnostics")
        lines.append("====================")
        lines.append("Version: \(version) (build \(build))")
        lines.append("macOS: \(macOS)")
        lines.append("Controller: \(controllerHost ?? "not configured")")
        lines.append("Self-signed certs: \(allowSelfSignedCerts ? "allowed" : "not allowed")")

        if let errorState {
            lines.append("Status: \(errorState.displayTitle) \(errorState.displayReason.map { "(\($0))" } ?? "")")
        } else {
            lines.append("Status: connected")
        }

        lines.append("Consecutive errors: \(consecutiveErrors)")
        lines.append("Poll interval: \(pollInterval)s")
        lines.append("")

        if events.isEmpty {
            lines.append("No events recorded.")
        } else {
            lines.append("Recent Events (newest first):")
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            for event in events.reversed() {
                let time = formatter.string(from: event.timestamp)
                let prefix = "\(time) \(event.level.rawValue.uppercased()) \(event.category.rawValue)"
                if let detail = event.detail {
                    lines.append("[\(prefix)] \(event.message): \(detail)")
                } else {
                    lines.append("[\(prefix)] \(event.message)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}