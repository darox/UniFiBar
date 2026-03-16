import Foundation
import Security

/// Stores credentials securely in the macOS Keychain.
/// Tries the data protection keychain first (no password prompts, requires proper signing).
/// Falls back to the legacy keychain for ad-hoc signed development builds.
actor KeychainHelper {
    static let shared = KeychainHelper()

    enum Key: String, Sendable {
        case controllerURL = "com.unifbar.controller-url"
        case apiKey = "com.unifbar.api-key"
    }

    private let service = "com.unifbar.app"
    private var useDataProtection: Bool

    private init() {
        // Probe whether data protection keychain is available (requires proper signing).
        // Clean up any stale probe from a previous crash first.
        let probeQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unifbar.probe",
            kSecAttrAccount as String: "entitlement-check",
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(probeQuery as CFDictionary)

        var addQuery = probeQuery
        addQuery[kSecValueData as String] = Data("probe".utf8)

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            useDataProtection = false
        } else {
            useDataProtection = (status == errSecSuccess)
            SecItemDelete(probeQuery as CFDictionary)
        }
    }

    private func query(for key: Key) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        if useDataProtection {
            q[kSecUseDataProtectionKeychain as String] = true
        }
        return q
    }

    func save(_ value: String, for key: Key) throws {
        let data = Data(value.utf8)

        // Try to update existing item first
        let q = query(for: key)
        let update: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }

        // Item doesn't exist — add it
        var addQuery = q
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.saveFailed(status: addStatus)
        }
    }

    func read(_ key: Key) -> String? {
        var q = query(for: key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string
    }

    func delete(_ key: Key) {
        SecItemDelete(query(for: key) as CFDictionary)
    }
}

enum KeychainError: Error, Sendable {
    case saveFailed(status: OSStatus)
}
