import Foundation
import Security

// Only namespaces change. All original backend/accessibility/match attributes survive.
// Even removeAll/cleanup is expanded into exact, predeclared accounts before native calls.
struct NativeScope: Sendable {
    let id: UUID
    let pins: Bool
    var originalService: String { pins ? "com.unifbar.cert-pins" : "com.unifbar.app" }
    var service: String { "com.unifibar.native-audit.\(id.uuidString).\(pins ? "pins" : "credentials")" }
    var accounts: [String] {
        pins ? ["fixture.invalid", "race.invalid", "sentinel.invalid"].map { "com.unifbar.cert-pin.\($0)" }
             : KeychainHelper.Key.allCases.map(\.rawValue)
    }

    func scoped(_ input: [String: Any]) -> [String: Any]? {
        guard input[kSecClass as String] as? String == kSecClassGenericPassword as String,
              input[kSecAttrService as String] as? String == originalService,
              let account = input[kSecAttrAccount as String] as? String, accounts.contains(account)
        else { return nil }
        var query = input
        query[kSecAttrService as String] = service
        query[kSecAttrAccount as String] = "\(id.uuidString).\(account)"
        return query
    }
    func read(_ input: [String: Any]) -> (OSStatus, Data?) {
        guard let query = scoped(input) else { return (errSecParam, nil) }
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        return (status, value as? Data)
    }
    func add(_ input: [String: Any]) -> OSStatus {
        guard let query = scoped(input) else { return errSecParam }
        return SecItemAdd(query as CFDictionary, nil)
    }
    func update(_ input: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        guard let query = scoped(input), Set(attributes.keys) == [kSecValueData as String] else { return errSecParam }
        return SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
    func delete(_ input: [String: Any]) -> OSStatus {
        if pins, input[kSecAttrAccount as String] == nil {
            // Preserve the production default backend; never issue an unqualified native delete.
            var result = errSecSuccess
            for account in accounts {
                var query = input
                query[kSecAttrAccount as String] = account
                let status = delete(query)
                if status != errSecSuccess && status != errSecItemNotFound { result = status }
            }
            return result
        }
        guard let query = scoped(input) else { return errSecParam }
        return SecItemDelete(query as CFDictionary)
    }
    var credentials: KeychainHelper { .init(operations: .init(read: read, update: update, add: add, delete: delete)) }
    var pinStore: CertificatePinStore { .init(read: read, add: add, delete: delete) }

    func cleanup() -> Bool {
        var complete = true
        for account in accounts {
            for backend: Bool? in pins ? [nil] : [true, false] {
                var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: originalService, kSecAttrAccount as String: account]
                if let backend { query[kSecUseDataProtectionKeychain as String] = backend }
                let status = delete(query)
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                let (absent, _) = read(query)
                print("CLEANUP account=\(account) backend=\(backend.map(String.init) ?? "default") delete=\(status) read=\(absent)")
                if (status != errSecSuccess && status != errSecItemNotFound) || absent != errSecItemNotFound { complete = false }
            }
        }
        return complete
    }
}

@MainActor
func storageCheck(_ mode: String, id: UUID, argument: String?) async throws -> Int32 {
    var interaction = DarwinBoolean(true)
    try require(SecKeychainGetUserInteractionAllowed(&interaction) == errSecSuccess, "interaction read")
    try require(SecKeychainSetUserInteractionAllowed(false) == errSecSuccess, "disable interaction")
    defer { print("INTERACTION_RESTORE=\(SecKeychainSetUserInteractionAllowed(interaction.boolValue))") }
    let scope = NativeScope(id: id, pins: false)
    let pins = NativeScope(id: id, pins: true)
    let helper = scope.credentials
    let suite = "com.unifibar.native-audit.\(id.uuidString).defaults"
    let defaults = UserDefaults(suiteName: suite)!
    let prefs = PreferencesManager(defaults: defaults, keychain: helper,
        removePins: { try pins.pinStore.removeAll() }, unregisterLoginItem: {})
    let url = "https://fixture.invalid"
    switch mode {
    case "storage-create":
        try require(try await helper.read(.credentials) == nil, "namespace must start empty")
        try require(defaults.persistentDomain(forName: suite) == nil, "defaults must start empty")
        try await helper.save(url, for: .controllerURL)
        try await helper.save("synthetic-legacy", for: .apiKey)
        try await prefs.save(controllerURL: url, apiKey: "synthetic-first", allowSelfSigned: true)
        let legacyURL = try await helper.read(.controllerURL)
        let legacyKey = try await helper.read(.apiKey)
        try require(legacyURL == nil && legacyKey == nil, "legacy cleanup")
        try pins.pinStore.saveIfAbsent(Data(repeating: 1, count: 32), host: "fixture.invalid")
        try pins.pinStore.saveIfAbsent(Data(repeating: 3, count: 32), host: "sentinel.invalid")
    case "storage-restart":
        await prefs.checkConfiguration()
        try require(prefs.isConfigured && prefs.cachedURL == url && prefs.cachedAPIKey == "synthetic-first" && prefs.allowSelfSignedCerts, "whole record after process restart")
        try await prefs.save(controllerURL: "https://updated.invalid", apiKey: "synthetic-second", allowSelfSigned: false)
        let stored = try await helper.read(.credentials)
        let fault = KeychainHelper(operations: .init(read: scope.read, update: { q, _ in
            scope.scoped(q) == nil ? errSecParam : errSecInteractionNotAllowed
        }, add: scope.add, delete: scope.delete))
        do { try await fault.save("synthetic-failed-update", for: .credentials); throw AuditFailure("hidden update error") } catch KeychainError.saveFailed(let status) { try require(status == errSecInteractionNotAllowed, "injected status") }
        try require(try await helper.read(.credentials) == stored, "injected write fault preserves native record")
        try require(try pins.pinStore.load(host: "fixture.invalid") == Data(repeating: 1, count: 32), "pin across process restart")
        do { try pins.pinStore.saveIfAbsent(Data(repeating: 2, count: 32), host: "fixture.invalid"); throw AuditFailure("conflicting pin accepted") } catch CertificatePinStore.Failure.conflictingPin {}
        try pins.pinStore.remove(host: "fixture.invalid")
        try require(try pins.pinStore.load(host: "sentinel.invalid") == Data(repeating: 3, count: 32), "per-account deletion scope")
    case "storage-pin-race":
        let candidate = UInt8(argument ?? "")!
        do { try pins.pinStore.saveIfAbsent(Data(repeating: candidate, count: 32), host: "race.invalid"); print("WINNER=\(candidate)") } catch CertificatePinStore.Failure.conflictingPin { print("CONFLICT=\(candidate)") }
    case "storage-race-read":
        let pin = try pins.pinStore.load(host: "race.invalid")
        try require(pin == Data(repeating: 4, count: 32) || pin == Data(repeating: 5, count: 32), "one complete cross-process winner")
    case "storage-credential-writer":
        guard let candidate = argument, ["6", "7"].contains(candidate) else { throw AuditFailure("candidate") }
        do {
            try await prefs.save(controllerURL: "https://writer-\(candidate).invalid", apiKey: "synthetic-\(candidate)", allowSelfSigned: candidate == "6")
            print("WRITE_VERIFIED=\(candidate)")
        } catch KeychainError.verificationFailed {
            print("CONCURRENT_WRITE_CHANGED_READBACK=\(candidate); not a rollback claim")
        } catch KeychainError.saveFailed(let status) where status == errSecDuplicateItem {
            print("CONCURRENT_ADD_REJECTED=\(candidate); native -25299 remains a visible save failure")
        }
    case "storage-credential-read":
        await prefs.checkConfiguration()
        let candidate = prefs.cachedAPIKey == "synthetic-6" ? "6" : "7"
        try require(prefs.isConfigured && prefs.cachedURL == "https://writer-\(candidate).invalid"
            && prefs.cachedAPIKey == "synthetic-\(candidate)" && prefs.allowSelfSignedCerts == (candidate == "6"),
            "cross-process credential writes retain one coherent URL/key/trust record")
    case "storage-intent":
        // Deliberately exit this fixture process before cleanup starts. Not power loss.
        let gate = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        _ = prefs.resetAll(after: gate)
        try require(!prefs.automaticConnectionAllowed && defaults.synchronize(), "reset intent flushed before fixture exits")
        print("SIMULATED interruption: process exits before pending cleanup; no host event")
    case "storage-intent-read":
        await prefs.checkConfiguration()
        try require(!prefs.automaticConnectionAllowed && !prefs.isConfigured && prefs.cachedAPIKey == nil, "reset intent blocks reconnect in next process")
        try require(try await helper.read(.credentials) != nil, "leftover synthetic record exists behind reset gate")
        try await prefs.save(controllerURL: url, apiKey: "synthetic-new", allowSelfSigned: false)
        try require(prefs.automaticConnectionAllowed, "explicit save clears intent")
        do { try await prefs.resetAll().value } catch let error as PreferencesManager.ResetError {
            try require(error.requiresEntitledBuild && error.components == ["credentials"], "only protected credentials unavailable")
            print("BLOCKED: protected reset cleanup -34018, source correctly reports incomplete")
        }
        try require(try await helper.read(.credentials) == nil && !prefs.automaticConnectionAllowed, "accessible reset deletes record and retains admission gate")
    case "storage-cleanup":
        let credentialCleanup = scope.cleanup()
        let pinCleanup = pins.cleanup()
        defaults.removePersistentDomain(forName: suite)
        try require(defaults.synchronize() && defaults.persistentDomain(forName: suite)?.isEmpty != false, "defaults cleanup")
        print("DEFAULTS_CLEANUP: scoped domain has no values (Foundation may retain an empty domain)")
        return credentialCleanup && pinCleanup ? 0 : 2
    default: throw AuditFailure("unknown storage mode")
    }
    print("PASS: \(mode)")
    return 0
}
