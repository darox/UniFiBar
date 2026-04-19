import Testing
@testable import UniFiBar

struct UniFiErrorTests {

    @Test func testHTTPErrorCode() {
        let error = UniFiError.httpError(statusCode: 401)
        if case .httpError(let code) = error {
            #expect(code == 401)
        }
    }

    @Test func testHTTPErrorCodes_various() {
        let codes = [400, 401, 403, 404, 500]
        for code in codes {
            let error = UniFiError.httpError(statusCode: code)
            if case .httpError(let stored) = error {
                #expect(stored == code)
            }
        }
    }

    @Test func testAllCases() {
        // Verify all cases can be constructed
        let errors: [UniFiError] = [
            .httpError(statusCode: 500),
            .noSitesFound,
            .selfNotFound,
            .invalidURL,
            .notConfigured,
        ]
        #expect(errors.count == 5)
    }
}