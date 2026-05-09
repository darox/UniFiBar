import Testing
@testable import UniFiBar

@MainActor
struct PreferencesManagerTests {

    // MARK: - Default Section Visibility

    @Test func testDefaultSectionVisibility() async {
        // Use a fresh instance with isolated UserDefaults
        let prefs = PreferencesManager()
        // Clear any stale section visibility from previous app runs
        await prefs.resetAll()
        // Re-create to get fresh defaults after reset
        let fresh = PreferencesManager()
        // Enabled by default
        #expect(fresh.isSectionEnabled(.internet) == true)
        #expect(fresh.isSectionEnabled(.vpn) == true)
        #expect(fresh.isSectionEnabled(.wifi) == true)
        #expect(fresh.isSectionEnabled(.network) == true)
        #expect(fresh.isSectionEnabled(.sessionHistory) == true)
        // Disabled by default
        #expect(fresh.isSectionEnabled(.ddns) == false)
        #expect(fresh.isSectionEnabled(.portForwards) == false)
        #expect(fresh.isSectionEnabled(.nearbyAPs) == false)
    }

    @Test func testSetSectionEnabled() async {
        let prefs = PreferencesManager()
        await prefs.resetAll()
        let fresh = PreferencesManager()
        #expect(fresh.isSectionEnabled(.ddns) == false)
        fresh.setSectionEnabled(.ddns, enabled: true)
        #expect(fresh.isSectionEnabled(.ddns) == true)
        fresh.setSectionEnabled(.ddns, enabled: false)
        #expect(fresh.isSectionEnabled(.ddns) == false)
    }

    // MARK: - Poll Interval Clamping

    @Test func testPollIntervalClamping_min() {
        let prefs = PreferencesManager()
        prefs.setPollInterval(5)
        #expect(prefs.pollIntervalSeconds == 10)
    }

    @Test func testPollIntervalClamping_max() {
        let prefs = PreferencesManager()
        prefs.setPollInterval(500)
        #expect(prefs.pollIntervalSeconds == 300)
    }

    @Test func testPollIntervalClamping_valid() {
        let prefs = PreferencesManager()
        prefs.setPollInterval(30)
        #expect(prefs.pollIntervalSeconds == 30)
    }

    @Test func testPollIntervalClamping_boundaryMin() {
        let prefs = PreferencesManager()
        prefs.setPollInterval(10)
        #expect(prefs.pollIntervalSeconds == 10)
    }

    @Test func testPollIntervalClamping_boundaryMax() {
        let prefs = PreferencesManager()
        prefs.setPollInterval(300)
        #expect(prefs.pollIntervalSeconds == 300)
    }

    // MARK: - hasMonitoringSectionsEnabled

    @Test func testHasMonitoringSectionsEnabled_withDefaults() async {
        let prefs = PreferencesManager()
        await prefs.resetAll()
        let fresh = PreferencesManager()
        // All monitoring sections are disabled by default after reset
        #expect(fresh.hasMonitoringSectionsEnabled == false)
    }

    @Test func testHasMonitoringSectionsEnabled_allDisabled() {
        let prefs = PreferencesManager()
        for section in [MenuSection.ddns, .portForwards, .nearbyAPs] {
            prefs.setSectionEnabled(section, enabled: false)
        }
        #expect(prefs.hasMonitoringSectionsEnabled == false)
    }

    @Test func testHasMonitoringSectionsEnabled_oneEnabled() {
        let prefs = PreferencesManager()
        for section in [MenuSection.ddns, .portForwards, .nearbyAPs] {
            prefs.setSectionEnabled(section, enabled: false)
        }
        prefs.setSectionEnabled(.ddns, enabled: true)
        #expect(prefs.hasMonitoringSectionsEnabled == true)
    }
}