import Foundation
import Testing
@testable import UniFiBar

@MainActor
struct DiagnosticsLogTests {
    @Test func defaultExportOmitsIdentifiersAndUntrustedText() {
        let status = WiFiStatus()
        let log = DiagnosticsLog()
        let secret = "synthetic-private-marker"
        status.ip = secret
        status.essid = secret
        status.apName = secret
        status.wifiStandard = secret
        status.mimoDescription = secret
        status.wanISP = secret
        status.gatewayName = secret
        status.vpnTunnels = [VPNTunnelDTO(name: secret, status: secret)]
        status.totalClients = 12
        status.clientsOnSameAP = 3
        status.signal = -55
        log.record(.connection, level: .error, message: secret, detail: "Bearer \(secret)")
        let report = log.exportText(
            errorState: .controllerUnreachable(reason: secret), consecutiveErrors: 2,
            pollInterval: 30, controllerHost: secret, allowSelfSignedCerts: false, wifiStatus: status
        )
        #expect(!report.contains(secret))
        #expect(report.contains("Signal: -55 dBm"))
        #expect(report.contains("ERROR connection"))
        #expect(report.contains("Controller Unreachable"))
    }

    @Test func fullDetailsRequireOptInAndEventsStayBoundedAndOrdered() {
        let status = WiFiStatus()
        let log = DiagnosticsLog()
        for index in 0..<201 {
            log.record(.monitoring, level: .info, message: "private-event-\(index)")
        }
        #expect(log.recentEvents.count == 200)
        let report = log.exportText(errorState: nil, consecutiveErrors: 0, pollInterval: 30,
            controllerHost: "private-controller.invalid", allowSelfSignedCerts: false,
            wifiStatus: status, includePrivateDetails: true)
        #expect(report.contains("PRIVATE DETAILS INCLUDED"))
        #expect(report.contains("private-controller.invalid"))
        #expect(!report.contains("private-event-0\n"))
        let events = report.split(separator: "\n").filter { $0.contains("private-event-") }
        #expect(events.first?.hasSuffix("private-event-200") == true)
        #expect(events.last?.hasSuffix("private-event-1") == true)
        log.clear()
        #expect(log.recentEvents.isEmpty)
    }

    @Test func typedStatusAndAvailabilitySurviveRedaction() {
        let status = WiFiStatus()
        status.dataAvailability[.devices] = .unavailable
        let report = DiagnosticsLog().exportText(errorState: .invalidAPIKey(httpCode: 401),
            consecutiveErrors: 1, pollInterval: 30, controllerHost: nil,
            allowSelfSignedCerts: false, wifiStatus: status)
        #expect(report.contains("HTTP 401"))
        #expect(report.contains("Devices: Unavailable"))
    }
}
