import Foundation
import Security

/// Security.framework operations are injectable; fixtures never access the real Keychain.
struct CertificatePinStore: Sendable {
    let read: @Sendable ([String: Any]) -> (OSStatus, Data?)
    let add: @Sendable ([String: Any]) -> OSStatus
    let delete: @Sendable ([String: Any]) -> OSStatus

    static let keychain = Self(
        read: { query in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        },
        add: { SecItemAdd($0 as CFDictionary, nil) },
        delete: { SecItemDelete($0 as CFDictionary) }
    )

    enum Failure: Error { case status(OSStatus), malformedPin, conflictingPin }

    func load(host: String) throws -> Data? {
        var query = query(host: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = read(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.status(status) }
        guard let data, data.count == 32 else { throw Failure.malformedPin }
        return data
    }

    /// First writer wins, including across delegates/processes. Never replace a different pin.
    func saveIfAbsent(_ pin: Data, host: String) throws {
        guard pin.count == 32 else { throw Failure.malformedPin }
        var query = query(host: host)
        query[kSecValueData as String] = pin
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = add(query)
        if status == errSecDuplicateItem {
            guard try load(host: host) == pin else { throw Failure.conflictingPin }
        } else if status != errSecSuccess {
            throw Failure.status(status)
        }
    }

    func remove(host: String) throws {
        let status = delete(query(host: host))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.status(status) }
    }

    func removeAll() throws {
        let status = delete([kSecClass as String: kSecClassGenericPassword,
                             kSecAttrService as String: "com.unifbar.cert-pins"])
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.status(status) }
    }

    private func query(host: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.unifbar.cert-pins",
         kSecAttrAccount as String: "com.unifbar.cert-pin.\(host)"]
    }
}
