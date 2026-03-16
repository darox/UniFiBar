import Foundation

@MainActor
@Observable
final class PreferencesManager {
    var isConfigured: Bool = false
    var allowSelfSignedCerts: Bool = false

    // Cached credentials — read from Keychain once, then reuse
    private var cachedURL: String?
    private var cachedAPIKey: String?

    private let siteIdKey = "com.unifbar.siteId"
    private let selfSignedKey = "com.unifbar.allowSelfSigned"

    var siteId: String? {
        get { UserDefaults.standard.string(forKey: siteIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: siteIdKey) }
    }

    init() {
        allowSelfSignedCerts = UserDefaults.standard.bool(forKey: selfSignedKey)
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
