import Foundation

struct DeviceDTO: Decodable, Sendable {
    let id: String?
    let macAddress: String?
    let name: String?
    let model: String?

    /// Convenience alias
    var mac: String? { macAddress }
}

struct DeviceListResponse: Decodable, Sendable {
    let data: [DeviceDTO]
}

// MARK: - AP Statistics

struct APStats: Sendable {
    let uptimeSec: Int?
    let cpuUtilizationPct: Double?
    let memoryUtilizationPct: Double?
    let txRetriesPct: Double?
}

struct APStatsResponse: Decodable, Sendable {
    let uptime: Int?
    let cpuUtilization: Double?
    let memoryUtilization: Double?
    let radioTable: [RadioStats]?

    struct RadioStats: Decodable, Sendable {
        let txRetriesPercentage: Double?

        enum CodingKeys: String, CodingKey {
            case txRetriesPercentage = "tx_retries_percentage"
        }
    }

    enum CodingKeys: String, CodingKey {
        case uptime
        case cpuUtilization = "cpu_utilization"
        case memoryUtilization = "memory_utilization"
        case radioTable = "radio_table"
    }

    var toAPStats: APStats {
        APStats(
            uptimeSec: uptime,
            cpuUtilizationPct: cpuUtilization,
            memoryUtilizationPct: memoryUtilization,
            txRetriesPct: radioTable?.compactMap(\.txRetriesPercentage).first
        )
    }
}

// MARK: - Self Info (v2 client + network context)

struct SelfInfo: Sendable {
    let client: V2ClientDTO
    let totalClients: Int
    let clientsOnSameAP: Int
}
