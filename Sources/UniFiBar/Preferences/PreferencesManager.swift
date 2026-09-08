import Foundation
import ServiceManagement

// MARK: - Section Visibility

enum MenuSection: String, CaseIterable, Sendable {
    case internet = "internet"
    case vpn = "vpn"
    case wifi = "wifi"
    case network = "network"
    case sessionHistory = "sessionHistory"
    case ddns = "ddns"
    case portForwards = "portForwards"
    case nearbyAPs = "nearbyAPs"

    var displayName: String {
        switch self {
        case .internet: return "Internet & Gateway"
        case .vpn: return "VPN Tunnels"
        case .wifi: return "WiFi & Connection"
        case .network: return "Network Overview"
        case .sessionHistory: return "Session History"
        case .ddns: return "Dynamic DNS"
        case .portForwards: return "Port Forwards"
        case .nearbyAPs: return "Nearby APs"
        }
    }

    var icon: String {
        switch self {
        case .internet: return "globe"
        case .vpn: return "lock.shield"
        case .wifi: return "wifi"
        case .network: return "network"
        case .sessionHistory: return "clock"
        case .ddns: return "link"
        case .portForwards: return "arrow.right.arrow.left"
        case .nearbyAPs: return "antenna.radiowaves.left.and.right"
        }
    }

    /// Whether this section is shown by default
    var defaultEnabled: Bool {
        switch self {
        case .internet, .vpn, .wifi, .network, .sessionHistory:
            return true
        case .ddns, .portForwards, .nearbyAPs:
            return false
        }
    }
}

/// URL, key and trust mode must be restored from the same committed item.
struct StoredCredentials: Codable, Equatable, Sendable {
    var version = 1
    let controllerURL: String
    let apiKey: String
    let allowSelfSigned: Bool

    func validate() throws {
        guard version == 1,
              case .success = URLValidator.normalizeAndValidate(controllerURL),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw KeychainError.invalidRecord }
    }
}

@MainActor
@Observable
final class PreferencesManager {
    private let defaults: UserDefaults
    var isConfigured: Bool = false
    var allowSelfSignedCerts: Bool = false
    var compactMode: Bool = false
    var pollIntervalSeconds: Int = 30

    // Section visibility
    private var sectionVisibility: [String: Bool] = [:]

    // Cached credentials — read from Keychain once, then reuse
    private(set) var cachedURL: String?
    private(set) var cachedAPIKey: String?
    private(set) var credentialError: String?
    private(set) var isResetting = false
    private var credentialGeneration = 0
    private var credentialBusy = false
    private var credentialWaiters: [CheckedContinuation<Void, Never>] = []
    private var resetTask: Task<Void, Error>?
    private let removePins: @MainActor () throws -> Void
    private let unregisterLoginItem: @MainActor () async throws -> Void

    private let siteIdKey = "com.unifbar.siteId"
    private let selfSignedKey = "com.unifbar.allowSelfSigned"
    private let sectionVisibilityKey = "com.unifbar.sectionVisibility"
    private let compactModeKey = "com.unifbar.compactMode"
    private let pollIntervalKey = "com.unifbar.pollInterval"
    private let resetPendingKey = "com.unifbar.resetPending"

    var automaticConnectionAllowed: Bool { !isResetting && !defaults.bool(forKey: resetPendingKey) }

    var siteId: String? {
        get { defaults.string(forKey: siteIdKey) }
        set { defaults.set(newValue, forKey: siteIdKey) }
    }

    var controllerURL: URL? {
        cachedURL.flatMap { URL(string: $0) }
    }

    private let keychain: KeychainHelperProtocol

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainHelperProtocol = KeychainHelper.shared,
        removePins: @escaping @MainActor () throws -> Void = { try CertificatePinStore.keychain.removeAll() },
        unregisterLoginItem: @escaping @MainActor () async throws -> Void = {
            if SMAppService.mainApp.status != .notRegistered { try await SMAppService.mainApp.unregister() }
        }
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.removePins = removePins
        self.unregisterLoginItem = unregisterLoginItem
        allowSelfSignedCerts = defaults.bool(forKey: selfSignedKey)
        compactMode = defaults.object(forKey: compactModeKey) as? Bool ?? false
        let savedInterval = defaults.object(forKey: pollIntervalKey) as? Int ?? 30
        pollIntervalSeconds = max(10, min(300, savedInterval))
        if let saved = defaults.dictionary(forKey: sectionVisibilityKey) as? [String: Bool] {
            sectionVisibility = saved
        }
        if defaults.bool(forKey: resetPendingKey) {
            credentialError = "Automatic reconnection is disabled after reset. Retry incomplete cleanup or enter new credentials."
        }
    }

    func isSectionEnabled(_ section: MenuSection) -> Bool {
        sectionVisibility[section.rawValue] ?? section.defaultEnabled
    }

    func setSectionEnabled(_ section: MenuSection, enabled: Bool) {
        sectionVisibility[section.rawValue] = enabled
        defaults.set(sectionVisibility, forKey: sectionVisibilityKey)
    }

    /// Reads Keychain once and caches. Subsequent calls use cache.
    func checkConfiguration() async {
        guard automaticConnectionAllowed else { return }
        let generation = credentialGeneration
        await acquireCredentials()
        defer { releaseCredentials() }
        guard automaticConnectionAllowed, generation == credentialGeneration, !Task.isCancelled else { return }
        do {
            if cachedURL == nil || cachedAPIKey == nil {
                let stored = try await keychain.read(.credentials)
                guard automaticConnectionAllowed, generation == credentialGeneration, !Task.isCancelled else { return }
                guard let stored else {
                    // Old independent items may already be mismatched. Never send them automatically.
                    let oldURL = try await keychain.read(.controllerURL)
                    let oldKey = try await keychain.read(.apiKey)
                    guard automaticConnectionAllowed, generation == credentialGeneration, !Task.isCancelled else { return }
                    if oldURL != nil || oldKey != nil { throw KeychainError.legacyCredentials }
                    isConfigured = false
                    credentialError = nil
                    return
                }
                let record = try JSONDecoder().decode(StoredCredentials.self, from: Data(stored.utf8))
                try record.validate()
                cache(record)
            }
            credentialError = nil
        } catch {
            guard automaticConnectionAllowed, generation == credentialGeneration else { return }
            cachedURL = nil
            cachedAPIKey = nil
            credentialError = (error as? KeychainError)?.errorDescription ?? KeychainError.invalidRecord.errorDescription
        }
        isConfigured = cachedURL != nil && cachedAPIKey != nil
    }

    func loadClient() async -> UniFiClientProtocol? {
        guard automaticConnectionAllowed else { return nil }
        if cachedURL == nil || cachedAPIKey == nil {
            await checkConfiguration()
        }
        guard automaticConnectionAllowed, !Task.isCancelled, let urlString = cachedURL,
              case .success(let url) = URLValidator.normalizeAndValidate(urlString),
              let apiKey = cachedAPIKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            isConfigured = false
            return nil
        }
        isConfigured = true
        return UniFiClient(
            baseURL: url,
            apiKey: apiKey,
            allowSelfSigned: allowSelfSignedCerts
        )
    }


    func save(controllerURL: String, apiKey: String, allowSelfSigned: Bool,
              isCurrent: @MainActor () -> Bool = { true }) async throws {
        guard !isResetting else { throw CancellationError() }
        let generation = credentialGeneration
        let record = StoredCredentials(controllerURL: controllerURL, apiKey: apiKey, allowSelfSigned: allowSelfSigned)
        try record.validate()
        let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        await acquireCredentials()
        defer { releaseCredentials() }
        try Task.checkCancellation()
        guard !isResetting, generation == credentialGeneration, isCurrent() else { throw CancellationError() }
        // Cancellation after this point is not rollback: complete the single-item commit.
        try await keychain.save(encoded, for: .credentials)
        guard !isResetting, generation == credentialGeneration else { throw CancellationError() }
        cache(record)
        defaults.removeObject(forKey: resetPendingKey)
        credentialError = nil
        isConfigured = true
    }

    private func cache(_ record: StoredCredentials) {
        cachedURL = record.controllerURL
        cachedAPIKey = record.apiKey
        allowSelfSignedCerts = record.allowSelfSigned
        // The record is authoritative; keep the old preference only for UI compatibility.
        defaults.set(record.allowSelfSigned, forKey: selfSignedKey)
    }

    private func acquireCredentials() async {
        if credentialBusy {
            await withCheckedContinuation { credentialWaiters.append($0) }
        } else { credentialBusy = true }
    }

    private func releaseCredentials() {
        // ponytail: tiny FIFO per preferences instance; not a cross-process transaction lock.
        if credentialWaiters.isEmpty { credentialBusy = false }
        else { credentialWaiters.removeFirst().resume() }
    }

    func setPollInterval(_ seconds: Int) {
        let clamped = max(10, min(300, seconds))
        pollIntervalSeconds = clamped
        defaults.set(clamped, forKey: pollIntervalKey)
    }

    func setCompactMode(_ value: Bool) {
        compactMode = value
        defaults.set(value, forKey: compactModeKey)
    }

    /// Admission closes synchronously; cleanup survives dismissal/cancellation of its caller.
    func resetAll(after invalidation: Task<Void, Never>? = nil) -> Task<Void, Error> {
        if let resetTask { return resetTask }
        isResetting = true
        credentialGeneration += 1
        defaults.set(true, forKey: resetPendingKey)
        cachedURL = nil
        cachedAPIKey = nil
        isConfigured = false
        let task = Task {
            await invalidation?.value
            await acquireCredentials() // Drain any commit before deleting it.
            defer {
                releaseCredentials()
                isResetting = false
                resetTask = nil
            }
            var failures: [String] = []
            var requiresEntitledBuild = false
            for key in KeychainHelper.Key.allCases {
                do { try await keychain.delete(key) }
                catch {
                    if !failures.contains("credentials") { failures.append("credentials") }
                    requiresEntitledBuild = requiresEntitledBuild || (error as? KeychainError)?.requiresEntitledBuild == true
                }
            }
            do { try removePins() } catch { failures.append("certificate pins") }
            do { try await unregisterLoginItem() } catch { failures.append("login item") }
            clearSettings()
            if !failures.isEmpty {
                let error = ResetError(components: failures, requiresEntitledBuild: requiresEntitledBuild)
                credentialError = error.errorDescription
                throw error
            }
            credentialError = nil
            // Keep reset intent across restart; only an explicit successful save clears it.
        }
        resetTask = task
        return task
    }

    private func clearSettings() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("com.unifbar.cert-pin.") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: siteIdKey)
        defaults.removeObject(forKey: selfSignedKey)
        defaults.removeObject(forKey: sectionVisibilityKey)
        defaults.removeObject(forKey: compactModeKey)
        defaults.removeObject(forKey: pollIntervalKey)
        sectionVisibility = [:]
        pollIntervalSeconds = 30
        allowSelfSignedCerts = false
        compactMode = false
        isConfigured = false
    }

    struct ResetError: LocalizedError {
        let components: [String]
        var requiresEntitledBuild = false
        var errorDescription: String? {
            let guidance = requiresEntitledBuild ? KeychainError.entitlementGuidance : "Retry reset to finish cleanup."
            return "Reset incomplete: \(components.joined(separator: ", ")). Automatic reconnection is disabled. \(guidance)"
        }
    }
}
