import Testing
@testable import UniFiBar

struct URLValidatorTests {

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