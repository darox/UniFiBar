import Foundation
import Testing
@testable import UniFiBar

struct RedirectPolicyTests {
    @Test(arguments: ["GET", "POST"], [
        "https://other.invalid/path", "http://controller.invalid/path",
        "https://controller.invalid:8443/path", "https://user:pass@controller.invalid/path",
        "https://controller.invalid.evil.invalid/path"
    ])
    func testRejectsCredentialEscape(method: String, destination: String) async throws {
        #expect(try await redirect(method: method, destination: destination) == nil)
    }

    @Test(arguments: ["https://controller.invalid/path", "https://CONTROLLER.invalid:443/path"])
    func testAllowsSameHTTPSOrigin(destination: String) async throws {
        let request = try #require(await redirect(method: "GET", destination: destination))
        #expect(request.value(forHTTPHeaderField: "X-API-KEY") == "synthetic-key")
    }

    private func redirect(method: String, destination: String) async throws -> URLRequest? {
        let origin = try #require(URL(string: "https://controller.invalid/original"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var original = URLRequest(url: origin)
        original.httpMethod = method
        original.setValue("synthetic-key", forHTTPHeaderField: "X-API-KEY")
        let task = session.dataTask(with: original) // Suspended: no network traffic.
        var redirected = original
        let target = try #require(URL(string: destination))
        redirected.url = target
        let response = try #require(HTTPURLResponse(url: origin, statusCode: 307, httpVersion: nil, headerFields: nil))
        return await SameOriginRedirectDelegate().urlSession(
            session, task: task, willPerformHTTPRedirection: response, newRequest: redirected
        )
    }
}
