import AppKit
import SwiftUI
import Testing
@testable import UniFiBar

/// Offscreen hosting only: never launches UniFiBar, starts polling or presses native actions.
@MainActor
struct MenuLayoutTests {
    @Test(arguments: [false, true], [360.0, 600.0, 1000.0])
    func connectedMenuHasUsableViewport(compact: Bool, height: Double) throws {
        let suite = "UniFiBarTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = PreferencesManager(defaults: defaults, keychain: FakeKeychain(),
            removePins: {}, unregisterLoginItem: {})
        prefs.isConfigured = true
        prefs.compactMode = compact
        let controller = StatusBarController(fixturePreferences: prefs, clientLoader: { nil })
        controller.wifiStatus.isConnected = true
        controller.wifiStatus.essid = String(repeating: "Synthetic long network ", count: 5)
        controller.wifiStatus.beginSupplementalRefresh()
        controller.wifiStatus.vpnTunnels = (0..<30).map { VPNTunnelDTO(name: "Synthetic tunnel \($0)", status: nil) }
        controller.wifiStatus.dataAvailability[.vpn] = .available
        controller.wifiStatus.dataAvailability[.devices] = .unavailable
        let host = NSHostingView(rootView: MenuContentView(controller: controller, availableHeight: height).frame(width: 320))
        let size = host.fittingSize
        print("CONNECTED compact=\(compact) fitting=\(size)")
        #expect(size.width == 320)
        #expect(size.height >= 300 && size.height <= height)
        #expect(controller.pollTask == nil)
    }

    @Test(arguments: [false, true])
    func nonConnectedMenuDoesNotForceFullScreenHeight(configured: Bool) throws {
        let suite = "UniFiBarTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = PreferencesManager(defaults: defaults, keychain: FakeKeychain(),
            removePins: {}, unregisterLoginItem: {})
        let controller = StatusBarController(fixturePreferences: prefs, clientLoader: { nil })
        prefs.isConfigured = configured
        if configured { controller.wifiStatus.markError(.invalidAPIKey(httpCode: 401)) }
        let host = NSHostingView(rootView: MenuContentView(controller: controller).frame(width: 320))
        let size = host.fittingSize
        #expect(size.width == 320)
        #expect(size.height > 80 && size.height < 500)
        #expect(controller.pollTask == nil)
        #expect(!controller.hasSystemObservers)
    }
}
