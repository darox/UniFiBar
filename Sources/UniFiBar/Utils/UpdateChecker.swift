import Foundation

@MainActor
@Observable
final class UpdateChecker {
    var updateAvailable = false
    var latestVersion: String?
    var releaseURL: URL?
    private(set) var isDebugMode = false

    private let repoOwner = "darox"
    private let repoName = "UniFiBar"
    private let checkInterval: TimeInterval = 86_400 // 24 hours
    private let lastCheckKey = "com.unifbar.lastUpdateCheck"
    private let checksEnabled: Bool
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private let fetch: @MainActor (URLRequest) async throws -> (Data, URLResponse)
    private var checkTask: Task<Void, Never>?
    private var lastAttempt: Date?

    init(
        checksEnabled: Bool = true,
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { Date() },
        fetch: @escaping @MainActor (URLRequest) async throws -> (Data, URLResponse) = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForResource = 30
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(for: $0, delegate: SameOriginRedirectDelegate())
            defer { bytes.task.cancel() }
            return (try await UniFiClient.boundedResponseData(bytes, response: response, limit: 1_024 * 1_024), response)
        }
    ) {
        self.checksEnabled = checksEnabled
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
    }

#if DEBUG
    /// Debug: toggle a fake update indicator for UI testing. Tap version 5 times in Preferences to trigger.
    func toggleDebugUpdate() {
        if isDebugMode {
            // Already in debug mode — turn it off
            isDebugMode = false
            updateAvailable = false
            latestVersion = nil
            releaseURL = nil
        } else {
            isDebugMode = true
            updateAvailable = true
            latestVersion = "99.99.99"
            releaseURL = URL(string: "https://github.com/darox/UniFiBar/releases")
        }
    }
#endif

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    @discardableResult
    func checkNow() -> Task<Void, Never>? {
        guard checksEnabled else { return nil }
        if let checkTask { return checkTask }
        lastAttempt = now()
        checkTask = Task {
            defer { checkTask = nil }
            await performCheck()
        }
        return checkTask
    }

    @discardableResult
    func schedulePeriodicCheck() -> Task<Void, Never>? {
        // Fixture mode must not even read the host's update-check timestamp.
        guard checksEnabled else { return nil }
        if let checkTask { return checkTask }
        // Retry failed/cancelled checks after five minutes, not on every controller poll.
        if let lastAttempt, (0..<300).contains(now().timeIntervalSince(lastAttempt)) { return nil }
        let lastCheck = defaults.object(forKey: lastCheckKey) as? Date
        if let lastCheck, (0..<checkInterval).contains(now().timeIntervalSince(lastCheck)) {
            return nil
        }
        return checkNow()
    }

    private func performCheck() async {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        do {
            try Task.checkCancellation()
            let (data, response) = try await fetch(request)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let trustedURL = validatedReleaseURL(release.htmlURL) else { return }
            let tag = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName

            if Self.isNewer(current: currentVersion, remote: tag) {
                updateAvailable = true
                latestVersion = tag
                releaseURL = trustedURL
            }
            defaults.set(now(), forKey: lastCheckKey)
        } catch {
            // Silently fail — update checks must never disrupt the user
        }
    }

    private func validatedReleaseURL(_ value: String) -> URL? {
        guard let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              parts.host?.lowercased() == "github.com", parts.port == nil || parts.port == 443,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !parts.path.contains("\\")
        else { return nil }
        let path = parts.path.split(separator: "/").map(String.init)
        guard Array(path.prefix(3)) == [repoOwner, repoName, "releases"],
              !path.contains("."), !path.contains(".."),
              path.count == 3 || (path.count >= 5 && path[3] == "tag")
        else { return nil }
        return parts.url
    }

    /// Semver comparison: "1.2.3" vs "1.3.0". Strips pre-release suffixes
    /// like "-beta1" from each segment before parsing.
    static func isNewer(current: String, remote: String) -> Bool {
        let currentParts = current.split(separator: ".").map { parseVersionSegment(String($0)) }
        let remoteParts = remote.split(separator: ".").map { parseVersionSegment(String($0)) }
        let count = max(currentParts.count, remoteParts.count)
        for i in 0..<count {
            let c = i < currentParts.count ? currentParts[i] : 0
            let r = i < remoteParts.count ? remoteParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }

    /// Parse a version segment, stripping pre-release suffixes (e.g. "0-beta1" → 0).
    static func parseVersionSegment(_ segment: String) -> Int {
        // Strip anything after a hyphen (pre-release suffix like "-beta1")
        let numericPart = segment.split(separator: "-").first.map(String.init) ?? segment
        return Int(numericPart) ?? 0
    }
}

private struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
