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
        // Populate all fields
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
        // Input is Kbps — 500000 Kbps = 500 Mbps
        #expect(status.formatRate(500_000) == "500 Mbps")
        #expect(status.formatRate(1_000_000) == "1.00 Gbps")
        #expect(status.formatRate(1_500_000) == "1.50 Gbps")
        #expect(status.formatRate(1_200_000) == "1.20 Gbps")
        #expect(status.formatRate(54_000) == "54 Mbps")
        // nil
        #expect(status.formatRate(nil) == "—")
    }

    // MARK: - Format Bytes

    @Test func testFormatBytes() {
        let status = WiFiStatus()
        #expect(status.formatBytes(500_000) == "500 KB")
        #expect(status.formatBytes(1_500_000) == "1.5 MB")
        #expect(status.formatBytes(1_000_000_000) == "1.0 GB")
        #expect(status.formatBytes(2_000_000_000) == "2.0 GB")
    }
}