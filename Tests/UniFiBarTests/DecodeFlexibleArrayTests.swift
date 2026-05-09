import Foundation
import Testing
@testable import UniFiBar

struct DecodeFlexibleArrayTests {

    // Simple DTO for testing decode
    private struct TestItem: Decodable, Sendable {
        let id: String
        let name: String
    }

    // MARK: - Wrapped Array { "data": [...] }

    @Test func testWrappedArray() {
        let json = """
        {
          "data": [
            {"id": "1", "name": "Alpha"},
            {"id": "2", "name": "Beta"}
          ]
        }
        """.data(using: .utf8)!

        let result = UniFiClient.decodeFlexibleArray(TestItem.self, from: json, endpoint: "test")
        #expect(result != nil)
        #expect(result?.count == 2)
        #expect(result?.first?.name == "Alpha")
    }

    // MARK: - Bare Array [...]

    @Test func testBareArray() {
        let json = """
        [
          {"id": "1", "name": "Alpha"},
          {"id": "2", "name": "Beta"}
        ]
        """.data(using: .utf8)!

        let result = UniFiClient.decodeFlexibleArray(TestItem.self, from: json, endpoint: "test")
        #expect(result != nil)
        #expect(result?.count == 2)
        #expect(result?.first?.name == "Alpha")
    }

    // MARK: - Null Data { "data": null }

    @Test func testNullData() {
        let json = """
        { "data": null }
        """.data(using: .utf8)!

        let result = UniFiClient.decodeFlexibleArray(TestItem.self, from: json, endpoint: "test")
        #expect(result != nil)
        #expect(result?.isEmpty == true)
    }

    // MARK: - Empty Data { "data": [] }

    @Test func testEmptyWrappedArray() {
        let json = """
        { "data": [] }
        """.data(using: .utf8)!

        let result = UniFiClient.decodeFlexibleArray(TestItem.self, from: json, endpoint: "test")
        #expect(result != nil)
        #expect(result?.isEmpty == true)
    }

    // MARK: - Bare Empty Array []

    @Test func testBareEmptyArray() {
        let json = "[]".data(using: .utf8)!

        let result = UniFiClient.decodeFlexibleArray(TestItem.self, from: json, endpoint: "test")
        #expect(result != nil)
        #expect(result?.isEmpty == true)
    }

    // MARK: - Invalid JSON

    @Test func testInvalidJSON() {
        let json = "not json at all".data(using: .utf8)!

        let result = UniFiClient.decodeFlexibleArray(TestItem.self, from: json, endpoint: "test")
        #expect(result == nil)
    }

    // MARK: - Empty Data

    @Test func testEmptyData() {
        let json = Data()

        let result = UniFiClient.decodeFlexibleArray(TestItem.self, from: json, endpoint: "test")
        #expect(result == nil)
    }

    // MARK: - Non-array data value

    @Test func testNonArrayDataValue() {
        let json = """
        { "data": "not_an_array" }
        """.data(using: .utf8)!

        let result = UniFiClient.decodeFlexibleArray(TestItem.self, from: json, endpoint: "test")
        // Should fail both wrapped and bare array decode, returning nil
        #expect(result == nil)
    }
}