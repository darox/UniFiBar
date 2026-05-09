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
    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

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
        allowSelfSignedCerts: Bool,
        wifiStatus: WiFiStatus
    ) -> String {
        var lines: [String] = []
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString

        lines.append("UniFiBar Diagnostics")
        lines.append("====================")

        // System info
        lines.append("")
        lines.append("[System]")
        lines.append("Version: \(version) (build \(build))")
        lines.append("macOS: \(macOS)")

        // Connection info
        lines.append("")
        lines.append("[Connection]")
        lines.append("Controller: \(controllerHost ?? "not configured")")
        lines.append("Self-signed certs: \(allowSelfSignedCerts ? "allowed" : "not allowed")")
        if let errorState {
            lines.append("Status: \(errorState.displayTitle) \(errorState.displayReason.map { "(\($0))" } ?? "")")
        } else {
            lines.append("Status: connected")
        }
        lines.append("Consecutive errors: \(consecutiveErrors)")
        lines.append("Poll interval: \(pollInterval)s")
        lines.append("Last updated: \(wifiStatus.lastUpdated.map { $0.formatted() } ?? "never")")

        // WiFi details
        lines.append("")
        lines.append("[WiFi]")
        lines.append("Connected: \(wifiStatus.isConnected)")
        lines.append("Wired: \(wifiStatus.isWired)")
        if let ip = wifiStatus.ip { lines.append("IP: \(ip)") }
        if let essid = wifiStatus.essid { lines.append("Network: \(essid)") }
        if let ap = wifiStatus.apName { lines.append("AP: \(ap)") }
        if let satisfaction = wifiStatus.satisfaction { lines.append("WiFi Experience: \(satisfaction)%") }
        if let signal = wifiStatus.signal { lines.append("Signal: \(signal) dBm") }
        if let noise = wifiStatus.noiseFloor { lines.append("Noise Floor: \(noise) dBm") }
        if let channel = wifiStatus.channel { lines.append("Channel: \(channel)\(wifiStatus.channelWidth.map { " / \($0) MHz" } ?? "")") }
        if let standard = wifiStatus.wifiStandard { lines.append("Standard: \(standard)") }
        if let mimo = wifiStatus.mimoDescription { lines.append("MIMO: \(mimo)") }
        if wifiStatus.uptime != nil { lines.append("Uptime: \(wifiStatus.formattedUptime)") }
        if let txRetries = wifiStatus.formattedTxRetries { lines.append("TX Retries: \(txRetries)") }

        // WAN
        lines.append("")
        lines.append("[WAN]")
        if let wanUp = wifiStatus.wanIsUp { lines.append("WAN Up: \(wanUp)") }
        if let isp = wifiStatus.wanISP { lines.append("ISP: \(isp)") }
        if let latency = wifiStatus.wanLatencyMs { lines.append("Latency: \(latency) ms") }
        if let avail = wifiStatus.formattedWANAvailability { lines.append("Availability: \(avail)") }
        if let throughput = wifiStatus.formattedWANThroughput { lines.append("Throughput: \(throughput)") }

        // Gateway
        if wifiStatus.gatewayName != nil || wifiStatus.gatewayCPU != nil {
            lines.append("")
            lines.append("[Gateway]")
            if let name = wifiStatus.gatewayName { lines.append("Name: \(name)") }
            if let load = wifiStatus.formattedGatewayLoad { lines.append("Load: \(load)") }
            if let uptime = wifiStatus.formattedGatewayUptime { lines.append("Uptime: \(uptime)") }
        }

        // VPN
        if let tunnels = wifiStatus.vpnTunnels, !tunnels.isEmpty {
            lines.append("")
            lines.append("[VPN]")
            for tunnel in tunnels {
                lines.append("  \(tunnel.name ?? "Unknown"): \(tunnel.isConnected ? "connected" : tunnel.status?.lowercased() ?? "unknown")")
            }
        }

        // Network overview
        lines.append("")
        lines.append("[Network]")
        if let overview = wifiStatus.formattedNetworkOverview { lines.append("Clients: \(overview)") }
        if let overview = wifiStatus.formattedDeviceOverview { lines.append("Devices: \(overview)") }
        if let firmware = wifiStatus.firmwareBadge { lines.append("Firmware: \(firmware)") }

        // Events
        lines.append("")
        if events.isEmpty {
            lines.append("[Events] None recorded.")
        } else {
            lines.append("[Events] (newest first, \(events.count) total):")
            for event in events.reversed() {
                let time = timestampFormatter.string(from: event.timestamp)
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