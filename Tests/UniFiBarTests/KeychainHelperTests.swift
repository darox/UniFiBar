import Foundation
import os
import Security
import Testing
@testable import UniFiBar

struct KeychainHelperTests {
    private final class Items: Sendable {
        struct State {
            var items: [String: Data] = [:]
            var protectedReadError: OSStatus?
            var protectedWriteError: OSStatus?
            var failAddOnly = false
            var updateError: OSStatus?
            var deleteError: OSStatus?
            var failVerification = false
            var reads = 0
            var adds = 0
            var updates = 0
            var deletes = 0
        }
        let state = OSAllocatedUnfairLock(initialState: State())
        static func id(_ key: KeychainHelper.Key, _ protected: Bool) -> String { "\(protected):\(key.rawValue)" }
        private static func id(_ query: [String: Any]) -> String {
            "\(query[kSecUseDataProtectionKeychain as String] as? Bool ?? false):\(query[kSecAttrAccount as String] as? String ?? "")"
        }
        func seed(_ key: KeychainHelper.Key, _ value: String, protected: Bool = true) {
            state.withLock { $0.items[Self.id(key, protected)] = Data(value.utf8) }
        }
        var store: KeychainHelper {
            KeychainHelper(operations: .init(read: { [self] query in
                let protected = query[kSecUseDataProtectionKeychain as String] as? Bool == true
                let id = Self.id(query)
                return state.withLock {
                    $0.reads += 1
                    if protected, let error = $0.protectedReadError { return (error, nil) }
                    if $0.failVerification && $0.updates > 0 { return (errSecAuthFailed, nil) }
                    let data = $0.items[id]
                    return (data == nil ? errSecItemNotFound : errSecSuccess, data)
                }
            }, update: { [self] query, values in
                let id = Self.id(query)
                let data = values[kSecValueData as String] as? Data
                let protected = query[kSecUseDataProtectionKeychain as String] as? Bool == true
                return state.withLock {
                    $0.updates += 1
                    if let error = $0.updateError { return error }
                    if protected, !$0.failAddOnly, let error = $0.protectedWriteError { return error }
                    guard $0.items[id] != nil else { return errSecItemNotFound }
                    $0.items[id] = data
                    return errSecSuccess
                }
            }, add: { [self] query in
                let id = Self.id(query)
                let data = query[kSecValueData as String] as? Data
                let protected = query[kSecUseDataProtectionKeychain as String] as? Bool == true
                return state.withLock {
                    $0.adds += 1
                    if protected, let error = $0.protectedWriteError { return error }
                    guard $0.items[id] == nil else { return errSecDuplicateItem }
                    $0.items[id] = data
                    return errSecSuccess
                }
            }, delete: { [self] query in
                let protected = query[kSecUseDataProtectionKeychain as String] as? Bool == true
                let id = Self.id(query)
                return state.withLock {
                    $0.deletes += 1
                    if let error = $0.deleteError { return error }
                    if protected, $0.protectedReadError == errSecMissingEntitlement { return errSecMissingEntitlement }
                    return $0.items.removeValue(forKey: id) == nil ? errSecItemNotFound : errSecSuccess
                }
            }))
        }
    }

    @Test(arguments: [errSecInteractionNotAllowed, errSecAuthFailed])
    func readFailureIsNotAbsenceOrBackendFallback(status: OSStatus) async {
        let items = Items()
        items.seed(.credentials, "legacy-record", protected: false)
        items.state.withLock { $0.protectedReadError = status }
        let store = items.store
        await #expect(throws: KeychainError.self) { try await store.read(.credentials) }
        await #expect(throws: KeychainError.self) { try await store.save("replacement", for: .credentials) }
        #expect(items.state.withLock { $0.updates == 0 && $0.adds == 0 && $0.deletes == 0 })
    }

    @Test func onlyMissingEntitlementAllowsLegacyFallback() async throws {
        let items = Items()
        items.state.withLock { $0.protectedReadError = errSecMissingEntitlement }
        let store = items.store
        try await store.save("whole-record", for: .credentials)
        #expect(try await store.read(.credentials) == "whole-record")
        #expect(items.state.withLock { $0.items[Items.id(.credentials, false)] != nil })
        #expect(items.state.withLock { $0.items[Items.id(.credentials, true)] == nil })
    }

    @Test(arguments: [false, true])
    func missingEntitlementAtWriteAllowsFallbackWithoutAProbe(addOnly: Bool) async throws {
        let items = Items()
        items.state.withLock {
            $0.protectedWriteError = errSecMissingEntitlement
            $0.failAddOnly = addOnly
        }
        let store = items.store
        try await store.save("whole-record", for: .credentials)
        #expect(try await store.read(.credentials) == "whole-record")
        #expect(items.state.withLock { $0.items[Items.id(.credentials, false)] != nil })
        #expect(items.state.withLock { $0.items[Items.id(.credentials, true)] == nil })
    }

    @Test func failedUpdateDoesNotAttemptAddOrDeleteOldRecords() async {
        let items = Items()
        items.seed(.credentials, "old-record")
        items.seed(.apiKey, "old-key")
        items.state.withLock { $0.updateError = errSecInteractionNotAllowed }
        await #expect(throws: KeychainError.self) { try await items.store.save("new-record", for: .credentials) }
        #expect(items.state.withLock { $0.adds == 0 && $0.deletes == 0 })
        #expect(items.state.withLock { $0.items[Items.id(.credentials, true)] == Data("old-record".utf8) })
    }

    @Test func explicitCommitMigratesAccessibleBackendAndOnlyThenRemovesLegacyItems() async throws {
        let items = Items()
        items.seed(.credentials, "old-record", protected: false)
        for protected in [true, false] {
            items.seed(.controllerURL, "https://legacy.invalid", protected: protected)
            items.seed(.apiKey, "legacy-key", protected: protected)
        }
        let store = items.store
        #expect(try await store.read(.credentials) == "old-record")
        try await store.save("confirmed-new-record", for: .credentials)
        #expect(try await store.read(.credentials) == "confirmed-new-record")
        #expect(items.state.withLock { $0.items == [Items.id(.credentials, true): Data("confirmed-new-record".utf8)] })
    }

    @Test func conflictingBackendsFailClosedUntilExplicitSave() async throws {
        let items = Items()
        items.seed(.credentials, "one-record", protected: true)
        items.seed(.credentials, "another-record", protected: false)
        let store = items.store
        await #expect(throws: KeychainError.self) { try await store.read(.credentials) }
        try await store.save("confirmed-record", for: .credentials)
        #expect(try await store.read(.credentials) == "confirmed-record")
    }

    @Test func failedReadbackRetainsLegacyRecords() async {
        let items = Items()
        items.seed(.controllerURL, "https://legacy.invalid")
        items.seed(.apiKey, "legacy-key")
        items.state.withLock { $0.failVerification = true }
        await #expect(throws: KeychainError.self) { try await items.store.save("new-record", for: .credentials) }
        #expect(items.state.withLock { $0.deletes == 0 })
        #expect(items.state.withLock { $0.items[Items.id(.apiKey, true)] == Data("legacy-key".utf8) })
    }

    @Test func cleanupFailureIsNotReportedAsSuccessfulSave() async throws {
        let items = Items()
        items.seed(.apiKey, "legacy-key")
        items.state.withLock { $0.deleteError = errSecAuthFailed }
        let store = items.store
        await #expect(throws: KeychainError.self) { try await store.save("new-record", for: .credentials) }
        // The new item may already be committed, but it is always an entire record.
        #expect(try await store.read(.credentials) == "new-record")
        #expect(items.state.withLock { $0.items[Items.id(.apiKey, true)] != nil })
    }

    @Test func inaccessibleBackendDoesNotHideIncompleteDeletion() async throws {
        let items = Items()
        items.seed(.credentials, "old-record", protected: false)
        items.state.withLock { $0.protectedReadError = errSecMissingEntitlement }
        await #expect(throws: KeychainError.self) { try await items.store.delete(.credentials) }
        #expect(items.state.withLock { $0.deletes == 2 })
        #expect(items.state.withLock { $0.items[Items.id(.credentials, false)] == nil })
    }

    @Test func malformedItemIsNotAbsent() async {
        let items = Items()
        items.state.withLock { $0.items[Items.id(.credentials, true)] = Data([0xff]) }
        await #expect(throws: KeychainError.self) { try await items.store.read(.credentials) }
    }
}
