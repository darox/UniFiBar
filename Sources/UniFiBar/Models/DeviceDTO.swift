import Foundation

struct DeviceDTO: Decodable, Sendable {
    let id: String?
    let macAddress: String?
    let name: String?
    let model: String?
    let state: String?
    let firmwareUpdatable: Bool?
    let features: [String]?

    /// Convenience alias
    var mac: String? { macAddress }

    var isOnline: Bool { state == "CONNECTED" || state == "ONLINE" }

    /// Gateway models: UCG Fiber, UDM, UDM Pro, UDR, UXG, etc.
    /// Also matches devices with gateway-like features (wan role, routing capability).
    var isGateway: Bool {
        if features?.contains(where: { $0 == "gateway" || $0 == "wan" }) == true { return true }
        guard let model = model?.lowercased() else { return false }
        return model.contains("ucg") || model.contains("udm") || model.contains("udr")
            || model.contains("uxg") || model.contains("gateway") || model.contains("dream")
            || model.contains("router") || model.contains("usg")
    }
}

// MARK: - WAN Health (from legacy /stat/health endpoint)

struct WANHealth: Sendable {
    let ispName: String?
    let wanIP: String?
    let status: String?
    let latencyMs: Int?
    let availability: Double?
    let drops: Int?
    let rxBytesRate: Double?
    let txBytesRate: Double?
    let speedTest: SpeedTestResult?
}

struct WANHealthResponse: Decodable, Sendable {
    let data: [HealthEntry]

    init(from decoder: Decoder) throws {
        data = try LegacyResponse<HealthEntry>(from: decoder).data ?? []
    }

    struct HealthEntry: Decodable, Sendable {
        let subsystem: String?
        let status: String?
        let ispName: String?
        let wanIP: String?
        let uptimeStats: UptimeStats?
        let latency: Int?
        let drops: Int?

        // Fields with dashes need manual key mapping
        let rxBytesR: Double?
        let txBytesR: Double?

        // Speed test fields
        let speedtestLastrun: Int?
        let speedtestPing: Int?
        let speedtestStatus: String?
        let xputDown: Double?
        let xputUp: Double?

        enum CodingKeys: String, CodingKey {
            case subsystem, status
            case ispName = "isp_name"
            case wanIP = "wan_ip"
            case uptimeStats = "uptime_stats"
            case latency, drops
            case rxBytesR = "rx_bytes-r"
            case txBytesR = "tx_bytes-r"
            case speedtestLastrun = "speedtest_lastrun"
            case speedtestPing = "speedtest_ping"
            case speedtestStatus = "speedtest_status"
            case xputDown = "xput_down"
            case xputUp = "xput_up"
        }
    }

    struct UptimeStats: Decodable, Sendable {
        let WAN: WANUptime?

        struct WANUptime: Decodable, Sendable {
            let availability: Double?
            let latencyAverage: Int?

            enum CodingKeys: String, CodingKey {
                case availability
                case latencyAverage = "latency_average"
            }
        }
    }

    func toWANHealth() -> WANHealth? {
        let wan = data.first(where: { $0.subsystem == "wan" })
        let www = data.first(where: { $0.subsystem == "www" })
        guard wan != nil || www != nil else { return nil }

        let speedTest: SpeedTestResult?
        if let lastrun = wan?.speedtestLastrun, lastrun > 0 {
            speedTest = SpeedTestResult(
                downloadMbps: wan?.xputDown,
                uploadMbps: wan?.xputUp,
                pingMs: wan?.speedtestPing,
                lastRun: Date(timeIntervalSince1970: TimeInterval(lastrun)),
                status: wan?.speedtestStatus
            )
        } else {
            speedTest = nil
        }

        return WANHealth(
            ispName: wan?.ispName,
            wanIP: wan?.wanIP,
            status: wan?.status,
            latencyMs: wan?.uptimeStats?.WAN?.latencyAverage ?? www?.latency,
            availability: wan?.uptimeStats?.WAN?.availability,
            drops: www?.drops,
            rxBytesRate: wan?.rxBytesR,
            txBytesRate: wan?.txBytesR,
            speedTest: speedTest
        )
    }
}

// MARK: - VPN Tunnels

struct VPNTunnelDTO: Decodable, Sendable, Identifiable {
    let officialId: String?
    private let _id: String?
    let name: String?
    let status: String?
    let remoteNetworkCidr: String?
    let type: String?

    var id: String { officialId ?? _id ?? name ?? stableFallback }

    /// Deterministic fallback so SwiftUI identity is stable across view updates.
    private var stableFallback: String {
        let fields = [_id, name, status, remoteNetworkCidr, type].compactMap { $0 }
        return fields.isEmpty ? "unknown-tunnel" : fields.joined(separator: ":")
    }
    var isConnected: Bool? {
        switch status {
        case "CONNECTED", "UP": true
        case "DISCONNECTED", "DOWN": false
        default: nil
        }
    }

    init(_id: String? = nil, name: String? = nil, status: String? = nil, remoteNetworkCidr: String? = nil, type: String? = nil) {
        self.officialId = nil
        self._id = _id
        self.name = name
        self.status = status
        self.remoteNetworkCidr = remoteNetworkCidr
        self.type = type
    }

    enum CodingKeys: String, CodingKey {
        case officialId = "id"
        case _id
        case name, status
        case remoteNetworkCidr = "remote_network_cidr"
        case type
    }
}

// MARK: - Gateway Statistics

struct GatewayStats: Sendable {
    let uptimeSec: Int?
    let cpuUtilizationPct: Double?
    let memoryUtilizationPct: Double?
}

struct GatewayStatsResponse: Decodable, Sendable {
    let uptimeSec: Int?
    let cpuUtilizationPct: Double?
    let memoryUtilizationPct: Double?

    var toGatewayStats: GatewayStats {
        GatewayStats(
            uptimeSec: uptimeSec,
            cpuUtilizationPct: cpuUtilizationPct,
            memoryUtilizationPct: memoryUtilizationPct
        )
    }

    /// The AP projection reads a subset of the same payload.
    var toAPStats: APStats {
        APStats(
            cpuUtilizationPct: cpuUtilizationPct,
            memoryUtilizationPct: memoryUtilizationPct
        )
    }
}

// MARK: - AP Statistics

struct APStats: Sendable {
    let cpuUtilizationPct: Double?
    let memoryUtilizationPct: Double?
}

/// Both statistics projections decode from one device payload. Fetching once and
/// deriving both avoids a duplicate request when the AP and gateway share a device.
struct DeviceStatsSnapshot: Sendable {
    let apStats: APStats
    let gatewayStats: GatewayStats
}

// MARK: - Self Info (v2 client + network context)

struct SelfInfo: Sendable {
    let client: V2ClientDTO
    let totalClients: Int
    let clientsOnSameAP: Int

    /// True when this Mac is connected via Ethernet (no AP association)
    var isWired: Bool { client.apMac == nil }
}
