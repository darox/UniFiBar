@testable import UniFiBar

actor FakeKeychain: KeychainHelperProtocol {
    private var storage: [String: String] = [:]
    private(set) var readCount = 0
    var saveError: KeychainError? = nil

    func setSaveError(_ error: KeychainError?) {
        saveError = error
    }

    func read(_ key: KeychainHelper.Key) -> String? {
        readCount += 1
        return storage[key.rawValue]
    }

    func save(_ value: String, for key: KeychainHelper.Key) throws {
        if let error = saveError { throw error }
        storage[key.rawValue] = value
    }

    func delete(_ key: KeychainHelper.Key) {
        storage[key.rawValue] = nil
    }
}
