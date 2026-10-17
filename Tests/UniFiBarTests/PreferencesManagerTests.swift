import Foundation
import os
import Security
import Testing
@testable import UniFiBar

@MainActor
struct PreferencesManagerTests {

    @Test func missingEntitlementResetGivesSigningGuidanceWithoutHidingFailure() async throws {
        try await withDefaults { defaults in
            let keychain = FakeKeychain()
            await keychain.setDeleteError(.deleteFailed(status: errSecMissingEntitlement))
            var pins = 0
            var loginItems = 0
            let prefs = PreferencesManager(defaults: defaults, keychain: keychain,
                removePins: { pins += 1 }, unregisterLoginItem: { loginItems += 1 })
            await #expect(throws: PreferencesManager.ResetError.self) { try await prefs.resetAll().value }
            let message = try #require(prefs.credentialError)
            #expect(message.contains("-34018"))
            #expect(message.contains("appropriately signed build"))
            #expect(message.contains("Some records may remain"))
            #expect(!prefs.automaticConnectionAllowed)
            #expect(pins == 1 && loginItems == 1)
        }
    }

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
            try await keychain.seedCredentials(url: "https://192.168.1.1", key: "test-api-key")

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
            try await keychain.seedCredentials(url: "https://192.168.1.1", key: "key1")

            await prefs.checkConfiguration()
            #expect(prefs.isConfigured == true)

            try await keychain.seedCredentials(url: "https://192.168.1.1", key: "key2")

            await prefs.checkConfiguration()
            #expect(prefs.cachedAPIKey == "key1")
        }
    }

    // MARK: - save

    @Test func testSaveFailureNeverRestoresMixedCredentials() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await prefs.save(controllerURL: "https://old.invalid", apiKey: "old-key", allowSelfSigned: false)
            await keychain.setSaveError(.saveFailed(status: -1), forKey: .apiKey)
            var saved = false
            do {
                try await prefs.save(controllerURL: "https://new.invalid", apiKey: "new-key", allowSelfSigned: false)
                saved = true
            } catch {}
            let restored = PreferencesManager(defaults: defaults, keychain: keychain)
            await restored.checkConfiguration()
            #expect(restored.cachedURL == (saved ? "https://new.invalid" : "https://old.invalid"))
            #expect(restored.cachedAPIKey == (saved ? "new-key" : "old-key"))
        }
    }

    @Test func testSaveCredentials() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)

            try await prefs.save(controllerURL: "https://10.0.0.1", apiKey: "new-key", allowSelfSigned: true)

            #expect(prefs.isConfigured == true)
            #expect(prefs.allowSelfSignedCerts == true)
            #expect(prefs.cachedURL == "https://10.0.0.1")
            #expect(prefs.cachedAPIKey == "new-key")

            let encoded = try #require(try await keychain.read(.credentials))
            let saved = try JSONDecoder().decode(StoredCredentials.self, from: Data(encoded.utf8))
            #expect(saved == StoredCredentials(controllerURL: "https://10.0.0.1", apiKey: "new-key", allowSelfSigned: true))
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

    @Test(arguments: ["http://fixture.invalid", "https://user:pass@fixture.invalid", "https://fixture.invalid?key=value"])
    func testRestoredCredentialsMustPassURLValidation(url: String) async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.seedCredentials(url: url, key: "fixture-key")
            let client = await prefs.loadClient()
            await client?.invalidate()
            #expect(client == nil)
            #expect(!prefs.isConfigured)
        }
    }

    @Test func testLoadClientWithCredentialsWithoutPinning() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.seedCredentials(url: "https://192.168.1.1", key: "api-key-123")
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
            try await keychain.seedCredentials(url: "", key: "key")

            let client = await prefs.loadClient()
            #expect(client == nil)
            #expect(prefs.isConfigured == false)
        }
    }

    // MARK: - resetAll

    @Test func testLegacyPairRequiresExplicitReentry() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.save("https://old.invalid", for: .controllerURL)
            try await keychain.save("old-key", for: .apiKey)
            #expect(await prefs.loadClient() == nil)
            #expect(!prefs.isConfigured)
            #expect(prefs.cachedAPIKey == nil)
            #expect(prefs.credentialError == KeychainError.legacyCredentials.errorDescription)
            #expect(try await keychain.read(.apiKey) == "old-key") // Not destroyed before confirmation.
            try await prefs.save(controllerURL: "https://confirmed.invalid", apiKey: "confirmed-key", allowSelfSigned: false)
            let restored = PreferencesManager(defaults: defaults, keychain: keychain)
            await restored.checkConfiguration()
            #expect(restored.cachedURL == "https://confirmed.invalid")
            #expect(restored.cachedAPIKey == "confirmed-key")
        }
    }

    @Test(arguments: ["not json", #"{"version":2,"controllerURL":"https://fixture.invalid","apiKey":"key","allowSelfSigned":false}"#])
    func testInvalidRecordCannotRestoreOrFallBack(record: String) async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.save(record, for: .credentials)
            try await keychain.save("https://legacy.invalid", for: .controllerURL)
            try await keychain.save("legacy-key", for: .apiKey)
            #expect(await prefs.loadClient() == nil)
            #expect(prefs.cachedAPIKey == nil)
            #expect(prefs.credentialError != nil)
        }
    }

    @Test func testSingleRecordFailurePreservesPairAndTrustMode() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await prefs.save(controllerURL: "https://old.invalid", apiKey: "old-key", allowSelfSigned: false)
            await keychain.setSaveError(.saveFailed(status: -1), forKey: .credentials)
            await #expect(throws: KeychainError.self) {
                try await prefs.save(controllerURL: "https://new.invalid", apiKey: "new-key", allowSelfSigned: true)
            }
            let restored = PreferencesManager(defaults: defaults, keychain: keychain)
            await restored.checkConfiguration()
            #expect(restored.cachedURL == "https://old.invalid")
            #expect(restored.cachedAPIKey == "old-key")
            #expect(!restored.allowSelfSignedCerts)
        }
    }

    @Test func testReadErrorIsVisibleAndRetryable() async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            try await keychain.seedCredentials(url: "https://fixture.invalid", key: "fixture-key")
            await keychain.setReadError(.readFailed(status: -1))
            await prefs.checkConfiguration()
            #expect(!prefs.isConfigured)
            #expect(prefs.credentialError == KeychainError.readFailed(status: -1).errorDescription)
            await keychain.setReadError(nil)
            await prefs.checkConfiguration()
            #expect(prefs.isConfigured)
            #expect(prefs.credentialError == nil)
        }
    }

    @Test(arguments: [false, true])
    func testRestoredTrustModeComesFromTheCredentialRecord(allow: Bool) async throws {
        try await withDefaults { defaults in
            let keychain = FakeKeychain()
            try await keychain.seedCredentials(url: "https://fixture.invalid", key: "fixture-key", allowSelfSigned: allow)
            defaults.set(!allow, forKey: "com.unifbar.allowSelfSigned")
            let prefs = PreferencesManager(defaults: defaults, keychain: keychain)
            await prefs.checkConfiguration() // No client construction or native pin read.
            #expect(prefs.isConfigured)
            #expect(prefs.allowSelfSignedCerts == allow)
        }
    }

    @Test(arguments: ["credentials", "certificate pins", "login item"])
    func testFailedResetDoesNotRehydrateAndCanRetry(component: String) async throws {
        try await withDefaults { defaults in
            let keychain = FakeKeychain()
            let fail = OSAllocatedUnfairLock(initialState: true)
            var pins = 0
            var unregisters = 0
            let prefs = PreferencesManager(defaults: defaults, keychain: keychain, removePins: {
                pins += 1
                if fail.withLock({ $0 }) && component == "certificate pins" { throw KeychainError.deleteFailed(status: -1) }
            }, unregisterLoginItem: {
                unregisters += 1
                if fail.withLock({ $0 }) && component == "login item" { throw KeychainError.deleteFailed(status: -1) }
            })
            try await prefs.save(controllerURL: "https://fixture.invalid", apiKey: "fixture-key", allowSelfSigned: false)
            if component == "credentials" { await keychain.setDeleteError(.deleteFailed(status: -1)) }
            let cleanup = prefs.resetAll()
            #expect(prefs.isResetting)
            #expect(!prefs.isConfigured)
            await #expect(throws: PreferencesManager.ResetError.self) { try await cleanup.value }
            #expect(prefs.credentialError?.contains(component) == true)
            #expect(pins == 1 && unregisters == 1)
            let reads = await keychain.readCount
            let restarted = PreferencesManager(defaults: defaults, keychain: keychain)
            #expect(await restarted.loadClient() == nil)
            #expect(await keychain.readCount == reads)
            fail.withLock { $0 = false }
            await keychain.setDeleteError(nil)
            try await prefs.resetAll().value
            #expect(pins == 2 && unregisters == 2)
            #expect(!prefs.automaticConnectionAllowed)
            try await prefs.save(controllerURL: "https://new.invalid", apiKey: "new-key", allowSelfSigned: false)
            #expect(prefs.automaticConnectionAllowed)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [FakeKeychain.Operation.read, .save])
    func testResetDrainsCredentialWorkWithoutRevivingIt(operation: FakeKeychain.Operation) async throws {
        try await withDefaults { defaults in
            let keychain = FakeKeychain()
            try await keychain.seedCredentials(url: "https://old.invalid", key: "old-key")
            let prefs = PreferencesManager(defaults: defaults, keychain: keychain,
                                           removePins: {}, unregisterLoginItem: {})
            await keychain.pauseNext(operation)
            var pauses = keychain.pauses.stream.makeAsyncIterator()
            let pending = Task {
                if operation == .read { await prefs.checkConfiguration() } else { try await prefs.save(controllerURL: "https://new.invalid", apiKey: "new-key", allowSelfSigned: false) }
            }
            #expect(await pauses.next() == operation)
            let cleanup = prefs.resetAll()
            await #expect(throws: CancellationError.self) {
                try await prefs.save(controllerURL: "https://blocked.invalid", apiKey: "blocked-key", allowSelfSigned: false)
            }
            await keychain.resume()
            if operation == .save {
                await #expect(throws: CancellationError.self) { try await pending.value }
            } else { try await pending.value }
            try await cleanup.value
            #expect(prefs.cachedURL == nil && prefs.cachedAPIKey == nil)
            #expect(!prefs.isConfigured && !prefs.isResetting)
            #expect(try await keychain.read(.credentials) == nil)
            #expect(await PreferencesManager(defaults: defaults, keychain: keychain).loadClient() == nil)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func testCancelledOrSupersededQueuedSaveDoesNotCommit(cancel: Bool) async throws {
        try await withDefaults { defaults in
            let (prefs, keychain) = makePrefs(defaults: defaults)
            await keychain.pauseNext(.save)
            var pauses = keychain.pauses.stream.makeAsyncIterator()
            let first = Task { try await prefs.save(controllerURL: "https://first.invalid", apiKey: "first-key", allowSelfSigned: false) }
            #expect(await pauses.next() == .save)
            let started = AsyncStream<Void>.makeStream()
            var starts = started.stream.makeAsyncIterator()
            var current = true
            let queued = Task {
                started.continuation.yield(())
                try await prefs.save(controllerURL: "https://obsolete.invalid", apiKey: "obsolete-key", allowSelfSigned: true,
                                     isCurrent: { current })
            }
            await starts.next()
            if cancel { queued.cancel() } else { current = false }
            await keychain.resume()
            try await first.value
            await #expect(throws: CancellationError.self) { try await queued.value }
            started.continuation.finish()
            #expect(await keychain.saveCount == 1)
            #expect(prefs.cachedAPIKey == "first-key")
        }
    }

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

            try await prefs.resetAll().value

            #expect(prefs.isConfigured == false)
            #expect(prefs.allowSelfSignedCerts == false)
            #expect(prefs.pollIntervalSeconds == 30)
            #expect(prefs.cachedURL == nil)
            #expect(prefs.cachedAPIKey == nil)
            #expect(prefs.isSectionEnabled(.ddns) == false)

            let url = try await keychain.read(.controllerURL)
            let key = try await keychain.read(.apiKey)
            #expect(url == nil)
            #expect(key == nil)
        }
    }
}
