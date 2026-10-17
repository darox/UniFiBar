import Foundation

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
}
