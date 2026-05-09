import Testing
@testable import UniFiBar

@MainActor
struct UpdateCheckerTests {

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