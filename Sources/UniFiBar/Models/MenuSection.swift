import Foundation

// MARK: - Section Visibility

enum MenuSection: String, CaseIterable, Sendable {
    case internet
    case vpn
    case wifi
    case network
    case sessionHistory
    case ddns
    case portForwards
    case nearbyAPs

    var displayName: String {
        switch self {
        case .internet: return "Internet & Gateway"
        case .vpn: return "VPN Tunnels"
        case .wifi: return "WiFi & Connection"
        case .network: return "Network Overview"
        case .sessionHistory: return "Session History"
        case .ddns: return "Dynamic DNS"
        case .portForwards: return "Port Forwards"
        case .nearbyAPs: return "Nearby APs"
        }
    }

    var icon: String {
        switch self {
        case .internet: return "globe"
        case .vpn: return "lock.shield"
        case .wifi: return "wifi"
        case .network: return "network"
        case .sessionHistory: return "clock"
        case .ddns: return "link"
        case .portForwards: return "arrow.right.arrow.left"
        case .nearbyAPs: return "antenna.radiowaves.left.and.right"
        }
    }

    /// Whether this section is shown by default
    var defaultEnabled: Bool {
        switch self {
        case .internet, .vpn, .wifi, .network, .sessionHistory:
            return true
        case .ddns, .portForwards, .nearbyAPs:
            return false
        }
    }
}
