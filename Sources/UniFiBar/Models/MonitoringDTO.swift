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

// MARK: - DPI (Deep Packet Inspection) Stats

struct DPICategoryDTO: Sendable, Identifiable {
    let id: Int
    let name: String
    let rxBytes: Int
    let txBytes: Int

    var totalBytes: Int { rxBytes + txBytes }

    var formattedTotal: String {
        formatBytes(totalBytes)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1.0 { return String(format: "%.0f MB", mb) }
        let kb = Double(bytes) / 1_024.0
        return String(format: "%.0f KB", kb)
    }
}

struct DPIStatsResponse: Decodable, Sendable {
    let data: [DPIEntry]

    struct DPIEntry: Decodable, Sendable {
        let byCat: [DPICategoryRaw]?

        enum CodingKeys: String, CodingKey {
            case byCat = "by_cat"
        }
    }

    struct DPICategoryRaw: Decodable, Sendable {
        let cat: Int?
        let rxBytes: Int?
        let txBytes: Int?
        let apps: [DPIAppRaw]?

        enum CodingKeys: String, CodingKey {
            case cat
            case rxBytes = "rx_bytes"
            case txBytes = "tx_bytes"
            case apps
        }
    }

    struct DPIAppRaw: Decodable, Sendable {
        let app: Int?
        let cat: Int?
        let rxBytes: Int?
        let txBytes: Int?

        enum CodingKeys: String, CodingKey {
            case app, cat
            case rxBytes = "rx_bytes"
            case txBytes = "tx_bytes"
        }
    }

    func toCategories() -> [DPICategoryDTO] {
        guard let entry = data.first, let cats = entry.byCat else { return [] }
        return cats.compactMap { raw in
            guard let cat = raw.cat else { return nil }
            return DPICategoryDTO(
                id: cat,
                name: Self.categoryName(cat),
                rxBytes: raw.rxBytes ?? 0,
                txBytes: raw.txBytes ?? 0
            )
        }
        .filter { $0.totalBytes > 0 }
        .sorted { $0.totalBytes > $1.totalBytes }
    }

    // UniFi DPI category mapping
    static func categoryName(_ cat: Int) -> String {
        switch cat {
        case 0: return "Instant Messaging"
        case 1: return "P2P"
        case 3: return "File Transfer"
        case 4: return "Streaming"
        case 5: return "Email"
        case 6: return "Network Protocols"
        case 7: return "Web"
        case 8: return "Gaming"
        case 9: return "Security"
        case 10: return "Database"
        case 13: return "Social"
        case 14: return "Apple"
        case 15: return "Microsoft"
        case 17: return "VPN/Tunnel"
        case 18: return "Video"
        case 19: return "IoT"
        case 20: return "Shopping"
        case 24: return "Productivity"
        case 25: return "Health"
        default: return "Category \(cat)"
        }
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

// MARK: - Anomalies

struct AnomalyDTO: Decodable, Sendable, Identifiable {
    let id: String
    let anomaly: String?
    let datetime: String?
    let deviceMac: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case anomaly, datetime
        case deviceMac = "device_mac"
    }
}

// MARK: - Site Events

struct SiteEventDTO: Decodable, Sendable, Identifiable {
    let id: String
    let key: String?
    let msg: String?
    let time: Int?
    let subsystem: String?
    let isAdmin: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case key, msg, time, subsystem
        case isAdmin = "is_admin"
    }

    var displayMessage: String {
        if let msg { return truncated(msg) }
        if let key { return truncated(key.replacingOccurrences(of: "EVT_", with: "").replacingOccurrences(of: "_", with: " ").capitalized) }
        return "Event"
    }

    var relativeTime: String {
        guard let time else { return "" }
        let seconds = TimeInterval(time) / 1000.0
        guard seconds > 946_684_800 && seconds < 4_102_444_800 else { return "" }
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var subsystemIcon: String {
        switch subsystem {
        case "wlan": return "wifi"
        case "lan": return "cable.connector.horizontal"
        case "wan": return "globe"
        case "vpn": return "lock.shield"
        default: return "info.circle"
        }
    }
}

// MARK: - Dynamic DNS

struct DDNSStatusDTO: Decodable, Sendable {
    let status: String?
    let ip: String?
    let hostname: String?
    let lastChanged: Int?

    enum CodingKeys: String, CodingKey {
        case status, ip, hostname
        case lastChanged = "last_changed"
    }

    var isActive: Bool {
        status == "good" || status == "nochg"
    }

    var displayStatus: String {
        switch status {
        case "good", "nochg": return "Active"
        case "abuse": return "Abuse"
        case "nohost": return "No Host"
        case "badauth": return "Auth Error"
        default: return status?.capitalized ?? "Unknown"
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
    let id: String
    let bssid: String?
    let essid: String?
    let rssi: Int?
    let channel: Int?
    let isRogue: Bool?
    let age: Int?
    let apMac: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case bssid, essid, rssi, channel, age
        case isRogue = "is_rogue"
        case apMac = "ap_mac"
    }

    var signalDescription: String {
        guard let rssi else { return "—" }
        // Clamp to physically plausible range
        let clamped = max(-120, min(0, rssi))
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
