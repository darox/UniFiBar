import Foundation
import Testing
@testable import UniFiBar

@MainActor
struct PreferencesManagerTests {

    private func withDefaults(_ check: (UserDefaults) -> Void) {
        let suite = "UniFiBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check(defaults)
    }

    @Test func testSectionVisibility() {
        withDefaults { defaults in
            let prefs = PreferencesManager(defaults: defaults)
            for section in [MenuSection.internet, .vpn, .wifi, .network, .sessionHistory] {
                #expect(prefs.isSectionEnabled(section))
            }
            for section in [MenuSection.ddns, .portForwards, .nearbyAPs] {
                #expect(!prefs.isSectionEnabled(section))
            }
            prefs.setSectionEnabled(.ddns, enabled: true)
            #expect(prefs.isSectionEnabled(.ddns))
            #expect(PreferencesManager(defaults: defaults).isSectionEnabled(.ddns))
            prefs.setSectionEnabled(.ddns, enabled: false)
            #expect(!prefs.isSectionEnabled(.ddns))
            #expect(!PreferencesManager(defaults: defaults).isSectionEnabled(.ddns))
        }
    }

    @Test(arguments: [(5, 10), (500, 300), (30, 30), (10, 10), (300, 300)])
    func testPollIntervalClamping(input: Int, expected: Int) {
        withDefaults { defaults in
            let prefs = PreferencesManager(defaults: defaults)
            #expect(prefs.pollIntervalSeconds == 30)
            prefs.setPollInterval(input)
            #expect(prefs.pollIntervalSeconds == expected)
            #expect(PreferencesManager(defaults: defaults).pollIntervalSeconds == expected)
        }
    }
}
