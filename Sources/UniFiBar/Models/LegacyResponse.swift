import Foundation

/// Envelope for legacy UniFi API responses shaped as `{ "meta": { "rc": "ok" }, "data": [...] }`.
/// Used by DTO decoders and by UniFiClient.decodeFlexibleArray.
struct LegacyResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let data: [T]?

    private enum CodingKeys: String, CodingKey { case data, meta }
    private struct Metadata: Decodable { let rc: String }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let meta = try container.decodeIfPresent(Metadata.self, forKey: .meta), meta.rc != "ok" {
            throw DecodingError.dataCorruptedError(forKey: .meta, in: container,
                debugDescription: "Legacy response did not report success")
        }
        // An explicit null is empty; a missing data key is not a successful response.
        data = try container.decode([T]?.self, forKey: .data)
    }
}
