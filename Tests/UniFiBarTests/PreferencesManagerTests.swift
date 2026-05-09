import Foundation
import Testing
@testable import UniFiBar

@MainActor
struct PreferencesManagerTests {

    private final actor FakeKeychain: KeychainHelperProtocol {
        private var storage: [String: String] = [:]
        var saveError: KeychainError? = nil

        func setSaveError(_ error: KeychainError?) {
            saveError = error
        }

        func read(_ key: KeychainHelper.Key) -> String? {
            storage[key.rawValue]
        }

        func save(_ value: String, for key: KeychainHelper.Key) throws {
            if let error = saveError { throw error }
            storage[key.rawValue] = value
        }

        func delete(_ key: KeychainHelper.Key) {
            storage[key.rawValue] = nil
        }
    }

    private func makePrefs() -> (PreferencesManager, FakeKeychain) {
        let keychain = FakeKeychain()
        let prefs = PreferencesManager(keychain: keychain)
        return (prefs, keychain)
    }

    // MARK: - Default Section Visibility

    @Test func testDefaultSectionVisibility() async {
        let (prefs, _) = makePrefs()
        await prefs.resetAll()
        let fresh = PreferencesManager()
        #expect(fresh.isSectionEnabled(.internet) == true)
        #expect(fresh.isSectionEnabled(.vpn) == true)
        #expect(fresh.isSectionEnabled(.wifi) == true)
        #expect(fresh.isSectionEnabled(.network) == true)
        #expect(fresh.isSectionEnabled(.sessionHistory) == true)
        #expect(fresh.isSectionEnabled(.ddns) == false)
        #expect(fresh.isSectionEnabled(.portForwards) == false)
        #expect(fresh.isSectionEnabled(.nearbyAPs) == false)
    }

    @Test func testSetSectionEnabled() async {
        let (prefs, _) = makePrefs()
        await prefs.resetAll()
        let fresh = PreferencesManager()
        #expect(fresh.isSectionEnabled(.ddns) == false)
        fresh.setSectionEnabled(.ddns, enabled: true)
        #expect(fresh.isSectionEnabled(.ddns) == true)
        fresh.setSectionEnabled(.ddns, enabled: false)
        #expect(fresh.isSectionEnabled(.ddns) == false)
    }

    // MARK: - Poll Interval Clamping

    @Test func testPollIntervalClamping_min() async {
        let (prefs, _) = makePrefs()
        await prefs.resetAll()
        prefs.setPollInterval(5)
        #expect(prefs.pollIntervalSeconds == 10)
    }

    @Test func testPollIntervalClamping_max() async {
        let (prefs, _) = makePrefs()
        await prefs.resetAll()
        prefs.setPollInterval(500)
        #expect(prefs.pollIntervalSeconds == 300)
    }

    @Test func testPollIntervalClamping_valid() async {
        let (prefs, _) = makePrefs()
        await prefs.resetAll()
        prefs.setPollInterval(30)
        #expect(prefs.pollIntervalSeconds == 30)
    }

    @Test func testPollIntervalClamping_boundaryMin() async {
        let (prefs, _) = makePrefs()
        await prefs.resetAll()
        prefs.setPollInterval(10)
        #expect(prefs.pollIntervalSeconds == 10)
    }

    @Test func testPollIntervalClamping_boundaryMax() async {
        let (prefs, _) = makePrefs()
        await prefs.resetAll()
        prefs.setPollInterval(300)
        #expect(prefs.pollIntervalSeconds == 300)
    }

    // MARK: - hasMonitoringSectionsEnabled

    @Test func testHasMonitoringSectionsEnabled_withDefaults() async {
        let (prefs, _) = makePrefs()
        await prefs.resetAll()
        let fresh = PreferencesManager()
        #expect(fresh.hasMonitoringSectionsEnabled == false)
    }

    @Test func testHasMonitoringSectionsEnabled_allDisabled() async {
        let (prefs, _) = makePrefs()
        for section in [MenuSection.ddns, .portForwards, .nearbyAPs] {
            prefs.setSectionEnabled(section, enabled: false)
        }
        #expect(prefs.hasMonitoringSectionsEnabled == false)
    }

    @Test func testHasMonitoringSectionsEnabled_oneEnabled() async {
        let (prefs, _) = makePrefs()
        for section in [MenuSection.ddns, .portForwards, .nearbyAPs] {
            prefs.setSectionEnabled(section, enabled: false)
        }
        prefs.setSectionEnabled(.ddns, enabled: true)
        #expect(prefs.hasMonitoringSectionsEnabled == true)
    }

    // MARK: - checkConfiguration

    @Test func testCheckConfigurationWithCredentials() async throws {
        let (prefs, keychain) = makePrefs()
        try await keychain.save("https://192.168.1.1", for: .controllerURL)
        try await keychain.save("test-api-key", for: .apiKey)

        await prefs.checkConfiguration()
        #expect(prefs.isConfigured == true)
        #expect(prefs.cachedURL == "https://192.168.1.1")
        #expect(prefs.cachedAPIKey == "test-api-key")
    }

    @Test func testCheckConfigurationMissingURL() async throws {
        let (prefs, keychain) = makePrefs()
        try await keychain.save("test-api-key", for: .apiKey)

        await prefs.checkConfiguration()
        #expect(prefs.isConfigured == false)
    }

    @Test func testCheckConfigurationMissingAPIKey() async throws {
        let (prefs, keychain) = makePrefs()
        try await keychain.save("https://192.168.1.1", for: .controllerURL)

        await prefs.checkConfiguration()
        #expect(prefs.isConfigured == false)
    }

    @Test func testCheckConfigurationCacheReuse() async throws {
        let (prefs, keychain) = makePrefs()
        try await keychain.save("https://192.168.1.1", for: .controllerURL)
        try await keychain.save("key1", for: .apiKey)

        await prefs.checkConfiguration()
        #expect(prefs.isConfigured == true)

        await keychain.delete(.apiKey)
        try await keychain.save("key2", for: .apiKey)

        await prefs.checkConfiguration()
        #expect(prefs.cachedAPIKey == "key1")
    }

    // MARK: - save

    @Test func testSaveCredentials() async throws {
        let (prefs, keychain) = makePrefs()

        try await prefs.save(controllerURL: "https://10.0.0.1", apiKey: "new-key", allowSelfSigned: true)

        #expect(prefs.isConfigured == true)
        #expect(prefs.allowSelfSignedCerts == true)
        #expect(prefs.cachedURL == "https://10.0.0.1")
        #expect(prefs.cachedAPIKey == "new-key")

        let savedURL = await keychain.read(.controllerURL)
        let savedKey = await keychain.read(.apiKey)
        #expect(savedURL == "https://10.0.0.1")
        #expect(savedKey == "new-key")
    }

    @Test func testSaveCredentialsWithError() async {
        let (prefs, keychain) = makePrefs()
        await keychain.setSaveError(KeychainError.saveFailed(status: -1))

        do {
            try await prefs.save(controllerURL: "https://x", apiKey: "k", allowSelfSigned: false)
            #expect(Bool(false))
        } catch {
            #expect(error is KeychainError)
        }
    }

    // MARK: - loadClient

    @Test func testLoadClientWithCredentials() async throws {
        let (prefs, keychain) = makePrefs()
        try await keychain.save("https://192.168.1.1", for: .controllerURL)
        try await keychain.save("api-key-123", for: .apiKey)
        prefs.allowSelfSignedCerts = true

        let client = await prefs.loadClient()
        #expect(client != nil)
    }

    @Test func testLoadClientNoCredentials() async {
        let (prefs, _) = makePrefs()

        let client = await prefs.loadClient()
        #expect(client == nil)
        #expect(prefs.isConfigured == false)
    }

    @Test func testLoadClientInvalidURL() async throws {
        let (prefs, keychain) = makePrefs()
        try await keychain.save("", for: .controllerURL)
        try await keychain.save("key", for: .apiKey)

        let client = await prefs.loadClient()
        #expect(client == nil)
        #expect(prefs.isConfigured == false)
    }

    // MARK: - resetAll

    @Test func testResetAll() async throws {
        let (prefs, keychain) = makePrefs()
        try await keychain.save("https://192.168.1.1", for: .controllerURL)
        try await keychain.save("key", for: .apiKey)
        prefs.allowSelfSignedCerts = true
        prefs.isConfigured = true
        prefs.setPollInterval(15)
        prefs.setSectionEnabled(.ddns, enabled: true)

        await prefs.resetAll()

        #expect(prefs.isConfigured == false)
        #expect(prefs.allowSelfSignedCerts == false)
        #expect(prefs.pollIntervalSeconds == 30)
        #expect(prefs.cachedURL == nil)
        #expect(prefs.cachedAPIKey == nil)
        #expect(prefs.isSectionEnabled(.ddns) == false)

        let url = await keychain.read(.controllerURL)
        let key = await keychain.read(.apiKey)
        #expect(url == nil)
        #expect(key == nil)
    }
}
