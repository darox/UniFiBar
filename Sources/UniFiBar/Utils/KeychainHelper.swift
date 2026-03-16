import Foundation

/// Stores credentials in Application Support with restricted file permissions.
/// Avoids macOS Keychain prompts that reappear on every rebuild during development.
actor KeychainHelper {
    static let shared = KeychainHelper()

    enum Key: String, Sendable {
        case controllerURL = "controller-url"
        case apiKey = "api-key"
    }

    private let storageDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("UniFiBar", isDirectory: true)
    }

    private func ensureDirectory() throws {
        let path = storageDir.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    private func filePath(for key: Key) -> String {
        storageDir.appendingPathComponent(key.rawValue).path(percentEncoded: false)
    }

    func save(_ value: String, for key: Key) throws {
        try ensureDirectory()
        let path = filePath(for: key)
        let data = Data(value.utf8)
        FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    func read(_ key: Key) -> String? {
        let path = filePath(for: key)
        guard let data = FileManager.default.contents(atPath: path),
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func delete(_ key: Key) {
        let path = filePath(for: key)
        try? FileManager.default.removeItem(atPath: path)
    }
}
