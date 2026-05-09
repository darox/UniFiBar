import Foundation
import Testing
@testable import UniFiBar

@MainActor
struct WiFiStatusTests {

    // MARK: - Quality Label

    @Test func testQualityLabel() {
        let status = WiFiStatus()
        status.satisfaction = 95
        #expect(status.qualityLabel == "Excellent")
        status.satisfaction = 80
        #expect(status.qualityLabel == "Excellent")
        status.satisfaction = 79
        #expect(status.qualityLabel == "Good")
        status.satisfaction = 50
        #expect(status.qualityLabel == "Good")
        status.satisfaction = 49
        #expect(status.qualityLabel == "Fair")
        status.satisfaction = 20
        #expect(status.qualityLabel == "Fair")
        status.satisfaction = 19
        #expect(status.qualityLabel == "Poor")
        status.satisfaction = 0
        #expect(status.qualityLabel == "Poor")
        status.satisfaction = nil
        #expect(status.qualityLabel == "Unknown")
    }

    // MARK: - Status Bar Colors

    @Test func testStatusBarColors_errorStates() {
        let status = WiFiStatus()
        status.errorState = .controllerUnreachable(reason: nil)
        #expect(status.statusBarColor == .orange)
        status.errorState = .invalidAPIKey(httpCode: 401)
        #expect(status.statusBarColor == .red)
        status.errorState = .notConnected
        #expect(status.statusBarColor == .gray)
        status.errorState = .certChanged
        #expect(status.statusBarColor == .orange)
    }

    @Test func testStatusBarColors_connected() {
        let status = WiFiStatus()
        status.isConnected = true
        status.satisfaction = 90
        #expect(status.statusBarColor == .green)
        status.satisfaction = 60
        #expect(status.statusBarColor == .yellow)
        status.satisfaction = 30
        #expect(status.statusBarColor == .red)
    }

    @Test func testStatusBarColors_connectedNilSatisfaction() {
        let status = WiFiStatus()
        status.isConnected = true
        status.satisfaction = nil
        #expect(status.statusBarColor == .gray)
    }

    @Test func testStatusBarColors_wired() {
        let status = WiFiStatus()
        status.isConnected = true
        status.isWired = true
        #expect(status.statusBarColor == .blue)
    }

    // MARK: - Status Bar Symbols

    @Test func testStatusBarSymbols_errorStates() {
        let status = WiFiStatus()
        status.errorState = .controllerUnreachable(reason: nil)
        #expect(status.statusBarSymbol == "wifi.exclamationmark")
        status.errorState = .invalidAPIKey(httpCode: 403)
        #expect(status.statusBarSymbol == "lock.shield")
        status.errorState = .notConnected
        #expect(status.statusBarSymbol == "wifi.slash")
        status.errorState = .certChanged
        #expect(status.statusBarSymbol == "lock.shield")
    }

    @Test func testStatusBarSymbols_connected() {
        let status = WiFiStatus()
        status.isConnected = true
        status.satisfaction = 50
        #expect(status.statusBarSymbol == "wifi")
        status.satisfaction = 30
        #expect(status.statusBarSymbol == "wifi.exclamationmark")
    }

    @Test func testStatusBarSymbols_disconnected() {
        let status = WiFiStatus()
        #expect(status.statusBarSymbol == "wifi.slash")
    }

    @Test func testStatusBarSymbols_wired() {
        let status = WiFiStatus()
        status.isConnected = true
        status.isWired = true
        #expect(status.statusBarSymbol == "cable.connector.horizontal")
    }

    // MARK: - clearState / markDisconnected / markError

    @Test func testMarkDisconnectedClearsAllState() {
        let status = WiFiStatus()
        status.isConnected = true
        status.isWired = false
        status.satisfaction = 95
        status.signal = -50
        status.apName = "U7 Pro"
        status.essid = "MyNetwork"
        status.channel = 36
        status.ip = "192.168.1.5"
        status.uptime = 3600
        status.wanIsUp = true
        status.vpnTunnels = [VPNTunnelDTO(_id: "1", name: "Tunnel", status: "CONNECTED", remoteNetworkCidr: nil, type: nil)]

        status.markDisconnected()

        #expect(status.isConnected == false)
        #expect(status.isWired == false)
        #expect(status.errorState == .notConnected)
        #expect(status.satisfaction == nil)
        #expect(status.signal == nil)
        #expect(status.apName == nil)
        #expect(status.essid == nil)
        #expect(status.channel == nil)
        #expect(status.ip == nil)
        #expect(status.uptime == nil)
        #expect(status.wanIsUp == nil)
        #expect(status.vpnTunnels == nil)
    }

    @Test func testMarkErrorClearsAllState() {
        let status = WiFiStatus()
        status.isConnected = true
        status.satisfaction = 90
        status.signal = -55
        status.apName = "U7 In-Wall"

        status.markError(.invalidAPIKey(httpCode: 401))

        #expect(status.isConnected == false)
        #expect(status.errorState == .invalidAPIKey(httpCode: 401))
        #expect(status.satisfaction == nil)
        #expect(status.signal == nil)
        #expect(status.apName == nil)
    }

    // MARK: - Format Rate

    @Test func testFormatRate() {
        let status = WiFiStatus()
        #expect(status.formatRate(500_000) == "500 Mbps")
        #expect(status.formatRate(1_000_000) == "1.00 Gbps")
        #expect(status.formatRate(1_500_000) == "1.50 Gbps")
        #expect(status.formatRate(1_200_000) == "1.20 Gbps")
        #expect(status.formatRate(54_000) == "54 Mbps")
        #expect(status.formatRate(nil) == "—")
    }

    @Test func testFormatRate_boundary() {
        let status = WiFiStatus()
        #expect(status.formatRate(0) == "0 Mbps")
        #expect(status.formatRate(1) == "0 Mbps")
        #expect(status.formatRate(999) == "1 Mbps")
        #expect(status.formatRate(1_000) == "1 Mbps")
        #expect(status.formatRate(999_999) == "1000 Mbps")
        #expect(status.formatRate(1_000_001) == "1.00 Gbps")
    }

    // MARK: - Format Bytes

    @Test func testFormatBytes() {
        let status = WiFiStatus()
        #expect(status.formatBytes(500_000) == "500 KB")
        #expect(status.formatBytes(1_500_000) == "1.5 MB")
        #expect(status.formatBytes(1_000_000_000) == "1.0 GB")
        #expect(status.formatBytes(2_000_000_000) == "2.0 GB")
    }

    @Test func testFormatBytes_boundary() {
        let status = WiFiStatus()
        #expect(status.formatBytes(0) == "0 B")
        #expect(status.formatBytes(1) == "1 B")
        #expect(status.formatBytes(999) == "999 B")
        #expect(status.formatBytes(999_999) == "1.0 MB")
        #expect(status.formatBytes(1_000) == "1 KB")
        #expect(status.formatBytes(999_000) == "999 KB")
    }

    // MARK: - ErrorState Display

    @Test func testErrorStateDisplay() {
        #expect(WiFiStatus.ErrorState.controllerUnreachable(reason: nil).displayTitle == "Controller Unreachable")
        #expect(WiFiStatus.ErrorState.invalidAPIKey(httpCode: 401).displayTitle == "Invalid API Key")
        #expect(WiFiStatus.ErrorState.notConnected.displayTitle == "Not Connected")
        #expect(WiFiStatus.ErrorState.certChanged.displayTitle == "Certificate Changed")

        #expect(WiFiStatus.ErrorState.controllerUnreachable(reason: "DNS lookup failed").displayReason == "DNS lookup failed")
        #expect(WiFiStatus.ErrorState.controllerUnreachable(reason: nil).displayReason == nil)
        #expect(WiFiStatus.ErrorState.invalidAPIKey(httpCode: 403).displayReason == "HTTP 403")
        #expect(WiFiStatus.ErrorState.invalidAPIKey(httpCode: nil).displayReason == nil)
        #expect(WiFiStatus.ErrorState.notConnected.displayReason == nil)
        #expect(WiFiStatus.ErrorState.certChanged.displayReason == nil)
    }

    // MARK: - update(from:) — WiFi client

    @Test func testUpdateFromWiFiClient() {
        let status = WiFiStatus()
        let client = V2ClientDTO(
            ip: "192.168.1.5",
            mac: "aa:bb:cc:dd:ee:ff",
            hostname: "macbook-pro",
            displayName: "Dario's MacBook",
            signal: -50,
            rssi: nil,
            noise: -92,
            satisfaction: nil,
            wifiExperienceScore: 85,
            wifiExperienceAverage: 82,
            wifiTxRetriesPercentage: 0.5,
            channel: 36,
            channelWidth: 80,
            radioProto: "ax",
            radio: "5g",
            essid: "HomeWiFi",
            apMac: "11:22:33:44:55:66",
            lastUplinkName: "U7 Pro",
            rxRate: 480_000,
            txRate: 360_000,
            rxBytes: 1_500_000_000,
            txBytes: 500_000_000,
            uptime: 7200,
            mimo: "MIMO_2",
            roamCount: 3,
            ccq: nil,
            gwMac: nil
        )
        let info = SelfInfo(client: client, totalClients: 12, clientsOnSameAP: 5)

        status.update(from: info)

        #expect(status.isConnected == true)
        #expect(status.isWired == false)
        #expect(status.errorState == nil)
        #expect(status.ip == "192.168.1.5")
        #expect(status.satisfaction == 85)
        #expect(status.wifiExperienceAverage == 82)
        #expect(status.signal == -50)
        #expect(status.noiseFloor == -92)
        #expect(status.essid == "HomeWiFi")
        #expect(status.channel == 36)
        #expect(status.channelWidth == 80)
        #expect(status.wifiStandard == "WiFi 6")
        #expect(status.mimoDescription == "2x2")
        #expect(status.rxRate == 480_000)
        #expect(status.txRate == 360_000)
        #expect(status.txRetriesPct == 0.5)
        #expect(status.rxBytes == 1_500_000_000)
        #expect(status.txBytes == 500_000_000)
        #expect(status.uptime == 7200)
        #expect(status.roamCount == 3)
        #expect(status.apName == "U7 Pro")
        #expect(status.totalClients == 12)
        #expect(status.clientsOnSameAP == 5)
        #expect(status.lastUpdated != nil)
        #expect(status.signalTrend == .stable)
        #expect(status.satisfactionTrend == .stable)
        #expect(status.recentlyRoamed == false)
    }

    // MARK: - update(from:) — wired client

    @Test func testUpdateFromWiredClient() {
        let status = WiFiStatus()
        let client = V2ClientDTO(ip: "10.0.0.50")
        let info = SelfInfo(client: client, totalClients: 8, clientsOnSameAP: 1)

        status.update(from: info)

        #expect(status.isConnected == true)
        #expect(status.isWired == true)
        #expect(status.ip == "10.0.0.50")
        #expect(status.satisfaction == nil)
        #expect(status.signal == nil)
        #expect(status.apName == nil)
        #expect(status.essid == nil)
        #expect(status.totalClients == 8)
    }

    // MARK: - update(from:) — trend detection

    @Test func testTrendSignalUp() {
        let status = WiFiStatus()
        let first = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: -75, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: 60, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: nil, rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: first, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.signal == -75)
        #expect(status.signalTrend == .stable)

        let second = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: -60, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: nil, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: nil, rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: second, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.signal == -60)
        #expect(status.signalTrend == .up)
    }

    @Test func testTrendSignalDown() {
        let status = WiFiStatus()
        let first = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: -55, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: 80, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: nil, rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: first, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.signal == -55)

        let second = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: -70, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: 75, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: nil, rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: second, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.signal == -70)
        #expect(status.signalTrend == .down)
    }

    @Test func testTrendSatisfactionUp() {
        let status = WiFiStatus()
        let first = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: nil, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: 60, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: nil, rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: first, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.satisfaction == 60)

        let second = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: nil, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: 80, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: nil, rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: second, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.satisfaction == 80)
        #expect(status.satisfactionTrend == .up)
    }

    @Test func testTrendSmallChangeStaysStable() {
        let status = WiFiStatus()
        let first = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: -60, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: 80, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: nil, rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: first, totalClients: 1, clientsOnSameAP: 1))

        let second = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: -59, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: 81, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: nil, rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: second, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.signalTrend == .stable)
        #expect(status.satisfactionTrend == .stable)
    }

    // MARK: - update(from:) — roam detection

    @Test func testRoamDetectedOnAPChange() {
        let status = WiFiStatus()
        let first = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: nil, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: nil, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: "U7 Pro", rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: first, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.apName == "U7 Pro")
        #expect(status.recentlyRoamed == false)

        let second = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: nil, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: nil, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: "U7 In-Wall", rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: second, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.apName == "U7 In-Wall")
        #expect(status.recentlyRoamed == true)
        #expect(status.roamedFrom == "U7 Pro")
    }

    @Test func testRoamClearsAfterCycles() {
        let status = WiFiStatus()
        let first = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: nil, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: nil, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: "U7 Pro", rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: first, totalClients: 1, clientsOnSameAP: 1))

        let second = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: nil, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: nil, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: "U7 In-Wall", rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: second, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.recentlyRoamed == true)

        let same = V2ClientDTO(ip: "192.168.1.5", mac: nil, hostname: nil, displayName: nil, signal: nil, rssi: nil, noise: nil, satisfaction: nil, wifiExperienceScore: nil, wifiExperienceAverage: nil, wifiTxRetriesPercentage: nil, channel: nil, channelWidth: nil, radioProto: nil, radio: nil, essid: nil, apMac: nil, lastUplinkName: "U7 In-Wall", rxRate: nil, txRate: nil, rxBytes: nil, txBytes: nil, uptime: nil, mimo: nil, roamCount: nil, ccq: nil, gwMac: nil)
        status.update(from: SelfInfo(client: same, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.recentlyRoamed == true)

        status.update(from: SelfInfo(client: same, totalClients: 1, clientsOnSameAP: 1))
        #expect(status.recentlyRoamed == false)
        #expect(status.roamedFrom == nil)
    }

    // MARK: - updateDevices

    @Test func testUpdateDevicesPopulated() {
        let status = WiFiStatus()
        let devices = [
            device(id: "1", mac: "aa", name: "U7 Pro", state: "CONNECTED"),
            device(id: "2", mac: "bb", name: "U7 In-Wall", state: "CONNECTED"),
            device(id: "3", mac: "cc", name: "Switch", state: "DISCONNECTED"),
            device(id: "4", mac: "dd", name: "Old AP", state: "DISCONNECTED", firmwareUpdatable: true),
        ]

        status.updateDevices(devices)

        #expect(status.totalDevices == 4)
        #expect(status.onlineDevices == 2)
        #expect(status.offlineDeviceNames == ["Switch", "Old AP"])
        #expect(status.devicesWithUpdates == ["Old AP"])
    }

    @Test func testUpdateDevicesAllOnline() {
        let status = WiFiStatus()
        let devices = [
            device(id: "1", mac: "aa", name: "U7 Pro", state: "ONLINE"),
            device(id: "2", mac: "bb", name: "UDM", state: "CONNECTED"),
        ]

        status.updateDevices(devices)

        #expect(status.totalDevices == 2)
        #expect(status.onlineDevices == 2)
        #expect(status.offlineDeviceNames == nil)
    }

    @Test func testUpdateDevicesEmpty() {
        let status = WiFiStatus()
        status.totalDevices = 5
        status.onlineDevices = 4
        status.devicesWithUpdates = ["AP1"]

        status.updateDevices([])

        #expect(status.totalDevices == nil)
        #expect(status.onlineDevices == nil)
        #expect(status.offlineDeviceNames == nil)
        #expect(status.devicesWithUpdates == nil)
    }

    @Test func testUpdateDevicesMultipleUpdates() {
        let status = WiFiStatus()
        let devices = [
            device(id: "1", mac: "aa", name: "U7 Pro", state: "ONLINE", firmwareUpdatable: true),
            device(id: "2", mac: "bb", name: "UDM", state: "ONLINE", firmwareUpdatable: true),
        ]

        status.updateDevices(devices)
        #expect(status.devicesWithUpdates == ["U7 Pro", "UDM"])
        #expect(status.firmwareBadge == "2 devices update available")
    }

    @Test func testUpdateDevicesWithNullStateFallback() {
        let status = WiFiStatus()
        let devices = [device(id: "1", mac: "aa", name: "Unknown AP", state: nil)]

        status.updateDevices(devices)

        #expect(status.totalDevices == 1)
        #expect(status.onlineDevices == 0)
        #expect(status.offlineDeviceNames == ["Unknown AP"])
    }

    // MARK: - updateWANHealth

    @Test func testUpdateWANHealthPopulated() {
        let status = WiFiStatus()
        let health = WANHealth(
            ispName: "Comcast",
            wanIP: "203.0.113.1",
            status: "ok",
            latencyMs: 12,
            availability: 99.9,
            drops: 3,
            rxBytesRate: 1_500_000,
            txBytesRate: 800_000,
            speedTest: nil
        )

        status.updateWANHealth(health)

        #expect(status.wanIsUp == true)
        #expect(status.wanIP == "203.0.113.1")
        #expect(status.wanISP == "Comcast")
        #expect(status.wanLatencyMs == 12)
        #expect(status.wanAvailability == 99.9)
        #expect(status.wanDrops == 3)
        #expect(status.wanTxBytesRate == 800_000)
        #expect(status.wanRxBytesRate == 1_500_000)
    }

    @Test func testUpdateWANHealthStatusNotOk() {
        let status = WiFiStatus()
        let health = WANHealth(
            ispName: nil, wanIP: nil, status: "down",
            latencyMs: nil, availability: nil, drops: nil,
            rxBytesRate: nil, txBytesRate: nil, speedTest: nil
        )

        status.updateWANHealth(health)
        #expect(status.wanIsUp == false)
    }

    @Test func testUpdateWANHealthDropsZeroIsNil() {
        let status = WiFiStatus()
        let health = WANHealth(
            ispName: nil, wanIP: nil, status: "ok",
            latencyMs: nil, availability: nil, drops: 0,
            rxBytesRate: nil, txBytesRate: nil, speedTest: nil
        )

        status.updateWANHealth(health)
        #expect(status.wanDrops == nil)
    }

    @Test func testUpdateWANHealthNil() {
        let status = WiFiStatus()
        let health = WANHealth(
            ispName: "ISP", wanIP: "1.2.3.4", status: "ok",
            latencyMs: 10, availability: 100, drops: 0,
            rxBytesRate: 1_000, txBytesRate: 1_000, speedTest: nil
        )
        status.updateWANHealth(health)
        #expect(status.wanIsUp == true)

        status.updateWANHealth(nil)
        #expect(status.wanIsUp == nil)
        #expect(status.wanIP == nil)
        #expect(status.wanISP == nil)
        #expect(status.wanLatencyMs == nil)
        #expect(status.wanAvailability == nil)
        #expect(status.wanTxBytesRate == nil)
        #expect(status.wanRxBytesRate == nil)
    }

    @Test func testUpdateWANHealthWithSpeedTest() {
        let status = WiFiStatus()
        let speedTest = SpeedTestResult(
            downloadMbps: 950, uploadMbps: 40,
            pingMs: 8, lastRun: Date(timeIntervalSince1970: 1_700_000_000),
            status: "Done"
        )
        let health = WANHealth(
            ispName: nil, wanIP: nil, status: "ok",
            latencyMs: nil, availability: nil, drops: nil,
            rxBytesRate: nil, txBytesRate: nil,
            speedTest: speedTest
        )

        status.updateWANHealth(health)
        #expect(status.speedTest?.downloadMbps == 950)
        #expect(status.speedTest?.uploadMbps == 40)
    }

    // MARK: - updateVPN

    @Test func testUpdateVPNPopulated() {
        let status = WiFiStatus()
        let tunnels = [
            VPNTunnelDTO(_id: "1", name: "Office", status: "CONNECTED", remoteNetworkCidr: nil, type: nil),
            VPNTunnelDTO(_id: "2", name: "Home", status: "DOWN", remoteNetworkCidr: nil, type: nil),
        ]

        status.updateVPN(tunnels)
        #expect(status.vpnTunnels?.count == 2)
    }

    @Test func testUpdateVPNEmptyBecomesNil() {
        let status = WiFiStatus()
        status.vpnTunnels = [VPNTunnelDTO(_id: "1", name: "X", status: "UP")]
        status.updateVPN([])
        #expect(status.vpnTunnels == nil)
    }

    @Test func testUpdateVPNNil() {
        let status = WiFiStatus()
        status.vpnTunnels = [VPNTunnelDTO(_id: "1", name: "X", status: "UP")]
        status.updateVPN(nil)
        #expect(status.vpnTunnels == nil)
    }

    // MARK: - updateGateway

    @Test func testUpdateGateway() {
        let status = WiFiStatus()
        let stats = GatewayStats(uptimeSec: 86400, cpuUtilizationPct: 12.5, memoryUtilizationPct: 45.0, uplinkTxRateBps: nil, uplinkRxRateBps: nil)
        let dev = device(id: "g1", mac: "gg", name: "UCG Fiber", state: "ONLINE")

        status.updateGateway(stats, device: dev)

        #expect(status.gatewayCPU == 12.5)
        #expect(status.gatewayMemory == 45.0)
        #expect(status.gatewayUptime == 86400)
        #expect(status.gatewayName == "UCG Fiber")
    }

    @Test func testUpdateGatewayNilStats() {
        let status = WiFiStatus()
        status.gatewayCPU = 50
        status.gatewayName = "Old"

        status.updateGateway(nil, device: nil)

        #expect(status.gatewayCPU == nil)
        #expect(status.gatewayMemory == nil)
        #expect(status.gatewayUptime == nil)
        #expect(status.gatewayName == nil)
    }

    // MARK: - updateAPStats

    @Test func testUpdateAPStats() {
        let status = WiFiStatus()
        let stats = APStats(uptimeSec: 3600, cpuUtilizationPct: 5.0, memoryUtilizationPct: 30.0)
        status.updateAPStats(stats)

        #expect(status.apCPU == 5.0)
        #expect(status.apMemory == 30.0)
    }

    @Test func testUpdateAPStatsNil() {
        let status = WiFiStatus()
        status.apCPU = 10
        status.apMemory = 20
        status.updateAPStats(nil)

        #expect(status.apCPU == nil)
        #expect(status.apMemory == nil)
    }

    // MARK: - updateSessions

    @Test func testUpdateSessionsMultipleAPs() {
        let status = WiFiStatus()
        let dtos = [
            SessionDTO(mac: "aa", apMac: "11:22:33", duration: 3600, assocTime: nil),
            SessionDTO(mac: "aa", apMac: "11:22:33", duration: 7200, assocTime: nil),
            SessionDTO(mac: "aa", apMac: "44:55:66", duration: 1800, assocTime: nil),
        ]
        let devices: [DeviceDTO] = []

        status.updateSessions(dtos, devices: devices)
        #expect(status.sessions?.count == 2)
        #expect(status.sessions?.first?.apName == "11:22:33")
        #expect(status.sessions?.first?.duration == 10800)
    }

    @Test func testUpdateSessionsResolvesAPNames() {
        let status = WiFiStatus()
        let dtos = [SessionDTO(mac: "mac1", apMac: "aa:bb:cc", duration: 1000, assocTime: nil)]
        let devices = [device(id: "1", mac: "aa:bb:cc", name: "Living Room AP", state: "ONLINE")]

        status.updateSessions(dtos, devices: devices)
        #expect(status.sessions?.first?.apName == "Living Room AP")
    }

    @Test func testUpdateSessionsSkipsNilFields() {
        let status = WiFiStatus()
        let dtos = [SessionDTO(mac: "aa", apMac: nil, duration: 500, assocTime: nil)]

        status.updateSessions(dtos, devices: [])
        #expect(status.sessions?.isEmpty == true)
    }

    @Test func testUpdateSessionsNil() {
        let status = WiFiStatus()
        status.sessions = [WiFiStatus.SessionEntry(apName: "x", duration: 1, fraction: 1.0)]
        status.updateSessions(nil, devices: [])
        #expect(status.sessions == nil)
    }

    // MARK: - updateMonitoring

    @Test func testUpdateMonitoring() {
        let status = WiFiStatus()
        let ddns = [DDNSStatusDTO(status: "good", service: "dyndns", hostName: "home.example.com", login: nil, interface: nil)]
        let pf: [PortForwardDTO]? = nil
        let rogue: [RogueAPDTO]? = nil

        status.updateMonitoring(ddns: ddns, portForwards: pf, rogueAPs: rogue)
        #expect(status.ddnsStatuses?.count == 1)
        #expect(status.portForwards == nil)
        #expect(status.nearbyAPs == nil)
    }

    // MARK: - Display Properties: uptime

    @Test func testFormattedUptime() {
        let status = WiFiStatus()
        status.uptime = 7200
        #expect(status.formattedUptime == "2h 0m")
        status.uptime = 1800
        #expect(status.formattedUptime == "30m")
        status.uptime = nil
        #expect(status.formattedUptime == "—")
    }

    @Test func testFormattedGatewayUptime() {
        let status = WiFiStatus()
        status.gatewayUptime = 90000
        #expect(status.formattedGatewayUptime == "1d 1h")
        status.gatewayUptime = 3600
        #expect(status.formattedGatewayUptime == "1h 0m")
        status.gatewayUptime = 0
        #expect(status.formattedGatewayUptime == nil)
        status.gatewayUptime = nil
        #expect(status.formattedGatewayUptime == nil)
    }

    // MARK: - Display Properties: WAN

    @Test func testFormattedWANThroughput() {
        let status = WiFiStatus()
        status.wanTxBytesRate = 2_000_000_000
        status.wanRxBytesRate = 1_000_000_000
        #expect(status.formattedWANThroughput == "↓ 1.0 GB/s ↑ 2.0 GB/s")
        status.wanTxBytesRate = 0
        status.wanRxBytesRate = 0
        #expect(status.formattedWANThroughput == nil)
    }

    @Test func testFormattedWANLatency() {
        let status = WiFiStatus()
        status.wanLatencyMs = 8
        #expect(status.formattedWANLatency == "8 ms")
        status.wanLatencyMs = nil
        #expect(status.formattedWANLatency == nil)
    }

    @Test func testFormattedWANAvailability() {
        let status = WiFiStatus()
        status.wanAvailability = 100
        #expect(status.formattedWANAvailability == "100%")
        status.wanAvailability = 99.5
        #expect(status.formattedWANAvailability == "99.5%")
        status.wanAvailability = nil
        #expect(status.formattedWANAvailability == nil)
    }

    // MARK: - Display Properties: network overview

    @Test func testFormattedNetworkOverview() {
        let status = WiFiStatus()
        status.totalClients = 8
        status.clientsOnSameAP = 3
        status.apName = "U7 Pro"
        #expect(status.formattedNetworkOverview == "8 clients · 3 on U7 Pro")
        status.apName = nil
        #expect(status.formattedNetworkOverview == "8 clients")
        status.clientsOnSameAP = nil
        #expect(status.formattedNetworkOverview == "8 clients")
    }

    @Test func testFormattedDeviceOverview() {
        let status = WiFiStatus()
        status.totalDevices = 5
        status.onlineDevices = 5
        #expect(status.formattedDeviceOverview == "5 devices · all online")
        status.onlineDevices = 3
        #expect(status.formattedDeviceOverview == "3 online · 2 offline")
        status.totalDevices = 1
        status.onlineDevices = 1
        #expect(status.formattedDeviceOverview == "1 device · all online")
        status.totalDevices = nil
        #expect(status.formattedDeviceOverview == nil)
    }

    @Test func testFirmwareBadge() {
        let status = WiFiStatus()
        status.devicesWithUpdates = ["AP1"]
        #expect(status.firmwareBadge == "1 device update available")
        status.devicesWithUpdates = ["AP1", "Switch"]
        #expect(status.firmwareBadge == "2 devices update available")
        status.devicesWithUpdates = nil
        #expect(status.firmwareBadge == nil)
    }

    // MARK: - Display Properties: roam, tx, AP load, signal

    @Test func testFormattedRoamCountSingular() {
        let status = WiFiStatus()
        status.roamCount = 1
        #expect(status.formattedRoamCount == "1 roam")
        status.roamCount = 5
        #expect(status.formattedRoamCount == "5 roams")
        status.roamCount = nil
        #expect(status.formattedRoamCount == nil)
    }

    @Test func testFormattedTxRetries() {
        let status = WiFiStatus()
        status.txRetriesPct = 2.3
        #expect(status.formattedTxRetries == "2.3%")
        status.txRetriesPct = 0
        #expect(status.formattedTxRetries == nil)
        status.txRetriesPct = nil
        #expect(status.formattedTxRetries == nil)
    }

    @Test func testFormattedAPLoad() {
        let status = WiFiStatus()
        status.apCPU = 5.2
        status.apMemory = 30.7
        #expect(status.formattedAPLoad == "CPU 5% · Mem 30%")
        status.apCPU = nil
        #expect(status.formattedAPLoad == nil)
    }

    @Test func testFormattedNoiseFloor() {
        let status = WiFiStatus()
        status.noiseFloor = -92
        #expect(status.formattedNoiseFloor == "-92 dBm")
        status.noiseFloor = nil
        #expect(status.formattedNoiseFloor == "—")
    }

    @Test func testFormattedChannelWidth() {
        let status = WiFiStatus()
        status.channelWidth = 80
        #expect(status.formattedChannelWidth == "80 MHz")
        status.channelWidth = 160
        #expect(status.formattedChannelWidth == "160 MHz")
        status.channelWidth = nil
        #expect(status.formattedChannelWidth == nil)
    }

    @Test func testFormattedSessionData() {
        let status = WiFiStatus()
        status.rxBytes = 2_000_000_000
        status.txBytes = 500_000_000
        #expect(status.formattedSessionData == "↓ 2.0 GB ↑ 500.0 MB")
        status.rxBytes = nil
        #expect(status.formattedSessionData == nil)
    }

    @Test func testSignalDescription() {
        let status = WiFiStatus()
        status.signal = -55
        #expect(status.signalDescription == "-55 dBm")
        status.signal = nil
        #expect(status.signalDescription == "—")
    }

    @Test func testFormattedGatewayLoad() {
        let status = WiFiStatus()
        status.gatewayCPU = 15.8
        status.gatewayMemory = 48.3
        #expect(status.formattedGatewayLoad == "CPU 15% · Mem 48%")
        status.gatewayCPU = nil
        #expect(status.formattedGatewayLoad == nil)
    }

    // MARK: - TrendDirection symbol

    @Test func testTrendDirectionSymbols() {
        #expect(WiFiStatus.TrendDirection.up.symbol == "↑")
        #expect(WiFiStatus.TrendDirection.down.symbol == "↓")
        #expect(WiFiStatus.TrendDirection.stable.symbol == "→")
    }

    // MARK: - Helpers

    private func device(
        id: String,
        mac: String,
        name: String,
        state: String?,
        firmwareUpdatable: Bool? = nil
    ) -> DeviceDTO {
        DeviceDTO(
            id: id,
            macAddress: mac,
            name: name,
            model: nil,
            state: state,
            firmwareUpdatable: firmwareUpdatable,
            features: nil,
            firmwareVersion: nil,
            ipAddress: nil
        )
    }
}
