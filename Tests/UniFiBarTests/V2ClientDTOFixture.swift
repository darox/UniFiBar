import Foundation
@testable import UniFiBar

/// Test-only convenience initializer with defaults. The production type ships only its
/// decoding conformance and the synthesized memberwise initializer.
extension V2ClientDTO {
    init(ip: String, mac: String? = nil, hostname: String? = nil, displayName: String? = nil, signal: Int? = nil, rssi: Int? = nil, noise: Int? = nil, satisfaction: Int? = nil, wifiExperienceScore: Int? = nil, wifiExperienceAverage: Int? = nil, wifiTxRetriesPercentage: Double? = nil, channel: Int? = nil, channelWidth: Int? = nil, radioProto: String? = nil, radio: String? = nil, essid: String? = nil, apMac: String? = nil, lastUplinkName: String? = nil, rxRate: Int? = nil, txRate: Int? = nil, rxBytes: Int? = nil, txBytes: Int? = nil, uptime: Int? = nil, mimo: String? = nil, roamCount: Int? = nil, ccq: Int? = nil, gwMac: String? = nil) {
        self.init(mac: mac, ip: ip, hostname: hostname, displayName: displayName, signal: signal, rssi: rssi, noise: noise, satisfaction: satisfaction, wifiExperienceScore: wifiExperienceScore, wifiExperienceAverage: wifiExperienceAverage, wifiTxRetriesPercentage: wifiTxRetriesPercentage, channel: channel, channelWidth: channelWidth, radioProto: radioProto, radio: radio, essid: essid, apMac: apMac, lastUplinkName: lastUplinkName, rxRate: rxRate, txRate: txRate, rxBytes: rxBytes, txBytes: txBytes, uptime: uptime, mimo: mimo, roamCount: roamCount, ccq: ccq, gwMac: gwMac)
    }
}
