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

    private let siteIdKey = "com.unifbar.siteId"
    private let selfSignedKey = "com.unifbar.allowSelfSigned"
    private let sectionVisibilityKey = "com.unifbar.sectionVisibility"
    private let compactModeKey = "com.unifbar.compactMode"
    private let pollIntervalKey = "com.unifbar.pollInterval"

    var siteId: String? {
        get { defaults.string(forKey: siteIdKey) }
        set { defaults.set(newValue, forKey: siteIdKey) }
    }

    var controllerURL: URL? {
        cachedURL.flatMap { URL(string: $0) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        allowSelfSignedCerts = defaults.bool(forKey: selfSignedKey)
        compactMode = defaults.object(forKey: compactModeKey) as? Bool ?? false
        let savedInterval = defaults.object(forKey: pollIntervalKey) as? Int ?? 30
        pollIntervalSeconds = max(10, min(300, savedInterval))
        if let saved = defaults.dictionary(forKey: sectionVisibilityKey) as? [String: Bool] {
            sectionVisibility = saved
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
        if cachedURL == nil || cachedAPIKey == nil {
            cachedURL = await KeychainHelper.shared.read(.controllerURL)
            cachedAPIKey = await KeychainHelper.shared.read(.apiKey)
        }
        isConfigured = cachedURL != nil && cachedAPIKey != nil
    }

    func loadClient() async -> UniFiClient? {
        // Use cached values from checkConfiguration
        if cachedURL == nil || cachedAPIKey == nil {
            await checkConfiguration()
        }
        guard let urlString = cachedURL,
              let url = URL(string: urlString),
              let apiKey = cachedAPIKey
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


    func save(controllerURL: String, apiKey: String, allowSelfSigned: Bool) async throws {
        try await KeychainHelper.shared.save(controllerURL, for: .controllerURL)
        try await KeychainHelper.shared.save(apiKey, for: .apiKey)
        // Update cache
        cachedURL = controllerURL
        cachedAPIKey = apiKey
        allowSelfSignedCerts = allowSelfSigned
        defaults.set(allowSelfSigned, forKey: selfSignedKey)
        isConfigured = true
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

    func resetAll() async {
        // Clear certificate pin for the current controller host from Keychain
        if let urlString = cachedURL, let url = URL(string: urlString), let host = url.host() {
            PinnedCertDelegate.deletePinFromKeychain(host: host)
            // Also clean up legacy UserDefaults pin if present from older versions
            defaults.removeObject(forKey: "com.unifbar.cert-pin.\(host)")
        }
        // Unregister login item so it doesn't persist after reset
        try? await SMAppService.mainApp.unregister()
        await KeychainHelper.shared.delete(.controllerURL)
        await KeychainHelper.shared.delete(.apiKey)
        cachedURL = nil
        cachedAPIKey = nil
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
}
