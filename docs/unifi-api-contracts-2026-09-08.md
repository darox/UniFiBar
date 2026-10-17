# UniFi API contracts checked for the local audit

**Checked:** 2026-09-08. **Scope:** public Ubiquiti documentation, not a live
controller capture. Used T3's browser to read the documentation and its linked
OpenAPI JSON. No controller requests, credentials, source uploads or remote Git
operations were used. Examples below are synthetic and contain no real network
identifiers.

## Sources

| Ref | Primary source |
| --- | --- |
| S1 | [Network 10.4.57 OpenAPI](https://developer.ui.com/network/v10.4.57/openapi.json), fetched successfully (HTTP 200) |
| S2 | [Network 9.1.120 OpenAPI](https://developer.ui.com/network/v9.1.120/openapi.json), fetched successfully (HTTP 200) |
| S3 | [Network 9.5.21 OpenAPI](https://developer.ui.com/network/v9.5.21/openapi.json), fetched successfully (HTTP 200) |
| S4 | [10.4.57 List Local Sites](https://developer.ui.com/network/v10.4.57/getsiteoverviewpage), including its Local connection cURL example |

The unversioned [Network documentation](https://developer.ui.com/network)
redirected to 10.4.57 during this inspection. These are versioned contracts as
served on the checked date, not promises about every deployed controller.

## Confirmed: official API prefix and site identity

1. **The documented prefix is singular:** `/proxy/network/integration`.
   S1, S2 and S3 all declare the local server as
   `https://{consoleIP}/proxy/network/integration`; S4's local cURL example appends
   `/v1/sites`. The repository's `/proxy/network/integrations/v1/...` spelling is
   not supported by these sources. No plural alias was verified.
2. **Official and older site identifiers are different fields.** In all three
   specifications, `Site overview` requires `id`, `internalReference` and `name`.
   `id` has UUID format; `name` is the display string. `internalReference` is
   described exactly as **“Internal unique name of the site used in older
   APIs”**. Official `/v1/sites/{siteId}/devices` declares its `siteId` path
   parameter as a UUID. Use the official ID for official paths, not the display
   name. Sources: S1–S3, `Site overview` and the devices GET operation.
3. **First site is not guaranteed to be the default site.** S2's sites operation
   says Multi-Site setups return all created sites; when Multi-Site is disabled,
   it returns just the default site. None of the inspected sites operations
   promises ordering or that the first entry is the default. Sources: S1–S3,
   `GET /v1/sites`.

**Implementation implication, not a new API guarantee:** cache the selected
official `id` and its corresponding validated `internalReference` together.
Do not combine a first-page official ID with hard-coded `default` requests to
other API families. A site-selection policy must be explicit; ordering is not
a selection contract. Reject unsafe path segments rather than interpolating
unchecked controller strings.

**Limit:** the field description establishes the bridge to older API names,
but these public specs do not enumerate `/proxy/network/v2/api/site/...` or
`/proxy/network/api/s/...`. Their exact route/response contracts and compatibility
across releases remain unverified here. Applying `internalReference` to the
repository's existing older routes is a source-backed identity correction,
not proof of every legacy endpoint's support.

## Confirmed: sites and devices are paginated

S1–S3 define `GET /v1/sites` and `GET /v1/sites/{siteId}/devices` as paginated.
Their query parameters have these bounds:

| Parameter | Contract |
| --- | --- |
| `offset` | Optional, default `0`, minimum `0`, `int32` |
| `limit` | Optional, default `25`, minimum `0`, maximum `200`, `int32` |

Both response envelopes require **`count`, `data`, `limit`, `offset`,
`totalCount`**. `data` is an array; `count` and `limit` use `int32`; `offset` and
`totalCount` use `int64`. S1 explicitly adds integer schema types; S2/S3 retain
the same formats/bounds. Relevant schemas are `Site overview page` and
`Adopted device overview page` in S1; S2 calls the device schema
`Device overview page`.

**Synthetic schema-shaped example. Not captured controller output.**

```json
{
  "offset": 0,
  "limit": 25,
  "count": 1,
  "totalCount": 1,
  "data": [
    {
      "id": "11111111-1111-4111-8111-111111111111",
      "internalReference": "default",
      "name": "Example site"
    }
  ]
}
```

**Implementation implications:** explicitly send a positive limit no greater
than 200; read all required pages within a deliberate total/page budget; check
nonnegative metadata, expected offset, count/data agreement and forward
progress. Do not report a truncated first page or a decode failure as a complete
empty list. A repeated/malformed page or exhausted budget must surface as an
incomplete/error result rather than looping or publishing false completeness.
These checks are defensive client policy, not additional server guarantees.

The inspected schema does not document snapshot consistency, stable ordering
under concurrent changes or cursor semantics. It also does not grant pagination
support to the repository's unlisted v2/legacy routes. No query parameters were
invented for those routes.

## Confirmed adjacent schema mismatches

These were visible while checking the same official source (S1):

| Area | Public contract | Consequence for the existing model |
| --- | --- | --- |
| Gateway detection | `Adopted device overview.features` contains the enum values `switching`, `accessPoint`, `gateway` | Honor explicit `gateway`, not only `wan` or model-name guesses |
| VPN collection | `GET /v1/sites/{siteId}/vpn/site-to-site-tunnels`, paginated with the same bounds/envelope | `/vpn/tunnels` was not found in the inspected official spec |
| VPN status | `Site-to-site VPN tunnel overview` requires `id`, `metadata`, `name`, `type`; its base schema has no live `status` | A missing status is **unknown**, not proof that a tunnel is down; configured-tunnel inventory is not runtime-health evidence |

The VPN details above describe 10.4.57. Backward compatibility or live-state
availability in older firmware was not established. Changing a path alone must
not turn absent status fields into fabricated disconnection results.

## Not established: v2 client radio-band contract

The S1 official `Wireless client overview` and `Wireless client details` schemas
do not document the repository's v2 `radio` or `radio_proto` fields. The official
device `Wireless radio overview` and `Latest statistics for wireless radio`
schemas instead use `frequencyGHz` with enum values **2.4, 5, 6, 60**. Those are
device-radio contracts, not a documented mapping for v2 active clients.

No authoritative mapping for v2 client values such as `ng`, `na` or `6e` was
established by these sources. Do not cite them as validation for a guessed
mapping, or treat a channel-number-only heuristic as authoritative frequency
data. A captured, sanitized supported-controller fixture or first-party v2
schema is still needed before claiming that contract is verified.
