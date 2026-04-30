import Foundation

// MARK: - Helpers

/// Truncates a string to a safe display length to prevent layout abuse from malicious API responses.
private func truncated(_ string: String, maxLength: Int = 200) -> String {
    if string.count <= maxLength { return string }
    return String(string.prefix(maxLength)) + "…"
}

// MARK: - Dynamic DNS

struct DDNSStatusDTO: Decodable, Sendable, Identifiable {
    let status: String?
    let service: String?
    let hostName: String?
    let login: String?
    let interface: String?

    enum CodingKeys: String, CodingKey {
        case status, service, login, interface
        case hostName = "host_name"
    }

    var id: String {
        let h = hostName ?? "unknown"
        let s = service ?? "ddns"
        return "\(h)-\(s)"
    }

    var isActive: Bool {
        // rest/dynamicdns doesn't always return status — presence implies configured
        if let status {
            return status == "good" || status == "nochg"
        }
        return service != nil
    }

    var displayStatus: String {
        switch status {
        case "good", "nochg": return "Active"
        case "abuse": return "Abuse"
        case "nohost": return "No Host"
        case "badauth": return "Auth Error"
        case nil: return service != nil ? "Configured" : "Unknown"
        default: return truncated(status?.capitalized ?? "Unknown", maxLength: 32)
        }
    }
}

// MARK: - Port Forwards

struct PortForwardDTO: Decodable, Sendable, Identifiable {
    private let _id: String?
    let name: String?
    let enabled: Bool?
    let dstPort: String?
    let fwd: String?
    let fwdPort: String?
    let proto: String?
    let pfwd_interface: String?

    var id: String { _id ?? "\(proto ?? ""):\(dstPort ?? "")->\(fwd ?? ""):\(fwdPort ?? "")" }

    init(_id: String? = nil, name: String? = nil, enabled: Bool? = nil, dstPort: String? = nil, fwd: String? = nil, fwdPort: String? = nil, proto: String? = nil, pfwd_interface: String? = nil) {
        self._id = _id
        self.name = name
        self.enabled = enabled
        self.dstPort = dstPort
        self.fwd = fwd
        self.fwdPort = fwdPort
        self.proto = proto
        self.pfwd_interface = pfwd_interface
    }

    enum CodingKeys: String, CodingKey {
        case _id
        case name, enabled
        case dstPort = "dst_port"
        case fwd
        case fwdPort = "fwd_port"
        case proto
        case pfwd_interface
    }

    var displayName: String {
        truncated(name ?? "\(proto?.uppercased() ?? ""):\(dstPort ?? "?")", maxLength: 64)
    }

    var summary: String {
        let p = proto?.uppercased() ?? "TCP"
        return truncated("\(p) :\(dstPort ?? "?") → \(fwd ?? "?"):\(fwdPort ?? dstPort ?? "?")", maxLength: 64)
    }
}

// MARK: - Rogue / Neighboring APs

struct RogueAPDTO: Decodable, Sendable, Identifiable {
    let _id: String?
    let bssid: String?
    let essid: String?
    let rssi: Int?
    let signal: Int?
    let channel: Int?
    let isRogue: Bool?
    let age: Int?
    let apMac: String?

    var id: String { _id ?? bssid ?? "\(essid ?? "")-\(channel ?? 0)-\(apMac ?? "")" }

    enum CodingKeys: String, CodingKey {
        case _id
        case bssid, essid, rssi, signal, channel, age
        case isRogue = "is_rogue"
        case apMac = "ap_mac"
    }

    var signalDescription: String {
        // Prefer the 'signal' field (already in dBm, negative).
        // Fall back to converting rssi: dBm = rssi - 95.
        let dBm: Int
        if let signal {
            dBm = signal
        } else if let rssi {
            dBm = rssi - 95
        } else {
            return "—"
        }
        let clamped = max(-120, min(0, dBm))
        return "\(clamped) dBm"
    }

    var displayName: String {
        truncated(essid ?? bssid ?? "Hidden", maxLength: 64)
    }
}

// MARK: - Speed Test Result (extracted from stat/health)

struct SpeedTestResult: Sendable {
    let downloadMbps: Double?
    let uploadMbps: Double?
    let pingMs: Int?
    let lastRun: Date?
    let status: String?

    var isRunning: Bool { status == "Running" }

    var formattedDownload: String? {
        guard let dl = downloadMbps, dl > 0 else { return nil }
        if dl >= 1000 { return String(format: "%.2f Gbps", dl / 1000) }
        return String(format: "%.0f Mbps", dl)
    }

    var formattedUpload: String? {
        guard let ul = uploadMbps, ul > 0 else { return nil }
        if ul >= 1000 { return String(format: "%.2f Gbps", ul / 1000) }
        return String(format: "%.0f Mbps", ul)
    }

    var formattedPing: String? {
        guard let p = pingMs else { return nil }
        return "\(p) ms"
    }
}

// MARK: - Speed test display (MainActor for RelativeDateTimeFormatter safety)

@MainActor
extension SpeedTestResult {
    var formattedLastRun: String? {
        guard let date = lastRun else { return nil }
        return Formatters.relativeTime(from: date)
    }
}
