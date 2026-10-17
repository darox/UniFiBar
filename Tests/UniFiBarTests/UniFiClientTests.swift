import Foundation
import Testing
@testable import UniFiBar

/// Synthetic, schema-shaped responses from docs/unifi-api-contracts-2026-09-08.md.
/// No live controller, native pin store, Keychain or interface lookup.
struct UniFiClientTests {
    private static let sitesPath = "/proxy/network/integration/v1/sites"
    private static let siteID = "11111111-1111-4111-8111-111111111111"
    private static let otherID = "22222222-2222-4222-8222-222222222222"

    private actor Replay {
        struct Step: Sendable {
            let path: String
            let data: Data
            var offset: Int? = nil
            var method = "GET"
        }
        var steps: [Step]
        init(_ steps: [Step]) { self.steps = steps }
        var remaining: Int { steps.count }

        func fetch(_ request: URLRequest) throws -> Data {
            let step = try #require(steps.first, "Unexpected request")
            steps.removeFirst()
            let url = try #require(request.url)
            #expect(url.host == "controller.invalid")
            #expect(url.path == step.path)
            #expect(request.httpMethod == step.method)
            #expect(request.value(forHTTPHeaderField: "X-API-KEY") == "synthetic-key")
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let offset = step.offset {
                #expect(query == [URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "limit", value: "200")])
            } else {
                #expect(query.isEmpty)
            }
            return step.data
        }
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    private func page(_ rows: [[String: Any]], offset: Int = 0, total: Int? = nil) throws -> Data {
        try json(["data": rows, "offset": offset, "limit": 200, "count": rows.count, "totalCount": total ?? rows.count])
    }

    private func site(_ id: String = Self.siteID, reference: String = "default") -> [String: Any] {
        ["id": id, "internalReference": reference, "name": "Synthetic site"]
    }

    @Test(arguments: ["ok", "error"])
    func legacyErrorEnvelopeCannotPublishMonitoring(code: String) async throws {
        let root = "/proxy/network/api/s/default"
        let empty = try json(["meta": ["rc": code], "data": []] as [String: Any])
        let health = try json(["meta": ["rc": code], "data": [["subsystem": "wan", "status": "ok"]]] as [String: Any])
        let replay = Replay([
            .init(path: Self.sitesPath, data: try page([site()]), offset: 0),
            .init(path: root + "/stat/health", data: health),
            .init(path: root + "/stat/session", data: empty, method: "POST"),
            .init(path: root + "/rest/dynamicdns", data: empty),
            .init(path: root + "/stat/portforward", data: empty),
            .init(path: root + "/stat/rogueap", data: empty, method: "POST")
        ])
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) })
        #expect((await client.fetchWANHealth() != nil) == (code == "ok"))
        #expect((await client.fetchSessionHistory(mac: "synthetic-mac") != nil) == (code == "ok"))
        let ddns = await client.fetchDDNSStatus()
        let forwards = await client.fetchPortForwards()
        let nearby = await client.fetchRogueAPs()
        for available in [ddns.data != nil, forwards.data != nil, nearby.data != nil] {
            #expect(available == (code == "ok"))
        }
        for error in [ddns.errorDetail, forwards.errorDetail, nearby.errorDetail] {
            #expect((error == nil) == (code == "ok"))
        }
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test func defaultSiteOnLaterPageIsPairedWithItsOfficialID() async throws {
        let devicePath = "/proxy/network/integration/v1/sites/\(Self.siteID)/devices"
        var steps = [
            Replay.Step(path: Self.sitesPath, data: try page([site(Self.otherID, reference: "branch")], total: 2), offset: 0),
            Replay.Step(path: Self.sitesPath, data: try page([site()], offset: 1, total: 2), offset: 1),
            Replay.Step(path: "/proxy/network/v2/api/site/default/clients/active", data: try json([["ip": "192.0.2.10", "ap_mac": "synthetic-ap"]]))
        ]
        for offset in stride(from: 0, to: 601, by: 200) {
            let rows = (offset..<min(offset + 200, 601)).map { ["id": "device-\($0)", "state": "ONLINE"] }
            steps.append(Replay.Step(path: devicePath, data: try page(rows, offset: offset, total: 601), offset: offset))
        }
        let replay = Replay(steps)
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) }, localAddresses: { ["192.0.2.10"] })
        let id = try await client.fetchSiteId()
        #expect(id == Self.siteID)
        #expect(try await client.fetchSiteId() == id) // Cached without another request.
        #expect(try await client.fetchSelfV2().client.ip == "192.0.2.10")
        let devices = try await client.fetchDevices(siteId: id)
        #expect(devices.count == 601)
        #expect(devices.last?.id == "device-600")
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test func singleNonDefaultSiteScopesEveryOlderEndpoint() async throws {
        let root = "/proxy/network/api/s/branch_a"
        let replay = Replay([
            .init(path: Self.sitesPath, data: try page([site(reference: "branch_a")]), offset: 0),
            .init(path: "/proxy/network/v2/api/site/branch_a/clients/active", data: try json([["ip": "192.0.2.10"]])),
            .init(path: root + "/stat/health", data: try json(["data": []])),
            .init(path: root + "/stat/session", data: try json(["data": []]), method: "POST"),
            .init(path: root + "/rest/dynamicdns", data: try json(["data": []])),
            .init(path: root + "/stat/portforward", data: try json(["data": []])),
            .init(path: root + "/stat/rogueap", data: try json(["data": []]), method: "POST")
        ])
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) }, localAddresses: { ["192.0.2.10"] })
        _ = try await client.fetchSelfV2()
        _ = await client.fetchWANHealth()
        #expect(await client.fetchSessionHistory(mac: "synthetic-mac")?.isEmpty == true)
        #expect(await client.fetchDDNSStatus().data?.isEmpty == true)
        #expect(await client.fetchPortForwards().data?.isEmpty == true)
        #expect(await client.fetchRogueAPs().data?.isEmpty == true)
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test(arguments: ["ambiguous", "missing-reference", "unsafe-reference", "duplicate-reference", "empty"])
    func invalidOrAmbiguousSiteCannotFallBackToDefault(scenario: String) async throws {
        let rows: [[String: Any]]
        switch scenario {
        case "ambiguous": rows = [site(reference: "branch"), site(Self.otherID, reference: "another")]
        case "missing-reference": rows = [["id": Self.siteID, "name": "default"]]
        case "unsafe-reference": rows = [site(reference: "../default")]
        case "duplicate-reference": rows = [site(), site(Self.otherID)]
        default: rows = []
        }
        let replay = Replay([.init(path: Self.sitesPath, data: try page(rows), offset: 0)])
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) })
        await #expect(throws: (any Error).self) { try await client.fetchSiteId() }
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test(arguments: ["offset", "count", "limit", "negative", "budget", "missing", "empty-page", "duplicate", "changing-total", "invalid-id"])
    func malformedOrIncompletePagesNeverBecomeSuccess(scenario: String) async throws {
        let path = "/proxy/network/integration/v1/sites/\(Self.siteID)/devices"
        var envelope: [String: Any] = ["data": [["id": "device-1"]], "offset": 0, "limit": 200, "count": 1, "totalCount": 1]
        switch scenario {
        case "offset": envelope["offset"] = 2
        case "count": envelope["count"] = 0
        case "limit": envelope["limit"] = 201
        case "negative": envelope["totalCount"] = -1
        case "budget": envelope["totalCount"] = 5_001
        case "missing": envelope.removeValue(forKey: "data")
        case "empty-page": envelope["data"] = []; envelope["count"] = 0
        case "invalid-id": envelope["data"] = [["id": "../bad"]]
        default: envelope["totalCount"] = 2
        }
        var steps = [Replay.Step(path: path, data: try json(envelope), offset: 0)]
        if scenario == "duplicate" || scenario == "changing-total" {
            steps.append(.init(path: path, data: try page([["id": "device-1"]], offset: 1,
                total: scenario == "duplicate" ? 2 : 3), offset: 1))
        }
        let replay = Replay(steps)
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) })
        await #expect(throws: (any Error).self) { try await client.fetchDevices(siteId: Self.siteID) }
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test func pageBudgetTerminatesEvenWithForwardProgress() async throws {
        let path = "/proxy/network/integration/v1/sites/\(Self.siteID)/devices"
        let steps = try (0..<100).map { index in
            Replay.Step(path: path, data: try page([["id": "device-\(index)"]], offset: index, total: 101), offset: index)
        }
        let replay = Replay(steps)
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) })
        await #expect(throws: UniFiError.self) { try await client.fetchDevices(siteId: Self.siteID) }
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test func aggregateByteBudgetRejectsIndividuallyValidPages() async throws {
        let path = "/proxy/network/integration/v1/sites/\(Self.siteID)/devices"
        let padding = String(repeating: "x", count: 8 * 1_024 * 1_024)
        let steps = try (0..<2).map { index in
            Replay.Step(path: path, data: try page([["id": "device-\(index)", "ignored": padding]],
                offset: index, total: 2), offset: index)
        }
        let replay = Replay(steps)
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) })
        await #expect(throws: UniFiError.self) { try await client.fetchDevices(siteId: Self.siteID) }
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test func selfSearchUsesEntireReturnedListAndDoesNotInventEthernet() async throws {
        var clients = Array(repeating: ["ip": "192.0.2.1"], count: 5_000)
        clients.append(["ip": "192.0.2.10", "ap_mac": "synthetic-ap"])
        let replay = Replay([
            .init(path: Self.sitesPath, data: try page([site()]), offset: 0),
            .init(path: "/proxy/network/v2/api/site/default/clients/active", data: try json(clients)),
            .init(path: "/proxy/network/v2/api/site/default/clients/active", data: try json([]))
        ])
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) }, localAddresses: { ["192.0.2.10"] })
        let info = try await client.fetchSelfV2()
        #expect(info.totalClients == 5_001)
        #expect(!info.isWired)
        await #expect(throws: UniFiError.self) { try await client.fetchSelfV2() }
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test func vpnInventoryUsesOfficialIDAndDoesNotInventDownStatus() async throws {
        let path = "/proxy/network/integration/v1/sites/\(Self.siteID)/vpn/site-to-site-tunnels"
        let replay = Replay([.init(path: path, data: try page([
            ["id": "tunnel-1", "name": "Synthetic tunnel", "type": "WIREGUARD", "metadata": [:]]
        ]), offset: 0)])
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) })
        let tunnels = try #require(await client.fetchVPNTunnels(siteId: Self.siteID))
        #expect(tunnels.first?.id == "tunnel-1")
        #expect(tunnels.first?.isConnected == nil)
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test func emptyOfficialCollectionIsDistinctFromMalformedData() async throws {
        let path = "/proxy/network/integration/v1/sites/\(Self.siteID)/devices"
        let replay = Replay([
            .init(path: path, data: try page([]), offset: 0),
            .init(path: path, data: Data(#"{"error":"unsupported"}"#.utf8), offset: 0)
        ])
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) })
        #expect(try await client.fetchDevices(siteId: Self.siteID).isEmpty)
        await #expect(throws: (any Error).self) { try await client.fetchDevices(siteId: Self.siteID) }
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test func olderCollectionsAreNotSilentlyTruncatedAtPresentationCaps() async throws {
        let root = "/proxy/network/api/s/default"
        let replay = Replay([
            .init(path: Self.sitesPath, data: try page([site()]), offset: 0),
            .init(path: root + "/stat/session", data: try json(["data": Array(repeating: ["duration": 1], count: 1_001)]), method: "POST"),
            .init(path: root + "/rest/dynamicdns", data: try json(["data": Array(repeating: ["status": "good"], count: 11)])),
            .init(path: root + "/stat/portforward", data: try json(["data": Array(repeating: ["enabled": true], count: 51)]))
        ])
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) })
        #expect(await client.fetchSessionHistory(mac: "synthetic-mac")?.count == 1_001)
        #expect(await client.fetchDDNSStatus().data?.count == 11)
        #expect(await client.fetchPortForwards().data?.count == 51)
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test func overBudgetOlderCollectionsFailInsteadOfReturningAPrefix() async throws {
        let many = try json(Array(repeating: ["ip": "192.0.2.1"], count: 10_001))
        let replay = Replay([
            .init(path: Self.sitesPath, data: try page([site()]), offset: 0),
            .init(path: "/proxy/network/v2/api/site/default/clients/active", data: many)
        ])
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) }, localAddresses: { ["192.0.2.1"] })
        await #expect(throws: UniFiError.self) { try await client.fetchSelfV2() }
        let legacy = try json(["data": Array(repeating: ["duration": 1], count: 5_001)])
        #expect(UniFiClient.decodeFlexibleArray(SessionDTO.self, from: legacy, endpoint: "synthetic") == nil)
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }

    @Test func cancellationAndInvalidationPreventRequestsEvenWithCachedSite() async throws {
        let replay = Replay([.init(path: Self.sitesPath, data: try page([site()]), offset: 0)])
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) })
        _ = try await client.fetchSiteId()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.fetchDevices(siteId: Self.siteID)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        await client.invalidate()
        await #expect(throws: CancellationError.self) { try await client.fetchSiteId() }
        #expect(await replay.remaining == 0)
    }

    @Test func deviceStatsSnapshotDerivesBothProjectionsFromOneRequest() async throws {
        let statsPath = "/proxy/network/integration/v1/sites/\(Self.siteID)/devices/synthetic-device/statistics/latest"
        let stats = try json([
            "uptimeSec": 3600,
            "cpuUtilizationPct": 12.5,
            "memoryUtilizationPct": 40.0
        ])
        let replay = Replay([.init(path: statsPath, data: stats)])
        let client = UniFiClient(fixtureTransport: { try await replay.fetch($0) })
        let snapshot = await client.fetchDeviceStats(deviceId: "synthetic-device", siteId: Self.siteID)
        #expect(snapshot?.apStats.cpuUtilizationPct == 12.5)
        #expect(snapshot?.apStats.memoryUtilizationPct == 40.0)
        #expect(snapshot?.gatewayStats.uptimeSec == 3600)
        #expect(await replay.remaining == 0)
        await client.invalidate()
    }
}
