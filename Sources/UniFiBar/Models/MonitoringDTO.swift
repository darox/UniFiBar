import Foundation

// MARK: - Helpers

/// Truncates a string to a safe display length to prevent layout abuse from malicious API responses.
private func truncated(_ string: String, maxLength: Int = 200) -> String {
    if string.count <= maxLength { return string }
    return String(string.prefix(maxLength)) + "…"
}

// MARK: - Alarms

struct AlarmDTO: Decodable, Sendable, Identifiable {
    let id: String
    let key: String?
    let msg: String?
    let time: Int?
    let archived: Bool?
    let handledAdminId: String?
    let siteId: String?
    let deviceMac: String?
    let subsystem: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case key, msg, time, archived
        case handledAdminId = "handled_admin_id"
        case siteId = "site_id"
        case deviceMac = "device_mac"
        case subsystem
    }

    var displayMessage: String {
        if let msg { return truncated(msg) }
        if let key { return truncated(key.replacingOccurrences(of: "EVT_", with: "").replacingOccurrences(of: "_", with: " ").capitalized) }
        return "Unknown Alert"
    }

    var date: Date? {
        guard let time else { return nil }
        // Clamp to reasonable range (year 2000 to year 2100) to prevent formatter abuse
        let seconds = TimeInterval(time) / 1000.0
        guard seconds > 946_684_800 && seconds < 4_102_444_800 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    var relativeTime: String {
        guard let date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - IDS/IPS Events

struct IPSEventDTO: Decodable, Sendable, Identifiable {
    let id: String
    let msg: String?
    let srcIP: String?
    let dstIP: String?
    let catname: String?
    let action: String?
    let timestamp: Int?
    let inIface: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case msg
        case srcIP = "src_ip"
        case dstIP = "dst_ip"
        case catname, action, timestamp
        case inIface = "in_iface"
    }

    var displayMessage: String {
        truncated(msg ?? catname ?? "IPS Event")
    }

    var relativeTime: String {
        guard let timestamp else { return "" }
        let seconds = TimeInterval(timestamp) / 1000.0
        guard seconds > 946_684_800 && seconds < 4_102_444_800 else { return "" }
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
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

    var id: String { "\(hostName ?? "")-\(service ?? "")" }

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
    let id: String
    let name: String?
    let enabled: Bool?
    let dstPort: String?
    let fwd: String?
    let fwdPort: String?
    let proto: String?
    let pfwd_interface: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
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

    var formattedLastRun: String? {
        guard let date = lastRun else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
