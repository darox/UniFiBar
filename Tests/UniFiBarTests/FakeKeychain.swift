import Foundation
@testable import UniFiBar

actor FakeKeychain: KeychainHelperProtocol {
    private var storage: [String: String] = [:]
    private(set) var readCount = 0
    private(set) var saveCount = 0
    private(set) var deleteCount = 0
    private var saveError: KeychainError?
    private var saveErrorKey: KeychainHelper.Key?
    private var readError: KeychainError?
    private var deleteError: KeychainError?

    enum Operation: Sendable { case read, save, delete }
    nonisolated let pauses = AsyncStream<Operation>.makeStream()
    private var pauseOperation: Operation?
    private var continuation: CheckedContinuation<Void, Never>?
    func pauseNext(_ operation: Operation) { pauseOperation = operation }
    func resume() { continuation?.resume(); continuation = nil }
    private func waitIfPaused(_ operation: Operation) async {
        guard pauseOperation == operation else { return }
        pauseOperation = nil
        await withCheckedContinuation {
            continuation = $0
            pauses.continuation.yield(operation)
        }
    }

    func setSaveError(_ error: KeychainError?, forKey key: KeychainHelper.Key? = nil) {
        saveError = error
        saveErrorKey = key
    }
    func setReadError(_ error: KeychainError?) { readError = error }
    func setDeleteError(_ error: KeychainError?) { deleteError = error }

    func read(_ key: KeychainHelper.Key) async throws -> String? {
        readCount += 1
        let value = storage[key.rawValue]
        await waitIfPaused(.read)
        if let readError { throw readError }
        return value
    }

    func save(_ value: String, for key: KeychainHelper.Key) async throws {
        saveCount += 1
        await waitIfPaused(.save)
        if let error = saveError, saveErrorKey == nil || saveErrorKey == key { throw error }
        storage[key.rawValue] = value
    }

    func seedCredentials(url: String, key: String, allowSelfSigned: Bool = false) throws {
        let record = StoredCredentials(controllerURL: url, apiKey: key, allowSelfSigned: allowSelfSigned)
        storage[KeychainHelper.Key.credentials.rawValue] = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
    }

    func delete(_ key: KeychainHelper.Key) async throws {
        deleteCount += 1
        await waitIfPaused(.delete)
        if let deleteError { throw deleteError }
        storage[key.rawValue] = nil
    }
}
