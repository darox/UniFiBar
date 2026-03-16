import Foundation
import SwiftUI

@MainActor
@Observable
final class WiFiStatus {
    var isConnected: Bool = false
    var errorState: ErrorState? = nil

    // WiFi Experience
    var satisfaction: Int? = nil
    var wifiExperienceAverage: Int? = nil

    // Signal
    var signal: Int? = nil
    var noiseFloor: Int? = nil

    // Connection details
    var apName: String? = nil
    var essid: String? = nil
    var channel: Int? = nil
    var channelWidth: Int? = nil
    var wifiStandard: String? = nil
    var mimoDescription: String? = nil
    var rxRate: Int? = nil
    var txRate: Int? = nil
    var rxBytes: Int? = nil
    var txBytes: Int? = nil
    var ip: String? = nil
    var uptime: Int? = nil
    var roamCount: Int? = nil

    // Network overview
    var totalClients: Int? = nil
    var clientsOnSameAP: Int? = nil

    // AP health
    var apCPU: Double? = nil
    var apMemory: Double? = nil

    // Roam detection
    var recentlyRoamed: Bool = false
    var roamedFrom: String? = nil
    private var roamCyclesRemaining: Int = 0
    private var previousAPName: String? = nil

    // Trend indicators
    private var previousSignal: Int? = nil
    private var previousSatisfaction: Int? = nil
    var signalTrend: TrendDirection = .stable
    var satisfactionTrend: TrendDirection = .stable

    // Session history
    var sessions: [SessionEntry]? = nil

    // Metadata
    var lastUpdated: Date? = nil

    enum TrendDirection: Sendable {
        case up, down, stable

        var symbol: String {
            switch self {
            case .up: return "↑"
            case .down: return "↓"
            case .stable: return "→"
            }
        }
    }

    struct SessionEntry: Identifiable, Sendable {
        let id = UUID()
        let apName: String
        let duration: Int
        let fraction: Double
    }

    enum ErrorState: Sendable {
        case controllerUnreachable
        case invalidAPIKey
        case notConnected
    }

    // MARK: - Display Properties

    var qualityLabel: String {
        guard let satisfaction else { return "Unknown" }
        switch satisfaction {
        case 80...100: return "Excellent"
        case 50..<80: return "Good"
        case 20..<50: return "Fair"
        default: return "Poor"
        }
    }

    var statusBarColor: Color {
        guard isConnected, let satisfaction else { return .gray }
        switch satisfaction {
        case 80...100: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    var statusBarSymbol: String {
        guard isConnected else { return "wifi.slash" }
        guard let satisfaction, satisfaction >= 50 else { return "wifi.exclamationmark" }
        return "wifi"
    }

    var formattedRxRate: String { formatRate(rxRate) }
    var formattedTxRate: String { formatRate(txRate) }

    var formattedSessionData: String? {
        guard let rx = rxBytes, let tx = txBytes else { return nil }
        return "↓ \(formatBytes(rx)) ↑ \(formatBytes(tx))"
    }

    var formattedNoiseFloor: String {
        guard let noise = noiseFloor else { return "—" }
        return "\(noise) dBm"
    }

    var formattedChannelWidth: String? {
        guard let w = channelWidth else { return nil }
        return "\(w) MHz"
    }

    var formattedRoamCount: String? {
        guard let count = roamCount else { return nil }
        return "\(count) roam\(count == 1 ? "" : "s")"
    }

    var formattedAPLoad: String? {
        guard let cpu = apCPU, let mem = apMemory else { return nil }
        return "CPU \(Int(cpu))% · Mem \(Int(mem))%"
    }

    var formattedNetworkOverview: String? {
        guard let total = totalClients else { return nil }
        var result = "\(total) client\(total == 1 ? "" : "s")"
        if let sameAP = clientsOnSameAP, let name = apName {
            result += " · \(sameAP) on \(name)"
        }
        return result
    }

    var formattedUptime: String {
        guard let uptime else { return "—" }
        let hours = uptime / 3600
        let minutes = (uptime % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var signalDescription: String {
        guard let signal else { return "—" }
        return "\(signal) dBm"
    }

    // MARK: - Update

    func update(from info: SelfInfo) {
        let client = info.client
        isConnected = true
        errorState = nil
        ip = client.ip
        wifiExperienceAverage = client.wifiExperienceAverage
        essid = client.essid
        channel = client.channel
        channelWidth = client.channelWidth
        wifiStandard = client.wifiStandard
        mimoDescription = client.mimoDescription
        rxRate = client.rxRate
        txRate = client.txRate
        rxBytes = client.rxBytes
        txBytes = client.txBytes
        uptime = client.uptime
        noiseFloor = client.noise
        roamCount = client.roamCount

        // Network overview
        totalClients = info.totalClients
        clientsOnSameAP = info.clientsOnSameAP

        // Trend indicators
        if let newSignal = client.signal, let prev = previousSignal {
            let diff = newSignal - prev
            signalTrend = diff > 2 ? .up : diff < -2 ? .down : .stable
        } else {
            signalTrend = .stable
        }
        previousSignal = client.signal
        signal = client.signal

        if let newSat = client.wifiExperienceScore, let prev = previousSatisfaction {
            let diff = newSat - prev
            satisfactionTrend = diff > 2 ? .up : diff < -2 ? .down : .stable
        } else {
            satisfactionTrend = .stable
        }
        previousSatisfaction = client.wifiExperienceScore
        satisfaction = client.wifiExperienceScore

        // Roam detection
        let newAPName = client.lastUplinkName
        if let prev = previousAPName, let current = newAPName, prev != current {
            recentlyRoamed = true
            roamedFrom = prev
            roamCyclesRemaining = 2
        } else if roamCyclesRemaining > 0 {
            roamCyclesRemaining -= 1
            if roamCyclesRemaining == 0 {
                recentlyRoamed = false
                roamedFrom = nil
            }
        }
        previousAPName = newAPName
        apName = newAPName

        lastUpdated = Date()
    }

    func updateAPStats(_ stats: APStats?) {
        apCPU = stats?.cpuUtilizationPct
        apMemory = stats?.memoryUtilizationPct
    }

    func updateSessions(_ dtos: [SessionDTO]?, devices: [DeviceDTO]) {
        guard let dtos, !dtos.isEmpty else {
            sessions = nil
            return
        }

        var apDurations: [String: Int] = [:]
        for session in dtos {
            guard let apMac = session.apMac, let duration = session.duration else { continue }
            let lowered = apMac.lowercased()
            let name = devices.first(where: { $0.mac?.lowercased() == lowered })?.name ?? apMac
            apDurations[name, default: 0] += duration
        }

        let maxDuration = apDurations.values.max() ?? 1
        sessions = apDurations
            .sorted { $0.value > $1.value }
            .map { SessionEntry(
                apName: $0.key,
                duration: $0.value,
                fraction: Double($0.value) / Double(maxDuration)
            )}
    }

    func markDisconnected() {
        isConnected = false
        errorState = .notConnected
        satisfaction = nil
        signal = nil
        lastUpdated = Date()
    }

    func markError(_ error: ErrorState) {
        isConnected = false
        errorState = error
        lastUpdated = Date()
    }

    // MARK: - Helpers

    private func formatRate(_ rateKbps: Int?) -> String {
        guard let rate = rateKbps else { return "—" }
        let mbps = Double(rate) / 1000.0
        if mbps >= 1000 {
            return String(format: "%.2f Gbps", mbps / 1000.0)
        }
        return String(format: "%.0f Mbps", mbps)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }
}
