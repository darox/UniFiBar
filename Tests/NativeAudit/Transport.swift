import Foundation
import os
import Security

// Actual URLSession/TLS; only pin persistence is in-memory. Production delegates and
// boundedResponseData execute unchanged. Native persistence is exercised separately.
func transportCheck(_ mode: String, port: Int, pinByte: UInt8? = nil) async throws {
    try require((1...65535).contains(port), "loopback port")
    let pin = OSAllocatedUnfairLock<Data?>(initialState: pinByte.map { Data(repeating: $0, count: 32) })
    let store = CertificatePinStore(read: { _ in
        pin.withLock { $0.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil) }
    }, add: { query in
        let data = query[kSecValueData as String] as? Data
        return pin.withLock { current in
            if current != nil { return errSecDuplicateItem }
            current = data
            return errSecSuccess
        }
    }, delete: { _ in pin.withLock { $0 = nil }; return errSecSuccess })
    let prompts = OSAllocatedUnfairLock(initialState: 0)
    let approval: (@Sendable (PinnedCertDelegate.CertificateDetails) async -> Bool)? =
        ["approved-bad-host", "slow-approved-bad-host", "denied-bad-host"].contains(mode) ? { @Sendable _ in
            prompts.withLock { $0 += 1 }
            if mode == "slow-approved-bad-host" { try? await Task.sleep(for: .seconds(5)) }
            return mode != "denied-bad-host"
        } : nil
    let delegate = PinnedCertDelegate(host: "127.0.0.1", pinStore: store, confirmCertificate: approval)
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [:]
    config.timeoutIntervalForRequest = 2
    config.timeoutIntervalForResource = 4
    config.httpMaximumConnectionsPerHost = 2
    let session = URLSession(configuration: config, delegate: mode == "default-reject" ? nil : delegate, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let redirect = SameOriginRedirectDelegate(certificateDelegate: mode == "default-reject" ? nil : delegate)
    let path: String
    switch mode {
    case "chunked", "oversized", "declared-oversized", "exact-limit", "understated", "timeout", "cancel", "same-origin", "cross-origin", "downgrade": path = mode
    default: path = "ok"
    }
    var request = URLRequest(url: URL(string: "https://127.0.0.1:\(port)/\(path)")!)
    request.setValue("synthetic-loopback-only", forHTTPHeaderField: "X-API-KEY")
    let headersReceived = AsyncStream<Void>.makeStream()
    let task = Task { [request] in
        defer { headersReceived.continuation.finish() }
        func readResponse() async throws -> Data {
            let (bytes, response) = try await session.bytes(for: request, delegate: redirect)
            defer { bytes.task.cancel() }
            headersReceived.continuation.yield(())
            return try await UniFiClient.boundedResponseData(bytes, response: response, limit: 1024)
        }
        do { return try await readResponse() } catch {
            guard await delegate.approvePendingCertificate() else { throw error }
            return try await readResponse()
        }
    }
    if mode == "cancel" {
        // Cancel only after real response headers, not an arbitrary startup delay.
        for await _ in headersReceived.stream { task.cancel(); break }
    }
    do {
        let data = try await task.value
        switch mode {
        case "valid", "continuity", "chunked", "same-origin", "approved-bad-host", "slow-approved-bad-host":
            try require(String(decoding: data, as: UTF8.self) == "fixture-ok", "response body")
        case "exact-limit": try require(data.count == 1024, "exact boundary must succeed")
        case "understated":
            // HTTP framing belongs to URLSession. Extra bytes may be discarded, never counted as data.
            try require(data.count <= 4, "understated Content-Length must not deliver trailing bytes")
            print("OBSERVED: native HTTP framing delivered \(data.count) declared bytes; trailing bytes not a JSON success claim")
        default: throw AuditFailure("unexpected success: \(mode)")
        }
        if ["continuity", "approved-bad-host", "slow-approved-bad-host"].contains(mode) {
            let second = PinnedCertDelegate(host: "127.0.0.1", pinStore: store)
            let next = URLSession(configuration: config, delegate: second, delegateQueue: nil)
            defer { next.invalidateAndCancel() }
            let (bytes, response) = try await next.bytes(for: request, delegate: SameOriginRedirectDelegate(certificateDelegate: second))
            defer { bytes.task.cancel() }
            let restored = try await UniFiClient.boundedResponseData(bytes, response: response, limit: 1024)
            try require(restored == data && pin.withLock { $0?.count == 32 }, "pin continuity in fresh delegate/session")
        }
    } catch {
        if let failure = error as? AuditFailure { throw failure }
        let code = (error as NSError).code
        print("OBSERVED: \(mode) error=\((error as NSError).domain)/\(code) certChanged=\(delegate.certChanged)")
        switch mode {
        case "bad-host", "denied-bad-host", "expired", "default-reject":
            try require(pin.withLock { $0 == nil }, "rejected certificate must not pin")
            if mode == "denied-bad-host" { try require(delegate.failure == .nameMismatch, "explicit certificate failure") }
        case "mismatch": try require(delegate.certChanged, "pin mismatch flag")
        case "oversized", "declared-oversized": try require((error as? URLError)?.code == .dataLengthExceedsMaximum, "size error")
        case "timeout": try require((error as? URLError)?.code == .timedOut, "timeout error")
        case "cancel": try require(error is CancellationError || (error as? URLError)?.code == .cancelled, "cancel error")
        case "cross-origin", "downgrade":
            guard case UniFiError.httpError(statusCode: 302) = error else { throw error }
        case "understated":
            try require((error as? URLError)?.code == .cannotParseResponse || (error as? URLError)?.code == .networkConnectionLost,
                "only a native framing failure is acceptable for understated length")
        default: throw error
        }
    }
    try require(prompts.withLock { $0 } == (approval == nil ? 0 : 1), "only the first mismatched-name connection requests approval")
    if mode == "denied-bad-host" || mode == "approved-bad-host" {
        pin.withLock { $0 = nil } // A fresh in-memory store for the full production-client flow.
        let client = UniFiClient(baseURL: URL(string: "https://127.0.0.1:\(port)")!,
            apiKey: "synthetic-loopback-only", allowSelfSigned: true, confirmCertificate: approval, pinStore: store)
        let result: Result<String, Error>
        do { result = .success(try await client.fetchSiteId()) } catch { result = .failure(error) }
        await client.invalidate()
        if mode == "approved-bad-host" {
            try require(try result.get() == "fixture-site", "production client retries and discovers the site after approval")
        } else {
            guard case .failure(let error) = result else { throw AuditFailure("unapproved production client succeeded") }
            try require(error as? CertificateConnectionError == .nameMismatch, "production client translates opaque TLS cancellation")
        }
    }
    print("PASS: transport \(mode)")
}
