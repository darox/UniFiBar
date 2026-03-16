import Foundation

/// Official integration API client — basic info only
struct ClientDTO: Decodable, Sendable {
    let ipAddress: String?
    let macAddress: String?
    let name: String?
    let type: String?
    let uplinkDeviceId: String?

    var ip: String? { ipAddress }
}

struct ClientListResponse: Decodable, Sendable {
    let data: [ClientDTO]
    let totalCount: Int?
    let limit: Int?
    let offset: Int?
}

/// v2 active client — rich WiFi details
struct V2ClientDTO: Decodable, Sendable {
    let mac: String?
    let ip: String?
    let hostname: String?
    let displayName: String?
    let signal: Int?
    let rssi: Int?
    let noise: Int?
    let satisfaction: Int?
    let wifiExperienceScore: Int?
    let wifiExperienceAverage: Int?
    let wifiTxRetriesPercentage: Double?
    let channel: Int?
    let channelWidth: Int?
    let radioProto: String?
    let radio: String?
    let essid: String?
    let apMac: String?
    let lastUplinkName: String?
    let rxRate: Int?
    let txRate: Int?
    let rxBytes: Int?
    let txBytes: Int?
    let uptime: Int?
    let mimo: String?
    let roamCount: Int?
    let ccq: Int?
    let gwMac: String?

    enum CodingKeys: String, CodingKey {
        case mac, ip, hostname, signal, rssi, noise, satisfaction, channel, radio, essid, uptime, ccq
        case displayName = "display_name"
        case gwMac = "gw_mac"
        case wifiExperienceScore = "wifi_experience_score"
        case wifiExperienceAverage = "wifi_experience_average"
        case wifiTxRetriesPercentage = "wifi_tx_retries_percentage"
        case channelWidth = "channel_width"
        case radioProto = "radio_proto"
        case apMac = "ap_mac"
        case lastUplinkName = "last_uplink_name"
        case rxRate = "rx_rate"
        case txRate = "tx_rate"
        case rxBytes = "rx_bytes"
        case txBytes = "tx_bytes"
        case mimo
        case roamCount = "roam_count"
    }

    var wifiStandard: String {
        switch radioProto {
        case "ax": return "WiFi 6"
        case "be": return "WiFi 7"
        case "ac": return "WiFi 5"
        case "n": return "WiFi 4"
        default: return radioProto ?? "Unknown"
        }
    }

    var mimoDescription: String? {
        guard let mimo else { return nil }
        // "MIMO_2" → "2x2"
        if mimo.hasPrefix("MIMO_"), let n = Int(mimo.dropFirst(5)) {
            return "\(n)x\(n)"
        }
        return mimo
    }
}
