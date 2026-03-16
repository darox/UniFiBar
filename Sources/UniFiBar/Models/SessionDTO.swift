import Foundation

struct SessionDTO: Decodable, Sendable {
    let mac: String?
    let apMac: String?
    let duration: Int?
    let assocTime: Int?

    enum CodingKeys: String, CodingKey {
        case mac
        case apMac = "ap_mac"
        case duration
        case assocTime = "assoc_time"
    }
}
