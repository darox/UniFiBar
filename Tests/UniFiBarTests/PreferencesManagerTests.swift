import Foundation
import Testing
@testable import UniFiBar

@MainActor
struct PreferencesManagerTests {

    private func makePrefs(defaults: UserDefaults) -> (PreferencesManager, FakeKeychain) {
        let keychain = FakeKeychain()
        let prefs = PreferencesManager(defaults: defaults, keychain: keychain)
        return (prefs, keychain)
    }

    private func withDefaults(_ check: (UserDefaults) async throws -> Void) async rethrows {
        let suite = "UniFiBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await check(defaults)
    }

    @Test func testSectionVisibility() async {
        await withDefaults { defaults in
            let prefs = PreferencesManager(defaults: defaults, keychain: FakeKeychain())
            for section in [MenuSection.internet, .vpn, .wifi, .network, .sessionHistory] {
                #expect(prefs.isSectionEnabled(section))
            }
            for section in [MenuSection.ddns, .portForwards, .nearbyAPs] {
                #expect(!prefs.isSectionEnabled(section))
            }
            prefs.setSectionEnabled(.ddns, enabled: true)
            #expect(prefs.isSectionEnabled(.ddns))
            #expect(PreferencesManager(defaults: defaults, keychain: FakeKeychain()).isSectionEnabled(.ddns))
            prefs.setSectionEnabled(.ddns, enabled: false)
            #expect(!prefs.isSectionEnabled(.ddns))
            #expect(!PreferencesManager(defaults: defaults, keychain: FakeKeychain()).isSectionEnabled(.ddns))
        }
    }

    @Test(arguments: [(5, 10), (500, 300), (30, 30), (10, 10), (300, 300)])
    func testPollIntervalClamping(input: Int, expected: Int) async {
        await withDefaults { defaults in
            let prefs = PreferencesManager(defaults: defaults, keychain: FakeKeychain())
            #expect(prefs.pollIntervalSeconds == 30)
            prefs.setPollInterval(input)
            #expect(prefs.pollIntervalSeconds == expected)
            #expect(PreferencesManager(defaults: defaults, keychain: FakeKeychain()).pollIntervalSeconds == expected)
        }
    }

    // MARK: - checkConfiguration

    @Test func testCheckConfigurationWithCredentials() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.save("https://192.168.1.1", for: .controllerURL)
            try await keychain.save("test-api-key", for: .apiKey)

            await prefs.checkConfiguration()
            #expect(prefs.isConfigured == true)
            #expect(prefs.cachedURL == "https://192.168.1.1")
            #expect(prefs.cachedAPIKey == "test-api-key")
        }
    }

    @Test func testCheckConfigurationMissingURL() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.save("test-api-key", for: .apiKey)

            await prefs.checkConfiguration()
            #expect(prefs.isConfigured == false)
        }
    }

    @Test func testCheckConfigurationMissingAPIKey() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.save("https://192.168.1.1", for: .controllerURL)

            await prefs.checkConfiguration()
            #expect(prefs.isConfigured == false)
        }
    }

    @Test func testCheckConfigurationCacheReuse() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.save("https://192.168.1.1", for: .controllerURL)
            try await keychain.save("key1", for: .apiKey)

            await prefs.checkConfiguration()
            #expect(prefs.isConfigured == true)

            await keychain.delete(.apiKey)
            try await keychain.save("key2", for: .apiKey)

            await prefs.checkConfiguration()
            #expect(prefs.cachedAPIKey == "key1")
        }
    }

    // MARK: - save

    @Test func testSaveCredentials() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)

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
    }

    @Test func testSaveCredentialsWithError() async {
        await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            await keychain.setSaveError(KeychainError.saveFailed(status: -1))

            do {
                try await prefs.save(controllerURL: "https://x", apiKey: "k", allowSelfSigned: false)
                #expect(Bool(false))
            } catch {
                #expect(error is KeychainError)
            }
        }
    }

    // MARK: - loadClient

    @Test func testLoadClientWithCredentialsWithoutPinning() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.save("https://192.168.1.1", for: .controllerURL)
            try await keychain.save("api-key-123", for: .apiKey)
            // Pinned construction reads the native pin store; separate-account QA only.
            prefs.allowSelfSignedCerts = false

            let client = await prefs.loadClient()
            #expect(client != nil)
            await client?.invalidate()
        }
    }

    @Test func testLoadClientNoCredentials() async {
        await withDefaults { defaults in
            let (prefs, _) = makePrefs(defaults: defaults)

            let client = await prefs.loadClient()
            #expect(client == nil)
            #expect(prefs.isConfigured == false)
        }
    }

    @Test func testLoadClientInvalidURL() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.save("", for: .controllerURL)
            try await keychain.save("key", for: .apiKey)

            let client = await prefs.loadClient()
            #expect(client == nil)
            #expect(prefs.isConfigured == false)
        }
    }

    // MARK: - resetAll

    @Test(.disabled("resetAll unregisters the real login item; run reset QA in a separate macOS account"))
    func testResetAll() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
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
}
