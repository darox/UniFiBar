import Foundation

struct DeviceDTO: Decodable, Sendable {
    let id: String?
    let macAddress: String?
    let name: String?
    let model: String?
    let state: String?
    let firmwareUpdatable: Bool?
    let features: [String]?
    let firmwareVersion: String?
    let ipAddress: String?

    /// Convenience alias
    var mac: String? { macAddress }

    var isOnline: Bool { state == "CONNECTED" || state == "ONLINE" }

    /// Gateway models: UCG Fiber, UDM, UDM Pro, UDR, UXG, etc.
    var isGateway: Bool {
        guard let model = model?.lowercased() else { return false }
        return model.contains("ucg") || model.contains("udm") || model.contains("udr")
            || model.contains("uxg") || model.contains("gateway") || model.contains("dream")
    }
}

struct DeviceListResponse: Decodable, Sendable {
    let data: [DeviceDTO]
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

struct VPNTunnelResponse: Decodable, Sendable {
    let data: [VPNTunnelDTO]
}

struct VPNTunnelDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let status: String?
    let remoteNetworkCidr: String?
    let type: String?

    var isConnected: Bool { status == "CONNECTED" || status == "UP" }
}

// MARK: - Gateway Statistics

struct GatewayStats: Sendable {
    let uptimeSec: Int?
    let cpuUtilizationPct: Double?
    let memoryUtilizationPct: Double?
    let uplinkTxRateBps: Double?
    let uplinkRxRateBps: Double?
}

struct GatewayStatsResponse: Decodable, Sendable {
    let uptimeSec: Int?
    let cpuUtilizationPct: Double?
    let memoryUtilizationPct: Double?
    let uplink: GatewayUplink?

    struct GatewayUplink: Decodable, Sendable {
        let txRateBps: Double?
        let rxRateBps: Double?
    }

    var toGatewayStats: GatewayStats {
        GatewayStats(
            uptimeSec: uptimeSec,
            cpuUtilizationPct: cpuUtilizationPct,
            memoryUtilizationPct: memoryUtilizationPct,
            uplinkTxRateBps: uplink?.txRateBps,
            uplinkRxRateBps: uplink?.rxRateBps
        )
    }
}

// MARK: - AP Statistics

struct APStats: Sendable {
    let uptimeSec: Int?
    let cpuUtilizationPct: Double?
    let memoryUtilizationPct: Double?
}

struct APStatsResponse: Decodable, Sendable {
    let uptimeSec: Int?
    let cpuUtilizationPct: Double?
    let memoryUtilizationPct: Double?

    var toAPStats: APStats {
        APStats(
            uptimeSec: uptimeSec,
            cpuUtilizationPct: cpuUtilizationPct,
            memoryUtilizationPct: memoryUtilizationPct
        )
    }
}

// MARK: - Self Info (v2 client + network context)

struct SelfInfo: Sendable {
    let client: V2ClientDTO
    let totalClients: Int
    let clientsOnSameAP: Int

    /// True when this Mac is connected via Ethernet (no AP association)
    var isWired: Bool { client.apMac == nil }
}
