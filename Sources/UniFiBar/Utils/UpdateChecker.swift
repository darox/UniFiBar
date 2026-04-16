import Foundation

@MainActor
@Observable
final class UpdateChecker {
    var updateAvailable = false
    var latestVersion: String?
    var releaseURL: URL?
    var releaseNotes: String?

    private let repoOwner = "darox"
    private let repoName = "UniFiBar"
    private let checkInterval: TimeInterval = 86_400 // 24 hours
    private let lastCheckKey = "com.unifbar.lastUpdateCheck"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func checkNow() {
        Task {
            await performCheck()
        }
    }

    func schedulePeriodicCheck() {
        let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < checkInterval {
            return
        }
        checkNow()
    }

    private func performCheck() async {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let tag = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName

            if Self.isNewer(current: currentVersion, remote: tag) {
                updateAvailable = true
                latestVersion = tag
                releaseURL = URL(string: release.htmlURL)
                releaseNotes = release.body
            }
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        } catch {
            // Silently fail — update checks must never disrupt the user
        }
    }

    /// Simple semver comparison: "1.2.3" vs "1.3.0".
    private static func isNewer(current: String, remote: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let count = max(currentParts.count, remoteParts.count)
        for i in 0..<count {
            let c = i < currentParts.count ? currentParts[i] : 0
            let r = i < remoteParts.count ? remoteParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}

private struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let htmlURL: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
    }
}