import Foundation
import Testing
@testable import UniFiBar

@MainActor
struct UpdateCheckerTests {

    private final class RetryFixture {
        var date = Date(timeIntervalSince1970: 1_788_825_600)
        var calls = 0
        var fails = true
    }

    private func withDefaults(_ check: (UserDefaults) async throws -> Void) async rethrows {
        let suite = "UniFiBarTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await check(defaults)
    }

    private func release(_ link: String = "https://github.com/darox/UniFiBar/releases/tag/v999.0.0") throws -> (Data, URLResponse) {
        let data = try JSONSerialization.data(withJSONObject: ["tag_name": "v999.0.0", "html_url": link, "body": "Fixture notes"])
        let url = try #require(URL(string: "https://api.github.com/repos/darox/UniFiBar/releases/latest"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return (data, response)
    }

    @Test func concurrentManualAndPeriodicChecksShareOneRequest() async {
        await withDefaults { defaults in
            var calls = 0
            let checker = UpdateChecker(defaults: defaults, fetch: { _ in calls += 1; return try release() })
            let first = checker.checkNow()
            let second = checker.schedulePeriodicCheck()
            let third = checker.checkNow()
            await first?.value
            await second?.value
            await third?.value
            #expect(calls == 1)
            #expect(checker.updateAvailable)
            #expect(checker.releaseURL?.host == "github.com")
        }
    }

    @Test(arguments: [URLError(.timedOut), URLError(.dataLengthExceedsMaximum)])
    func automaticChecksAreDueDailyAndFailuresBackOff(error: URLError) async {
        await withDefaults { defaults in
            let fixture = RetryFixture()
            let checker = UpdateChecker(defaults: defaults, now: { fixture.date }, fetch: { _ in
                fixture.calls += 1
                if fixture.fails { throw error }
                return try release()
            })
            await checker.schedulePeriodicCheck()?.value
            let premature = checker.schedulePeriodicCheck()
            #expect(premature == nil)
            await premature?.value
            #expect(fixture.calls == 1)
            fixture.date.addTimeInterval(300)
            fixture.fails = false
            await checker.schedulePeriodicCheck()?.value
            #expect(fixture.calls == 2)
            let notDue = checker.schedulePeriodicCheck()
            #expect(notDue == nil)
            await notDue?.value
            fixture.date.addTimeInterval(86_400)
            await checker.schedulePeriodicCheck()?.value
            #expect(fixture.calls == 3)
        }
    }

    @Test(arguments: ["http://github.com/darox/UniFiBar/releases/tag/v2", "https://evil.invalid/release",
                      "https://github.com/other/repo/releases/tag/v2", "javascript:alert(1)",
                      "https://user@github.com/darox/UniFiBar/releases/tag/v2",
                      "https://github.com:8443/darox/UniFiBar/releases/tag/v2",
                      "https://github.com/darox/UniFiBar/releases/tag/%2e%2e/%2e%2e/issues"])
    func untrustedReleaseLinksAreNotPublished(link: String) async {
        await withDefaults { defaults in
            let checker = UpdateChecker(defaults: defaults, fetch: { _ in try release(link) })
            await checker.checkNow()?.value
            #expect(!checker.updateAvailable)
            #expect(checker.releaseURL == nil)
            #expect(defaults.object(forKey: "com.unifbar.lastUpdateCheck") == nil)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledRequestCannotPublishOrConsumeTheDailyCheck() async throws {
        try await withDefaults { defaults in
            let started = AsyncStream<Void>.makeStream()
            var resume: CheckedContinuation<Void, Never>?
            let checker = UpdateChecker(defaults: defaults, fetch: { _ in
                await withCheckedContinuation {
                    resume = $0
                    started.continuation.yield(())
                }
                return try release()
            })
            var signals = started.stream.makeAsyncIterator()
            let task = try #require(checker.checkNow())
            await signals.next()
            task.cancel()
            resume?.resume()
            await task.value
            #expect(!checker.updateAvailable)
            #expect(defaults.object(forKey: "com.unifbar.lastUpdateCheck") == nil)
        }
    }

    @Test func testDisabledChecksDoNotCreateTasks() {
        let checker = UpdateChecker(checksEnabled: false)
        #expect(checker.checkNow() == nil)
        #expect(checker.schedulePeriodicCheck() == nil)
        #expect(!checker.updateAvailable)
        #expect(checker.latestVersion == nil)
    }

    // MARK: - Version Comparison

    @Test func testIsNewer_major() {
        #expect(UpdateChecker.isNewer(current: "2.0.0", remote: "3.0.0") == true)
        #expect(UpdateChecker.isNewer(current: "3.0.0", remote: "2.0.0") == false)
    }

    @Test func testIsNewer_minor() {
        #expect(UpdateChecker.isNewer(current: "2.0.0", remote: "2.1.0") == true)
        #expect(UpdateChecker.isNewer(current: "2.1.0", remote: "2.0.0") == false)
    }

    @Test func testIsNewer_patch() {
        #expect(UpdateChecker.isNewer(current: "2.0.0", remote: "2.0.1") == true)
        #expect(UpdateChecker.isNewer(current: "2.0.1", remote: "2.0.0") == false)
    }

    @Test func testIsNewer_equal() {
        #expect(UpdateChecker.isNewer(current: "2.0.0", remote: "2.0.0") == false)
        #expect(UpdateChecker.isNewer(current: "1.5.3", remote: "1.5.3") == false)
    }

    @Test func testIsNewer_older() {
        #expect(UpdateChecker.isNewer(current: "3.0.0", remote: "2.9.9") == false)
    }

    @Test func testIsNewer_unevenLengths() {
        #expect(UpdateChecker.isNewer(current: "2.0", remote: "2.0.1") == true)
        #expect(UpdateChecker.isNewer(current: "2.0.0", remote: "2.0") == false)
    }

    // MARK: - Pre-release version parsing

    @Test func testIsNewer_preRelease() {
        // "2.0.0-beta1" should parse as [2, 0, 0] — not [2, 0]
        #expect(UpdateChecker.isNewer(current: "2.0.0", remote: "2.0.0-beta1") == false)
        // Pre-release is NOT newer than the same stable version
        #expect(UpdateChecker.isNewer(current: "1.9.9", remote: "2.0.0-beta1") == true)
    }

    // MARK: - Version segment parsing

    @Test func testParseVersionSegment_numeric() {
        #expect(UpdateChecker.parseVersionSegment("3") == 3)
        #expect(UpdateChecker.parseVersionSegment("0") == 0)
        #expect(UpdateChecker.parseVersionSegment("15") == 15)
    }

    @Test func testParseVersionSegment_preRelease() {
        #expect(UpdateChecker.parseVersionSegment("0-beta1") == 0)
        #expect(UpdateChecker.parseVersionSegment("3-rc2") == 3)
        #expect(UpdateChecker.parseVersionSegment("1-alpha") == 1)
    }

    @Test func testParseVersionSegment_nonNumeric() {
        #expect(UpdateChecker.parseVersionSegment("abc") == 0)
    }
}
