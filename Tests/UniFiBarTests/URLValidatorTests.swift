import Testing
@testable import UniFiBar

struct URLValidatorTests {

    @Test(arguments: ["https://192.168.1.1/proxy/network", "https://controller.invalid/status"])
    func nonRootPathRejected(raw: String) {
        guard case .failure(let error) = URLValidator.normalizeAndValidate(raw) else {
            Issue.record("Non-root path accepted: \(raw)")
            return
        }
        #expect(error == .noPath)
    }

    @Test(arguments: ["https://192.168.1.1:8443", "https://[fd00::1]:8443", "https://controller.invalid:443"])
    func explicitPortAccepted(raw: String) {
        guard case .success = URLValidator.normalizeAndValidate(raw) else {
            Issue.record("Valid port rejected: \(raw)")
            return
        }
    }

    @Test(arguments: ["https://:secret@controller.invalid", "https://user:secret@controller.invalid"])
    func userinfoRejected(raw: String) {
        guard case .failure(let error) = URLValidator.normalizeAndValidate(raw) else {
            Issue.record("Userinfo accepted: \(raw)")
            return
        }
        #expect(error == .noUserinfo)
    }

    @Test(arguments: ["HTTPS://controller.invalid", "http-controller.invalid"])
    func testSchemeDetection(raw: String) throws {
        let url = try URLValidator.normalizeAndValidate(raw).get()
        #expect(url.scheme?.lowercased() == "https")
        #expect(url.host()?.hasSuffix("controller.invalid") == true)
    }

    @Test(arguments: ["https://controller.invalid:0", "https://controller.invalid:65536", "ftp://controller.invalid"])
    func testInvalidTransportRejected(raw: String) {
        if case .success = URLValidator.normalizeAndValidate(raw) {
            Issue.record("Invalid transport accepted")
        }
    }

    @Test func testValidHTTPS() {
        let result = URLValidator.normalizeAndValidate("https://192.168.1.1")
        guard case .success(let url) = result else {
            Issue.record("Expected success for valid HTTPS URL")
            return
        }
        #expect(url.host() == "192.168.1.1")
        #expect(url.scheme == "https")
    }

    @Test func testAutoPrependHTTPS() {
        let result = URLValidator.normalizeAndValidate("192.168.1.1")
        guard case .success(let url) = result else {
            Issue.record("Expected success for bare hostname")
            return
        }
        #expect(url.scheme == "https")
        #expect(url.host() == "192.168.1.1")
    }

    @Test func testHTTPRejected() {
        let result = URLValidator.normalizeAndValidate("http://192.168.1.1")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure for HTTP URL")
            return
        }
        #expect(error == .mustBeHTTPS)
    }

    @Test func testQueryRejected() {
        let result = URLValidator.normalizeAndValidate("https://controller.local?foo=bar")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure for URL with query")
            return
        }
        #expect(error == .noQueryOrFragment)
    }

    @Test func testFragmentRejected() {
        let result = URLValidator.normalizeAndValidate("https://controller.local#anchor")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure for URL with fragment")
            return
        }
        #expect(error == .noQueryOrFragment)
    }

    @Test func testUserinfoRejected() {
        let result = URLValidator.normalizeAndValidate("https://user:pass@controller.local")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure for URL with userinfo")
            return
        }
        #expect(error == .noUserinfo)
    }

    @Test func testTrailingSlashStripped() {
        let result = URLValidator.normalizeAndValidate("https://controller.local/")
        guard case .success(let url) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(url.absoluteString == "https://controller.local")
    }

    @Test func testWhitespaceTrimmed() {
        let result = URLValidator.normalizeAndValidate("  https://controller.local  ")
        guard case .success(let url) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(url.host() == "controller.local")
    }

    @Test func testEmptyHostRejected() {
        let result = URLValidator.normalizeAndValidate("https://")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure for empty host")
            return
        }
        #expect(error == .emptyHost)
    }
}
