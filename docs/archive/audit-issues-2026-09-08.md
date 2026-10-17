# Remaining audit issues — implementation follow-up

**2026-09-08.** The actionable source findings are fixed or mitigated below.
Native signing, supported-controller compatibility and end-to-end display QA
remain open; this is not an “all issues verified closed” or Mantis certification.

Continued the existing dirty worktree without reset, stash, commit, push or
installation. HEAD remains `0fede8a763ba09ac3bc204d993d1d962c89d7eb9`.
Artifacts: `.build/issues-20260908T132942Z-92576990/` (`STATE_ROOT` below).
The pre-edit inventory records SHA-256 and modes for 168 Git-visible repository
files. It identifies live-tree bytes, not an isolated or immutable snapshot.

## Finding dispositions

| Finding | Disposition and evidence |
| --- | --- |
| **F1: split credential writes** | Previous whole-record URL/key/trust-mode patch retained. Credential partial-write, legacy re-entry, cancellation and reset/restart regressions pass in the complete check. Native cross-process/power-loss guarantees are not inferred from these tests. |
| **F2: hidden storage/reset failure** | Previous fallible cleanup and persistent reset intent retained. Missing-entitlement credential failures now preserve specific signing guidance through `PreferencesManager.ResetError`: OSStatus `-34018` needs an appropriately signed build with access to the original records, not repeated unlocks. A fake missing-entitlement regression confirms failure remains visible, other cleanup still runs and automatic reconnect stays disabled. |
| **F3: lifecycle races** | Previous credential/reset admission and invalidation protections retained. Session, AP and gateway fetches now use structured child tasks, not detached-from-parent lifetime via `Task`. A regression confirms stopping polling cancels the in-flight session child. Existing generation/reset/cancelled-save tests still pass. |
| **F4: site mixing, truncation, hidden optional errors** | Contract-backed site identity, pagination and explicit data availability implemented; details below. Undocumented older-API server behavior and live controller compatibility remain verification gates. |
| **F5: diagnostic privacy** | Both existing copy paths redact by default. Controller/IP/SSID/AP/gateway/ISP/VPN identifiers, unknown standard/MIMO text, arbitrary error reasons and event text are omitted rather than regex-scrubbed. Typed metrics, authentication HTTP codes, event ordering/times/categories/levels and availability remain. Preferences has a warned, one-copy private-detail opt-in that resets after copying. Synthetic secret-marker regression failed before the change and passes now. |

## Data integrity corrections

- **Documented API contracts:** public Ubiquiti OpenAPI versions 9.1.120,
  9.5.21 and 10.4.57 establish singular `/proxy/network/integration`, site
  `id`/`internalReference` pairing and offset/limit pagination. The research
  agent used T3's browser and wrote
  [versioned primary-source findings](unifi-api-contracts-2026-09-08.md).
  No controller was contacted and no source was uploaded.
- **Site scope:** select the actual default site, wherever it occurs in the
  page sequence; otherwise accept exactly one visible site. Reject multiple
  non-default sites or invalid/duplicate older references. Official requests
  use its ID; all existing v2/legacy routes use its validated internal reference.
  There is no speculative alias fallback or site-picker UI.
- **Collections:** official sites/devices/VPN inventory traverse pages with
  at most 200 requested entries per page. Validate offsets, counts, limits,
  stable totals, unique safe IDs and forward progress. Budgets are 5,000 entries,
  100 pages and 16 MiB across each official collection. Malformed, repeated,
  changing or over-budget results fail rather than become empty or partial success.
- **Older lists:** remove silent 5,000-client search, 500-device, 1,000-session,
  10-DDNS and 50-port-forward prefixes. Active-client responses are searched
  completely up to a new explicit 10,000-entry ceiling; larger ones fail.
  Legacy collections fail above 5,000 entries. Nearby APs retain the intentional
  strongest-ten presentation and now say “top 10.” An unmatched Mac no longer
  becomes an invented Ethernet connection. Returned empty arrays remain distinct
  from request/decode failures.
- **Availability:** optional metrics clear when a new primary result starts
  their refresh, instead of appearing current under a fresh timestamp. The model
  records refreshing, available, empty, unavailable, disabled and inapplicable
  states. Existing menu/footer text and diagnostic export expose those states;
  disabled/inapplicable sources do not create menu warnings. No stale-data cache,
  new polling loop or notification subsystem was added.

These bounds are client policies, not proven production sizing thresholds or
process-memory limits. DTO decoding can allocate more than the input body size.
Older endpoints have no verified pagination contract here: no page parameters
were invented, and complete server-side coverage is not claimed. Even stable
official totals do not prove snapshot consistency while the controller changes.

## Other residuals addressed

| Issue | Change / remaining limit |
| --- | --- |
| Incorrect radio band | Removed channel-only 2.4/5 GHz inference. Channels and widths remain; no guessed v2 mapping for overlapping 6 GHz channels. Authoritative client-radio fields are still needed before restoring a band label. |
| Gateway classification | Honor the documented `gateway` feature even without a model name; retain existing compatibility checks. Synthetic JSON regression passes. |
| VPN schema | Use paginated `/vpn/site-to-site-tunnels` and official `id`. Missing/unrecognized live status is unknown, not down. Current official schema supplies configured inventory, not guaranteed runtime health; unsupported controller versions show unavailable. |
| Updater resource use | Reuse the existing bounded stream reader with a 1 MiB limit, ephemeral session and 30-second resource timeout. Existing backoff test now also covers oversized-response failure. Stream-boundary tests exercise the shared reader; no live GitHub streaming/TLS replay was performed. Controller requests also have a 30-second resource timeout. |
| Menu sizing / #15 | Setup/error/loading states no longer force full-screen height. Offscreen `NSHostingView` tests verify setup/error menus at width 320 with fake dependencies. Connected full/compact behavior is deliberately retained; actual display changes, scrolling, keyboard and VoiceOver remain unverified. This does **not** close #15. |
| Earlier feature proposals | Redacted export and minimal data-health reporting now exist. Site-picker UI, update controls/status, retained history and notifications remain proposals, not defects silently marked fixed or speculative features added during this pass. |

## Verification

All commands ran directly on this Mac, without a VM or execution sandbox.
XcodeBuildMCP tools were unavailable; existing SwiftPM/project scripts were used.
No real app was launched, stopped or installed; no real credential/pin service,
login item, controller or system trust setting was manipulated by this pass.
Offscreen menu hosting is a native layout measurement, not UI interaction.

| Check | Result / log under `STATE_ROOT` |
| --- | --- |
| New default-export regression before implementation | Expected failure: synthetic private marker leaked. `diagnostics-red.log` |
| Focused compile/test iterations | An initial VPN color-inference compile error and one obsolete generic-error-message expectation were corrected, not suppressed. `first-focused.log`, `second-focused.log` |
| Focused privacy/API replay tests | Passed. `contracts-first.log` |
| Focused lifecycle, preferences, model and offscreen-menu regressions | 125 tests / six suites reported passed at that revision. `focused-regressions.log` |
| Final `bash Scripts/check.sh` | **Exit 0; 192 tests / 14 suites reported passed**, portable fake-curl/bundle checks, release build, plist and ad-hoc signature verification passed. `check-full-final.log` |

`testResetAll()` is explicitly **skipped** because it unregisters the real login
item. The runner's aggregate count must not hide that skip. No compiler warning
or error appears in the final log; this was not a clean rebuild claim.

Prior direct-host native storage evidence remains in
`.build/native-security-20260908T151529-3685437f/summary.md`: seven scoped checks
passed, but the overall result was exit 2 because protected cleanup returned
`-34018`. That older native run was **not rerun or converted to success** here.
This pass improves guidance, not entitlements or inaccessible-backend certainty.

## Open verification gates and preservation

1. **Native signing/storage:** an appropriately signed build and access to the
   original backend are needed to verify protected cleanup. Do not invent a team
   or entitlement, suppress the error, or claim inaccessible records are absent.
   Cross-process/signing transitions, restart durability and power loss remain
   outside the synthetic regression guarantees.
2. **Controller/TLS:** obtain sanitized captures from supported versions for
   multi-site, pagination, older APIs, client-radio semantics and VPN inventory;
   verify actual TLS/pin continuity and native network/interface transitions.
3. **Native UI/stable OS:** complete the connected/compact/display/keyboard/
   VoiceOver and sleep/wake checks in `docs/development.md`, including stable
   macOS compatibility. Offscreen setup/error sizing does not replace these.

Formal Mantis reproduction, independent re-attack, calibration and security
certification were not performed. The installed suite's execution prerequisites
were not satisfied by running ordinary checks on this machine.

`preservation-final.json` records 147 of 168 baseline files unchanged, 21
intentionally edited files, no deleted baseline files or mode changes, unchanged
HEAD and all original Git-status paths retained. New files after that inventory
are three test files and this report; the research note was already inventoried.
Existing historical audit reports and all unrelated work remain intact. Build
artifacts are not covered by the source-file preservation claim.
