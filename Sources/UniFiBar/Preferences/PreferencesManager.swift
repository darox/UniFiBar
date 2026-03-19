import Foundation

// MARK: - Section Visibility

enum MenuSection: String, CaseIterable, Sendable {
    case internet = "internet"
    case vpn = "vpn"
    case wifi = "wifi"
    case network = "network"
    case sessionHistory = "sessionHistory"
    case alerts = "alerts"
    case security = "security"
    case traffic = "traffic"
    case events = "events"
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
        case .alerts: return "Alerts"
        case .security: return "Security (IPS)"
        case .traffic: return "Traffic (DPI)"
        case .events: return "Recent Events"
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
        case .alerts: return "bell.badge"
        case .security: return "shield.lefthalf.filled"
        case .traffic: return "chart.pie"
        case .events: return "list.bullet"
        case .ddns: return "link"
        case .portForwards: return "arrow.right.arrow.left"
        case .nearbyAPs: return "antenna.radiowaves.left.and.right"
        }
    }

    /// Whether this section is shown by default
    var defaultEnabled: Bool {
        switch self {
        case .internet, .vpn, .wifi, .network, .sessionHistory, .alerts:
            return true
        case .security, .traffic, .events, .ddns, .portForwards, .nearbyAPs:
            return false
        }
    }
}

@MainActor
@Observable
final class PreferencesManager {
    var isConfigured: Bool = false
    var allowSelfSignedCerts: Bool = false

    // Section visibility
    private var sectionVisibility: [String: Bool] = [:]

    // Cached credentials — read from Keychain once, then reuse
    private var cachedURL: String?
    private var cachedAPIKey: String?

    private let siteIdKey = "com.unifbar.siteId"
    private let selfSignedKey = "com.unifbar.allowSelfSigned"
    private let sectionVisibilityKey = "com.unifbar.sectionVisibility"

    var siteId: String? {
        get { UserDefaults.standard.string(forKey: siteIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: siteIdKey) }
    }

    init() {
        allowSelfSignedCerts = UserDefaults.standard.bool(forKey: selfSignedKey)
        if let saved = UserDefaults.standard.dictionary(forKey: sectionVisibilityKey) as? [String: Bool] {
            sectionVisibility = saved
        }
    }

    func isSectionEnabled(_ section: MenuSection) -> Bool {
        sectionVisibility[section.rawValue] ?? section.defaultEnabled
    }

    func setSectionEnabled(_ section: MenuSection, enabled: Bool) {
        sectionVisibility[section.rawValue] = enabled
        UserDefaults.standard.set(sectionVisibility, forKey: sectionVisibilityKey)
    }

    /// Returns true if any optional monitoring section is enabled (requiring extra API calls)
    var hasMonitoringSectionsEnabled: Bool {
        let monitoringSections: [MenuSection] = [.alerts, .security, .traffic, .events, .ddns, .portForwards, .nearbyAPs]
        return monitoringSections.contains { isSectionEnabled($0) }
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
        UserDefaults.standard.set(allowSelfSigned, forKey: selfSignedKey)
        isConfigured = true
    }

    func resetAll() async {
        await KeychainHelper.shared.delete(.controllerURL)
        await KeychainHelper.shared.delete(.apiKey)
        cachedURL = nil
        cachedAPIKey = nil
        UserDefaults.standard.removeObject(forKey: siteIdKey)
        UserDefaults.standard.removeObject(forKey: selfSignedKey)
        allowSelfSignedCerts = false
        isConfigured = false
    }
}
