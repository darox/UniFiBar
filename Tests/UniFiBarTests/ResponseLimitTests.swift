import Foundation
import os
import Testing
@testable import UniFiBar

struct ResponseLimitTests {
    private struct Bytes: AsyncSequence, AsyncIteratorProtocol {
        let count: Int
        let reads = OSAllocatedUnfairLock(initialState: 0)
        var failAfter: Int? = nil
        func makeAsyncIterator() -> Self { self }
        func next() async throws -> UInt8? {
            try reads.withLock { read in
                if read == failAfter { throw URLError(.networkConnectionLost) }
                guard read < count else { return nil }
                read += 1
                return 7
            }
        }
    }

    private func response(length: Int = -1, status: Int = 200) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://fixture.invalid"))
        return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                          headerFields: length < 0 ? [:] : ["Content-Length": "\(length)"]))
    }

    @Test(arguments: [-1, 2, 100])
    func oversizedBodiesStopDuringReading(declaredLength: Int) async throws {
        let bytes = Bytes(count: 100)
        await #expect(throws: URLError(.dataLengthExceedsMaximum)) {
            try await UniFiClient.boundedResponseData(bytes, response: response(length: declaredLength), limit: 4)
        }
        #expect(bytes.reads.withLock { $0 } == (declaredLength > 4 ? 0 : 5))
    }

    private class StubURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url, let count = Int(url.lastPathComponent) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Length": String(count)]
            )!
            let data = Data(repeating: 7, count: count)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @Test func productionTransportStopsAnOversizedBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let delegate = SameOriginRedirectDelegate()

        let exact = try #require(URL(string: "https://fixture.invalid/body/4"))
        let accepted = try await UniFiClient.boundedResponse(
            for: URLRequest(url: exact), using: session, delegate: delegate, limit: 4
        )
        #expect(accepted == Data(repeating: 7, count: 4))

        let oversized = try #require(URL(string: "https://fixture.invalid/body/5"))
        await #expect(throws: URLError(.dataLengthExceedsMaximum)) {
            try await UniFiClient.boundedResponse(
                for: URLRequest(url: oversized), using: session, delegate: delegate, limit: 4
            )
        }
    }

    @Test(arguments: [0, 4])
    func acceptsEmptyAndExactLimit(count: Int) async throws {
        let result = try await UniFiClient.boundedResponseData(Bytes(count: count), response: response(), limit: 4)
        #expect(result == Data(repeating: 7, count: count))
    }

    @Test func statusAndTransportErrorsSurvive() async throws {
        let bytes = Bytes(count: 100)
        await #expect(throws: UniFiError.self) {
            try await UniFiClient.boundedResponseData(bytes, response: response(status: 401), limit: 4)
        }
        #expect(bytes.reads.withLock { $0 } == 0)
        await #expect(throws: URLError(.networkConnectionLost)) {
            try await UniFiClient.boundedResponseData(Bytes(count: 4, failAfter: 2), response: response(), limit: 4)
        }
    }

    @Test func cancelledReadDoesNotConsumeBody() async throws {
        let bytes = Bytes(count: 100)
        let reply = try response()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await UniFiClient.boundedResponseData(bytes, response: reply, limit: 4)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(bytes.reads.withLock { $0 } == 0)
    }
}
