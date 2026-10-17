import Foundation
import Security

protocol KeychainHelperProtocol: Sendable {
    func read(_ key: KeychainHelper.Key) async throws -> String?
    func save(_ value: String, for key: KeychainHelper.Key) async throws
    func delete(_ key: KeychainHelper.Key) async throws
}

/// One credential item per backend. Native calls never suspend within a store operation.
actor KeychainHelper: KeychainHelperProtocol {
    static let shared = KeychainHelper(operations: .native)

    enum Key: String, Sendable, CaseIterable {
        case credentials = "com.unifbar.credentials.v1"
        case controllerURL = "com.unifbar.controller-url"
        case apiKey = "com.unifbar.api-key"
    }

    /// Same injection boundary as CertificatePinStore; tests never call Security.framework.
    struct Operations: Sendable {
        let read: @Sendable ([String: Any]) -> (OSStatus, Data?)
        let update: @Sendable ([String: Any], [String: Any]) -> OSStatus
        let add: @Sendable ([String: Any]) -> OSStatus
        let delete: @Sendable ([String: Any]) -> OSStatus

        static let native = Self(read: { query in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        }, update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
        add: { SecItemAdd($0 as CFDictionary, nil) },
        delete: { SecItemDelete($0 as CFDictionary) })
    }

    private let operations: Operations

    init(operations: Operations) { self.operations = operations }

    private func query(for key: Key, protected: Bool) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.unifbar.app",
         kSecAttrAccount as String: key.rawValue,
         kSecUseDataProtectionKeychain as String: protected]
    }

    /// Never treat locked/unavailable/malformed storage as an empty store or switch backend.
    private func locations(for key: Key) throws -> [(protected: Bool, value: String?)] {
        var locations: [(protected: Bool, value: String?)] = []
        for protected in [true, false] {
            var q = query(for: key, protected: protected)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            let (status, data) = operations.read(q)
            if protected && status == errSecMissingEntitlement { continue }
            if status == errSecItemNotFound {
                locations.append((protected, nil))
                continue
            }
            guard status == errSecSuccess else { throw KeychainError.readFailed(status: status) }
            guard let data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidRecord
            }
            locations.append((protected, value))
        }
        return locations
    }

    func read(_ key: Key) throws -> String? {
        let values = try locations(for: key).compactMap(\.value)
        guard Set(values).count <= 1 else { throw KeychainError.conflictingRecords }
        return values.first
    }

    func save(_ value: String, for key: Key) throws {
        var locations = try locations(for: key)
        let data = Data(value.utf8)
        // A successful/missing read does not establish permission to write that backend.
        while let destination = locations.first {
            let q = query(for: key, protected: destination.protected)
            let status = write(data, query: q)
            if destination.protected && status == errSecMissingEntitlement {
                locations.removeFirst()
                continue
            }
            guard status == errSecSuccess else { throw KeychainError.saveFailed(status: status) }

            // Keep old records until the new item has been committed and read back successfully.
            var verify = q
            verify[kSecReturnData as String] = true
            verify[kSecMatchLimit as String] = kSecMatchLimitOne
            let (verified, stored) = operations.read(verify)
            guard verified == errSecSuccess, stored == data else {
                throw KeychainError.verificationFailed
            }
            for location in locations where location.protected != destination.protected && location.value != nil {
                try remove(key, protected: location.protected)
            }
            if key == .credentials {
                for legacy in [Key.controllerURL, .apiKey] {
                    for location in locations {
                        try remove(legacy, protected: location.protected)
                    }
                }
            }
            return
        }
        throw KeychainError.saveFailed(status: errSecMissingEntitlement)
    }

    private func write(_ data: Data, query: [String: Any]) -> OSStatus {
        let status = operations.update(query, [kSecValueData as String: data])
        guard status == errSecItemNotFound else { return status }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        return operations.add(add)
    }

    private func remove(_ key: Key, protected: Bool) throws {
        let status = operations.delete(query(for: key, protected: protected))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    func delete(_ key: Key) throws {
        var failure: Error?
        for protected in [true, false] {
            do { try remove(key, protected: protected) } catch { failure = failure ?? error }
        }
        // An inaccessible old backend is not proof that its credentials were removed.
        if let failure { throw failure }
    }
}

enum KeychainError: Error, Sendable, LocalizedError {
    case saveFailed(status: OSStatus)
    case readFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case invalidRecord
    case conflictingRecords
    case verificationFailed
    case legacyCredentials

    static let entitlementGuidance = "This build lacks the required Keychain entitlement (OSStatus -34018). Use an appropriately signed build with access to the original Keychain records, then retry cleanup. Some records may remain; unlocking Keychain alone does not fix this signing issue."

    var requiresEntitledBuild: Bool {
        switch self {
        case .saveFailed(let status), .readFailed(let status), .deleteFailed(let status):
            status == errSecMissingEntitlement
        default: false
        }
    }

    var errorDescription: String? {
        if requiresEntitledBuild { return Self.entitlementGuidance }
        return switch self {
        case .legacyCredentials:
            "Saved credentials use the old format. Re-enter your controller URL and API key to reconnect securely."
        case .conflictingRecords:
            "Keychain contains conflicting credential records. Re-enter your controller URL and API key."
        case .invalidRecord:
            "Saved credentials are invalid. Re-enter your controller URL and API key."
        case .readFailed:
            "Could not read credentials from Keychain. Unlock it and try again."
        case .saveFailed, .verificationFailed:
            "Could not save and verify credentials in Keychain. Unlock it and try again."
        case .deleteFailed:
            "Keychain cleanup was incomplete. Some saved credentials may remain."
        }
    }
}
