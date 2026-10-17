import Foundation
import Testing
@testable import UniFiBar

struct FormattersTests {
    @Test func durationMinutes() {
        #expect(Formatters.duration(seconds: 0) == "0m")
        #expect(Formatters.duration(seconds: 1800) == "30m")
        #expect(Formatters.duration(seconds: -5) == "0m")
    }

    @Test func durationHours() {
        #expect(Formatters.duration(seconds: 3600) == "1h 0m")
        #expect(Formatters.duration(seconds: 8100) == "2h 15m")
    }

    @Test func durationDays() {
        #expect(Formatters.duration(seconds: 86400) == "1d")
        #expect(Formatters.duration(seconds: 90000) == "1d 1h")
        #expect(Formatters.duration(seconds: 90061) == "1d 1h")
    }
}
