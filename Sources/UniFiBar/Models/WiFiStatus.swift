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
    private var previousAPKey: String? = nil
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
    var ddnsStatuses: [DDNSStatusDTO]? = nil
    var portForwards: [PortForwardDTO]? = nil
    var nearbyAPs: [RogueAPDTO]? = nil

    // Metadata
    var lastUpdated: Date? = nil

    enum DataSource: String, CaseIterable {
        case devices = "Devices", wan = "WAN", vpn = "VPN", sessions = "Session history"
        case accessPoint = "AP statistics", gateway = "Gateway statistics"
        case ddns = "Dynamic DNS", portForwards = "Port forwards", nearbyAPs = "Nearby APs"

        var menuSection: MenuSection {
            switch self {
            case .devices: .network
            case .wan, .gateway: .internet
            case .vpn: .vpn
            case .sessions: .sessionHistory
            case .accessPoint: .wifi
            case .ddns: .ddns
            case .portForwards: .portForwards
            case .nearbyAPs: .nearbyAPs
            }
        }
    }

    enum Availability: String {
        case refreshing = "Refreshing", available = "Available"
        case empty = "No entries returned", unavailable = "Unavailable"
        case notApplicable = "Not applicable"
        case disabled = "Disabled"
    }

    var dataAvailability: [DataSource: Availability] = [:]

    /// Never display the previous poll's optional metrics under a fresh primary timestamp.
    func beginSupplementalRefresh() {
        updateDevices(nil)
        updateWANHealth(nil)
        updateVPN(nil)
        updateSessions(nil, devices: [])
        updateAPStats(nil)
        updateGateway(nil, device: nil)
        updateMonitoring(ddns: nil, portForwards: nil, rogueAPs: nil)
        dataAvailability = Dictionary(uniqueKeysWithValues: DataSource.allCases.map { ($0, .refreshing) })
    }

    private func availability<T>(of items: [T]?) -> Availability {
        guard let items else { return .unavailable }
        return items.isEmpty ? .empty : .available
    }

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
        var id: String { apName }
        let apName: String
        let duration: Int
        let fraction: Double
    }

    enum ErrorState: Sendable, Equatable {
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

    /// One banding of the satisfaction score, so label, color, and icon cannot disagree.
    enum QualityBand: Sendable {
        case excellent, good, fair, poor, unknown

        init(_ satisfaction: Int?) {
            switch satisfaction {
            case .some(80...): self = .excellent
            case .some(50..<80): self = .good
            case .some(20..<50): self = .fair
            case .some: self = .poor
            case .none: self = .unknown
            }
        }

        var label: String {
            switch self {
            case .excellent: "Excellent"
            case .good: "Good"
            case .fair: "Fair"
            case .poor: "Poor"
            case .unknown: "Unknown"
            }
        }

        var color: Color {
            switch self {
            case .excellent: .green
            case .good: .yellow
            case .fair, .poor: .red
            case .unknown: .gray
            }
        }

        var isBelowGood: Bool { self == .fair || self == .poor }
    }

    var qualityBand: QualityBand { QualityBand(satisfaction) }
    var qualityLabel: String { qualityBand.label }

    var statusBarColor: Color {
        switch errorState {
        case .controllerUnreachable: return .orange
        case .invalidAPIKey: return .red
        case .notConnected: return .gray
        case .certChanged: return .orange
        case nil: break
        }
        if isConnected && isWired { return .blue }
        guard isConnected else { return .gray }
        return qualityBand.color
    }

    var statusBarSymbol: String {
        switch errorState {
        case .controllerUnreachable: return "wifi.exclamationmark"
        case .invalidAPIKey: return "lock.shield"
        case .notConnected: return "wifi.slash"
        case .certChanged: return "lock.shield"
        case nil: break
        }
        guard isConnected else { return "wifi.slash" }
        if isWired { return "cable.connector.horizontal" }
        guard !qualityBand.isBelowGood, satisfaction != nil else { return "wifi.exclamationmark" }
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

    var formattedAPLoad: String? { Self.formattedLoad(cpu: apCPU, memory: apMemory) }
    var formattedGatewayLoad: String? { Self.formattedLoad(cpu: gatewayCPU, memory: gatewayMemory) }

    private static func formattedLoad(cpu: Double?, memory: Double?) -> String? {
        guard let cpu, let memory else { return nil }
        return "CPU \(Int(cpu))% · Mem \(Int(memory))%"
    }

    var formattedGatewayUptime: String? {
        guard let secs = gatewayUptime, secs > 0 else { return nil }
        return Formatters.duration(seconds: secs)
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
        if total == 0 { return "No devices returned" }
        if online == total {
            return "\(total) device\(total == 1 ? "" : "s") · all online"
        }
        let offline = total - online
        return "\(online) online · \(offline) offline"
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
        return Formatters.duration(seconds: uptime)
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
        wifiStandard = Self.wifiStandard(fromRadioProto: client.radioProto)
        mimoDescription = Self.mimoDescription(fromMimo: client.mimo)
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
        let newSignal = client.signal.flatMap { (-120...0).contains($0) ? $0 : nil }
        if let newSignal, let prev = previousSignal {
            let diff = newSignal - prev
            signalTrend = diff > 2 ? .up : diff < -2 ? .down : .stable
        } else {
            signalTrend = .stable
        }
        previousSignal = newSignal
        signal = newSignal

        let newSat = client.wifiExperienceScore.flatMap { (0...100).contains($0) ? $0 : nil }
        if let newSat, let prev = previousSatisfaction {
            let diff = newSat - prev
            satisfactionTrend = diff > 2 ? .up : diff < -2 ? .down : .stable
        } else {
            satisfactionTrend = .stable
        }
        previousSatisfaction = newSat
        satisfaction = newSat

        // Roam detection keys on the AP MAC (stable identity) and falls back
        // to the uplink name when the MAC is missing.
        let newAPName = client.lastUplinkName
        let newAPKey = client.apMac?.lowercased() ?? newAPName?.lowercased()
        if let prevKey = previousAPKey, let key = newAPKey, prevKey != key {
            recentlyRoamed = true
            roamedFrom = previousAPName ?? prevKey
            roamCyclesRemaining = 2
        } else if roamCyclesRemaining > 0 {
            roamCyclesRemaining -= 1
            if roamCyclesRemaining == 0 {
                recentlyRoamed = false
                roamedFrom = nil
            }
        }
        previousAPKey = newAPKey
        previousAPName = newAPName
        apName = newAPName

        lastUpdated = Date()
    }

    func updateAPStats(_ stats: APStats?) {
        apCPU = stats?.cpuUtilizationPct.flatMap { (0...100).contains($0) ? $0 : nil }
        apMemory = stats?.memoryUtilizationPct.flatMap { (0...100).contains($0) ? $0 : nil }
        dataAvailability[.accessPoint] = apCPU == nil && apMemory == nil ? .unavailable : .available
    }

    func updateWANHealth(_ health: WANHealth?) {
        dataAvailability[.wan] = health?.status == nil ? .unavailable : .available
        if let health {
            wanIsUp = health.status.map { $0 == "ok" }
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
        gatewayCPU = stats?.cpuUtilizationPct.flatMap { (0...100).contains($0) ? $0 : nil }
        gatewayMemory = stats?.memoryUtilizationPct.flatMap { (0...100).contains($0) ? $0 : nil }
        gatewayUptime = stats?.uptimeSec
        gatewayName = device?.name
        dataAvailability[.gateway] = gatewayCPU == nil && gatewayMemory == nil && gatewayUptime == nil ? .unavailable : .available
    }

    func updateVPN(_ tunnels: [VPNTunnelDTO]?) {
        dataAvailability[.vpn] = availability(of: tunnels)
        vpnTunnels = (tunnels?.isEmpty == true) ? nil : tunnels
    }

    func updateDevices(_ devices: [DeviceDTO]?) {
        dataAvailability[.devices] = availability(of: devices)
        guard let devices else {
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
        dataAvailability[.sessions] = availability(of: dtos)
        guard let dtos, !dtos.isEmpty else {
            sessions = nil
            return
        }

        let devicesByMAC = Dictionary(
            devices.compactMap { device in device.mac.map { ($0.lowercased(), device) } },
            uniquingKeysWith: { first, _ in first }
        )
        var apDurations: [String: Int] = [:]
        for session in dtos {
            guard let apMac = session.apMac, let duration = session.duration, duration >= 0 else { continue }
            let lowered = apMac.lowercased()
            let name = devicesByMAC[lowered]?.name ?? apMac
            let (total, overflow) = apDurations[name, default: 0].addingReportingOverflow(duration)
            guard !overflow else { continue }
            apDurations[name] = total
        }

        let maxDuration = max(apDurations.values.max() ?? 1, 1)
        sessions = apDurations
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { SessionEntry(
                apName: $0.key,
                duration: $0.value,
                fraction: Double($0.value) / Double(maxDuration)
            )}
    }

    func updateMonitoring(
        ddns: [DDNSStatusDTO]?,
        portForwards: [PortForwardDTO]?,
        rogueAPs: [RogueAPDTO]?
    ) {
        dataAvailability[.ddns] = availability(of: ddns)
        dataAvailability[.portForwards] = availability(of: portForwards)
        dataAvailability[.nearbyAPs] = availability(of: rogueAPs)
        self.ddnsStatuses = ddns
        self.portForwards = portForwards
        self.nearbyAPs = rogueAPs
    }

    /// Resets all display state to defaults. Called on disconnect, error, and reset.
    func clearState() {
        isConnected = false
        isWired = false
        errorState = nil
        satisfaction = nil
        wifiExperienceAverage = nil
        signal = nil
        noiseFloor = nil
        apName = nil
        essid = nil
        channel = nil
        channelWidth = nil
        wifiStandard = nil
        mimoDescription = nil
        rxRate = nil
        txRate = nil
        txRetriesPct = nil
        rxBytes = nil
        txBytes = nil
        ip = nil
        uptime = nil
        roamCount = nil
        totalClients = nil
        clientsOnSameAP = nil
        apCPU = nil
        apMemory = nil
        recentlyRoamed = false
        roamedFrom = nil
        roamCyclesRemaining = 0
        previousAPKey = nil
        previousAPName = nil
        previousSignal = nil
        previousSatisfaction = nil
        signalTrend = .stable
        satisfactionTrend = .stable
        sessions = nil
        wanIsUp = nil
        wanIP = nil
        wanISP = nil
        wanLatencyMs = nil
        wanAvailability = nil
        wanDrops = nil
        wanTxBytesRate = nil
        wanRxBytesRate = nil
        gatewayCPU = nil
        gatewayMemory = nil
        gatewayUptime = nil
        gatewayName = nil
        vpnTunnels = nil
        devicesWithUpdates = nil
        totalDevices = nil
        onlineDevices = nil
        offlineDeviceNames = nil
        speedTest = nil
        ddnsStatuses = nil
        portForwards = nil
        nearbyAPs = nil
        lastUpdated = nil
        dataAvailability = [:]
    }

    func markDisconnected() {
        clearState()
        errorState = .notConnected
    }

    func markError(_ error: ErrorState) {
        clearState()
        errorState = error
    }

    // MARK: - Helpers

    /// Formats a rate in Kbps to human-readable Mbps/Gbps.
    /// Input unit: Kbps (Kilobits per second, decimal = 1000 bps).
    func formatRate(_ rateKbps: Int?) -> String {
        guard let rate = rateKbps else { return "—" }
        let mbps = Double(rate) / 1000.0
        if mbps >= 1000 {
            return String(format: "%.2f Gbps", mbps / 1000.0)
        }
        return String(format: "%.0f Mbps", mbps)
    }

    private func formatBytesPerSec(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000_000 {
            return String(format: "%.1f GB/s", bytesPerSec / 1_000_000_000)
        } else if bytesPerSec >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSec / 1_000)
        }
        return "0 B/s"
    }

    /// Formats byte counts using SI (decimal) units: KB=1000, MB=1,000,000, GB=1,000,000,000.
    /// This matches network throughput conventions (Mbps/Gbps use decimal units).
    func formatBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_000_000.0
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1_000.0
        if kb >= 1.0 {
            let formatted = String(format: "%.0f", kb)
            // Avoid "1000 KB" — show as "1.0 MB" instead
            if formatted == "1000" {
                return String(format: "%.1f MB", mb)
            }
            return "\(formatted) KB"
        }
        return "\(bytes) B"
    }

    // MARK: - DTO Display Mapping

    static func wifiStandard(fromRadioProto radioProto: String?) -> String? {
        switch radioProto {
        case "ax": return "WiFi 6"
        case "be": return "WiFi 7"
        case "ac": return "WiFi 5"
        case "n": return "WiFi 4"
        default: return radioProto
        }
    }

    static func mimoDescription(fromMimo mimo: String?) -> String? {
        guard let mimo else { return nil }
        if mimo.hasPrefix("MIMO_"), let n = Int(mimo.dropFirst(5)) {
            return "\(n)x\(n)"
        }
        return mimo
    }
}
