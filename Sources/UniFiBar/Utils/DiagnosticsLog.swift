import AppKit

@MainActor
@Observable
final class DiagnosticsLog {
    static func copyToClipboard(_ report: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

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
    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Newest first, capped at the caller's row budget so a large log never allocates a full copy.
    func recentEvents(limit: Int) -> [Event] {
        guard limit > 0 else { return [] }
        return Array(events.suffix(limit).reversed())
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
        allowSelfSignedCerts: Bool,
        wifiStatus: WiFiStatus,
        includePrivateDetails: Bool = false
    ) -> String {
        var lines: [String] = []
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString

        lines.append("UniFiBar Diagnostics")
        lines.append("====================")
        lines.append(includePrivateDetails
            ? "PRIVATE DETAILS INCLUDED — review before sharing."
            : "Redacted: identifiers and free-text details omitted.")

        // Omit arbitrary text, rather than guessing every possible identifier/secret with regexes.
        func privateText(_ value: String) -> String {
            includePrivateDetails ? value : "[redacted]"
        }

        // System info
        lines.append("")
        lines.append("[System]")
        lines.append("Version: \(version) (build \(build))")
        lines.append("macOS: \(macOS)")

        // Connection info
        lines.append("")
        lines.append("[Connection]")
        lines.append("Controller: \(controllerHost.map(privateText) ?? "not configured")")
        lines.append("Self-signed certs: \(allowSelfSignedCerts ? "allowed" : "not allowed")")
        if let errorState {
            let reason: String?
            if case .invalidAPIKey = errorState {
                reason = errorState.displayReason // Typed HTTP status, not controller/free text.
            } else {
                reason = errorState.displayReason.map(privateText)
            }
            lines.append("Status: \(errorState.displayTitle) \(reason.map { "(\($0))" } ?? "")")
        } else {
            lines.append("Status: \(wifiStatus.isConnected ? "connected" : "not connected")")
        }
        lines.append("Consecutive errors: \(consecutiveErrors)")
        lines.append("Poll interval: \(pollInterval)s")
        lines.append("Last updated: \(wifiStatus.lastUpdated.map { $0.formatted() } ?? "never")")

        // WiFi details
        lines.append("")
        lines.append("[WiFi]")
        lines.append("Connected: \(wifiStatus.isConnected)")
        lines.append("Wired: \(wifiStatus.isWired)")
        if let ip = wifiStatus.ip { lines.append("IP: \(privateText(ip))") }
        if let essid = wifiStatus.essid { lines.append("Network: \(privateText(essid))") }
        if let ap = wifiStatus.apName { lines.append("AP: \(privateText(ap))") }
        if let satisfaction = wifiStatus.satisfaction { lines.append("WiFi Experience: \(satisfaction)%") }
        if let signal = wifiStatus.signal { lines.append("Signal: \(signal) dBm") }
        if let noise = wifiStatus.noiseFloor { lines.append("Noise Floor: \(noise) dBm") }
        if let channel = wifiStatus.channel { lines.append("Channel: \(channel)\(wifiStatus.channelWidth.map { " / \($0) MHz" } ?? "")") }
        if let standard = wifiStatus.wifiStandard { lines.append("Standard: \(privateText(standard))") }
        if let mimo = wifiStatus.mimoDescription { lines.append("MIMO: \(privateText(mimo))") }
        if wifiStatus.uptime != nil { lines.append("Uptime: \(wifiStatus.formattedUptime)") }
        if let txRetries = wifiStatus.formattedTxRetries { lines.append("TX Retries: \(txRetries)") }

        // WAN
        lines.append("")
        lines.append("[WAN]")
        if let wanUp = wifiStatus.wanIsUp { lines.append("WAN Up: \(wanUp)") }
        if let isp = wifiStatus.wanISP { lines.append("ISP: \(privateText(isp))") }
        if let latency = wifiStatus.wanLatencyMs { lines.append("Latency: \(latency) ms") }
        if let avail = wifiStatus.formattedWANAvailability { lines.append("Availability: \(avail)") }
        if let throughput = wifiStatus.formattedWANThroughput { lines.append("Throughput: \(throughput)") }

        // Gateway
        if wifiStatus.gatewayName != nil || wifiStatus.gatewayCPU != nil {
            lines.append("")
            lines.append("[Gateway]")
            if let name = wifiStatus.gatewayName { lines.append("Name: \(privateText(name))") }
            if let load = wifiStatus.formattedGatewayLoad { lines.append("Load: \(load)") }
            if let uptime = wifiStatus.formattedGatewayUptime { lines.append("Uptime: \(uptime)") }
        }

        // VPN
        if let tunnels = wifiStatus.vpnTunnels, !tunnels.isEmpty {
            lines.append("")
            lines.append("[VPN]")
            for tunnel in tunnels {
                lines.append("  \(privateText(tunnel.name ?? "Unknown")): \(privateText(tunnel.status ?? "unknown"))")
            }
        }

        // Network overview
        lines.append("")
        lines.append("[Network]")
        if includePrivateDetails, let overview = wifiStatus.formattedNetworkOverview {
            lines.append("Clients: \(overview)")
        } else if let total = wifiStatus.totalClients {
            lines.append("Clients: \(total)")
        }
        if let overview = wifiStatus.formattedDeviceOverview { lines.append("Devices: \(overview)") }
        if let firmware = wifiStatus.firmwareBadge { lines.append("Firmware: \(firmware)") }

        lines.append("")
        lines.append("[Data availability]")
        for source in WiFiStatus.DataSource.allCases {
            if let availability = wifiStatus.dataAvailability[source] {
                lines.append("\(source.rawValue): \(availability.rawValue)")
            }
        }

        // Events
        lines.append("")
        if events.isEmpty {
            lines.append("[Events] None recorded.")
        } else {
            lines.append("[Events] (newest first, \(events.count) total):")
            for event in events.reversed() {
                let time = timestampFormatter.string(from: event.timestamp)
                let prefix = "\(time) \(event.level.rawValue.uppercased()) \(event.category.rawValue)"
                if !includePrivateDetails {
                    lines.append("[\(prefix)] [details redacted]")
                } else if let detail = event.detail {
                    lines.append("[\(prefix)] \(event.message): \(detail)")
                } else {
                    lines.append("[\(prefix)] \(event.message)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
