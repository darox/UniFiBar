import Foundation
import SwiftUI

@MainActor
@Observable
final class WiFiStatus {
    var isConnected: Bool = false
    var isWired: Bool = false
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
    var txRetriesPct: Double? = nil
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

    // WAN status (from health endpoint)
    var wanIsUp: Bool? = nil
    var wanIP: String? = nil
    var wanISP: String? = nil
    var wanLatencyMs: Int? = nil
    var wanAvailability: Double? = nil
    var wanDrops: Int? = nil
    var wanTxBytesRate: Double? = nil
    var wanRxBytesRate: Double? = nil

    // Gateway health
    var gatewayCPU: Double? = nil
    var gatewayMemory: Double? = nil
    var gatewayUptime: Int? = nil
    var gatewayName: String? = nil

    // VPN tunnels
    var vpnTunnels: [VPNTunnelDTO]? = nil

    // Firmware
    var devicesWithUpdates: [String]? = nil

    // Device overview
    var totalDevices: Int? = nil
    var onlineDevices: Int? = nil
    var offlineDeviceNames: [String]? = nil

    // Speed test
    var speedTest: SpeedTestResult? = nil

    // Monitoring data
    var activeAlarms: [AlarmDTO]? = nil
    var ipsEvents: [IPSEventDTO]? = nil
    var ddnsStatuses: [DDNSStatusDTO]? = nil
    var portForwards: [PortForwardDTO]? = nil
    var nearbyAPs: [RogueAPDTO]? = nil

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
        case controllerUnreachable(reason: String?)
        case invalidAPIKey(httpCode: Int?)
        case notConnected
        case certChanged

        var displayTitle: String {
            switch self {
            case .controllerUnreachable: return "Controller Unreachable"
            case .invalidAPIKey: return "Invalid API Key"
            case .notConnected: return "Not Connected"
            case .certChanged: return "Certificate Changed"
            }
        }

        var displayReason: String? {
            switch self {
            case .controllerUnreachable(let reason): return reason
            case .invalidAPIKey(let code): return code.map { "HTTP \($0)" }
            case .notConnected, .certChanged: return nil
            }
        }
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
        switch errorState {
        case .controllerUnreachable(_): return .orange
        case .invalidAPIKey(_): return .red
        case .notConnected: return .gray
        case .certChanged: return .orange
        case nil: break
        }
        if isConnected && isWired { return .blue }
        guard isConnected, let satisfaction else { return .gray }
        switch satisfaction {
        case 80...100: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    var statusBarSymbol: String {
        switch errorState {
        case .controllerUnreachable(_): return "wifi.exclamationmark"
        case .invalidAPIKey(_): return "lock.shield"
        case .notConnected: return "wifi.slash"
        case .certChanged: return "lock.shield"
        case nil: break
        }
        guard isConnected else { return "wifi.slash" }
        if isWired { return "cable.connector.horizontal" }
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

    var formattedTxRetries: String? {
        guard let pct = txRetriesPct, pct > 0 else { return nil }
        return String(format: "%.1f%%", pct)
    }

    var formattedAPLoad: String? {
        guard let cpu = apCPU, let mem = apMemory else { return nil }
        return "CPU \(Int(cpu))% · Mem \(Int(mem))%"
    }

    var formattedGatewayLoad: String? {
        guard let cpu = gatewayCPU, let mem = gatewayMemory else { return nil }
        return "CPU \(Int(cpu))% · Mem \(Int(mem))%"
    }

    var formattedGatewayUptime: String? {
        guard let secs = gatewayUptime, secs > 0 else { return nil }
        let days = secs / 86400
        let hours = (secs % 86400) / 3600
        if days > 0 { return "\(days)d \(hours)h" }
        let minutes = (secs % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    var formattedWANThroughput: String? {
        guard let tx = wanTxBytesRate, let rx = wanRxBytesRate,
              tx > 0 || rx > 0 else { return nil }
        return "↓ \(formatBytesPerSec(rx)) ↑ \(formatBytesPerSec(tx))"
    }

    var formattedWANLatency: String? {
        guard let ms = wanLatencyMs else { return nil }
        return "\(ms) ms"
    }

    var formattedWANAvailability: String? {
        guard let pct = wanAvailability else { return nil }
        if pct == 100 {
            return "100%"
        }
        return String(format: "%.1f%%", pct)
    }

    var formattedDeviceOverview: String? {
        guard let total = totalDevices, let online = onlineDevices else { return nil }
        if online == total {
            return "\(total) device\(total == 1 ? "" : "s") · all online"
        }
        let offline = total - online
        return "\(online) online · \(offline) offline"
    }

    var activeAlarmCount: Int {
        activeAlarms?.count ?? 0
    }

    var ipsEventCount: Int {
        ipsEvents?.count ?? 0
    }

    var securitySummary: String? {
        let threats = ipsEventCount
        guard threats > 0 else { return nil }
        return "\(threats) threat\(threats == 1 ? "" : "s")"
    }

    var nearbyAPCount: Int {
        nearbyAPs?.count ?? 0
    }

    var firmwareBadge: String? {
        guard let names = devicesWithUpdates, !names.isEmpty else { return nil }
        let count = names.count
        return "\(count) device\(count == 1 ? "" : "s") update available"
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
        isWired = info.isWired
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
        txRetriesPct = client.wifiTxRetriesPercentage
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

    func updateWANHealth(_ health: WANHealth?) {
        if let health {
            wanIsUp = health.status == "ok"
            wanIP = health.wanIP
            wanISP = health.ispName
            wanLatencyMs = health.latencyMs
            wanAvailability = health.availability
            wanDrops = (health.drops ?? 0) > 0 ? health.drops : nil
            wanTxBytesRate = health.txBytesRate
            wanRxBytesRate = health.rxBytesRate
            speedTest = health.speedTest
        } else {
            wanIsUp = nil
            wanIP = nil
            wanISP = nil
            wanLatencyMs = nil
            wanAvailability = nil
            wanDrops = nil
            wanTxBytesRate = nil
            wanRxBytesRate = nil
            speedTest = nil
        }
    }

    func updateGateway(_ stats: GatewayStats?, device: DeviceDTO?) {
        // WAN status now comes from health endpoint via updateWANHealth()
        // Gateway only handles device-level stats
        gatewayCPU = stats?.cpuUtilizationPct
        gatewayMemory = stats?.memoryUtilizationPct
        gatewayUptime = stats?.uptimeSec
        gatewayName = device?.name
    }

    func updateVPN(_ tunnels: [VPNTunnelDTO]?) {
        vpnTunnels = (tunnels?.isEmpty == true) ? nil : tunnels
    }

    func updateDevices(_ devices: [DeviceDTO]) {
        guard !devices.isEmpty else {
            totalDevices = nil
            onlineDevices = nil
            offlineDeviceNames = nil
            devicesWithUpdates = nil
            return
        }

        totalDevices = devices.count
        onlineDevices = devices.filter(\.isOnline).count

        let offline = devices.filter { !$0.isOnline }
        offlineDeviceNames = offline.isEmpty ? nil : offline.compactMap(\.name)

        let updatable = devices.filter { $0.firmwareUpdatable == true }
        devicesWithUpdates = updatable.isEmpty ? nil : updatable.compactMap(\.name)
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

    func updateMonitoring(
        alarms: [AlarmDTO]?,
        ips: [IPSEventDTO]?,
        ddns: [DDNSStatusDTO]?,
        portForwards: [PortForwardDTO]?,
        rogueAPs: [RogueAPDTO]?
    ) {
        self.activeAlarms = alarms
        self.ipsEvents = ips
        self.ddnsStatuses = ddns
        self.portForwards = portForwards
        self.nearbyAPs = rogueAPs
    }

    func markDisconnected() {
        isConnected = false
        isWired = false
        errorState = .notConnected
        satisfaction = nil
        signal = nil
        lastUpdated = Date()
    }

    func markError(_ error: ErrorState) {
        isConnected = false
        errorState = error
        // Clear stale connection data so the UI doesn't show ghost values
        satisfaction = nil
        signal = nil
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

    private func formatBytesPerSec(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_073_741_824 {
            return String(format: "%.1f GB/s", bytesPerSec / 1_073_741_824)
        } else if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1_024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1_024)
        }
        return "0 B/s"
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
