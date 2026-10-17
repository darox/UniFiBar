# Finish audit — implementation and verification

**2026-09-08. All feasible local work complete; release is not cleared.**
Executed [the finish prompt](finish-audit-prompt.md) in the existing dirty checkout.
Fixed two demonstrated production defects and a native-fixture cleanup gap.
Protected Keychain access, real-controller compatibility and stable-OS/product QA
remain open. GitHub issue **#15 is still OPEN**, confirmed by a read-only query;
no issue was published, changed or closed.

## Evidence and environment

- **STATE_ROOT:** [`.build/finish-audit-20260908T150750Z-4804aedb/`](../.build/finish-audit-20260908T150750Z-4804aedb/).
  Entry inventory: **180 Git-visible files**, hashes/modes, HEAD and dirty status.
- **NATIVE_ROOT:** [`.build/remaining-native-6a815fc8-8fc8-46a7-8fee-4e93977c96b3/`](../.build/remaining-native-6a815fc8-8fc8-46a7-8fee-4e93977c96b3/).
  Final `results.json` records **36 commands**, PIDs, timings and exits; all
  **37 production/harness input hashes** match the final source.
- HEAD remains `0fede8a763ba09ac3bc204d993d1d962c89d7eb9`.
  Actual host: **macOS 27.0 (26A5425a), Swift 6.4, Xcode-beta, macOS SDK 27.0**.
  This is not stable macOS 26 testing.
- XcodeBuildMCP tools were unavailable; existing SwiftPM scripts and owned AppKit
  fixtures were used. No browser interaction was needed. Versioned API research
  was reused as documentation, not new controller evidence.

Artifact links are local ignored build output; retain them separately before
cleaning `.build`. Historical reports, findings and IDs remain unchanged.

## Changes and before/after evidence

### 1. Explicit legacy API errors no longer publish successful monitoring

`LegacyResponse` previously ignored `meta`, accepting an error envelope with
empty, null or populated `data`. WAN health had a separate decoder with the same
problem: plausible WAN data could become healthy despite `meta.rc: "error"`.

The existing shared envelope decoder now validates metadata; WAN reuses it.
Non-null `meta` must contain string `rc: "ok"`. Error/unknown codes and malformed
metadata, including missing/null/wrong-type `rc`, fail closed. Absent/null metadata
remains accepted. Flexible endpoints retain bare arrays and explicit-null success
handling. WAN now accepts null data internally as an empty list, but its public
result remains unavailable because no WAN/WWW entry exists.

- **Red:** `legacy-envelope-red.log`, exit 1: **14 failing assertions across two
  tests**, before the production edit.
- **Green:** `legacy-envelope-green.log`, exit 0: **24 tests / two suites**.
  Nine success/error/unknown × empty/null/populated combinations plus public
  WAN, session, DDNS, port-forward and nearby-AP fetches use synthetic transport.
- `legacy-envelope-preedit.json` and `legacy-envelope-snippet.patch` identify the
  exact transition, without attributing earlier dirty-tree changes to this pass.

This closes a demonstrated **F4 parser-policy gap**, not a proven live-controller
exploit or a new version-specific contract. Routes, pagination, limits and unknown
radio/VPN semantics were not changed.

### 2. Failed login-item changes no longer trigger another operation

The actual Preferences toggle observed all state changes with `onChange`, including
rollback after failure. A fake successful disable followed by a rejected enable
produced calls **`[false, true, false]`**, not the intended `[false, true]`.

An explicit `Binding` setter now performs user-requested operations; loading and
rollback only update state. The initialization flag was removed. Opening the form
with login already enabled was separately tested and **did not** cause a write;
that initial suspicion was not a defect.

- **Red:** `ui-forms-fourth.log`; relevant pre-edit text/hash in
  `login-rollback-preedit.json`.
- Independent review rejected an intermediate Boolean-status guard: not-enabled
  can mean registered but requiring approval, so an intentional off action must
  still unregister. `ui-forms-sixth.log` reproduced that guard's failure; it was
  replaced, not retained.
- Final native checks confirm no load-time operation, intentional off despite
  changed observed state, one rejected enable, restored off-state, and no deferred
  duplicate operation after subsequent form rendering. **All operations are fake**;
  no real ServiceManagement registration/status behavior was exercised.

### 3. Real form coverage and timeout cleanup

Minimal defaulted dependencies let fixtures host the actual Setup and Preferences
views: client creation, and Preferences login-item status/setter and clipboard
output. Production defaults remain real native implementations; normal app call
sites supply no overrides. No parallel UI implementation or new dependency exists.

The extended native fixture verifies empty submission is disabled, HTTP URLs fail
before client creation, normalized HTTPS URL/trimmed synthetic key/trust choice
reach the offline factory, and 401 validation displays the real error without
persisting credentials. It also verifies compact-mode persistence and full
Preferences redacted copy. Existing menu and DiagnosticsSection actions retain
default redaction and one-copy private opt-in/reset.

Harness iterations exposed native AX-wrapper/field differences and an invalid
generic AX-value conversion. These were fixture problems, not product accessibility
findings. Final lookup honors title-element labels, selects a unique owned native
field, and reads string values only from static text. Tests use native control
actions/delegate notifications, never global input.

Two timed-out fixture processes left their **synthetic** compact-mode defaults.
The runner now always invokes exact UUID-scoped UI cleanup in a separate owned
command after UI success, failure or timeout, preserving both test and cleanup
failures. `ui-timeout-cleanup-preedit.json` records the leftovers; the new command
removed both (`ui-timeout-cleanup-green.json`). Final automatic cleanup passes.
This does not guarantee cleanup if the whole runner or host terminates.

## Remaining acceptance matrix

`acceptance-final.json` in STATE_ROOT records evidence and the next action for
each original matrix row.

| Row | Disposition | Verified scope / remaining requirement |
| --- | --- | --- |
| **S1 — native storage and cleanup** | **Mitigated but unverified** | Ten storage behavior invocations pass using production implementations and exact synthetic service **and account** scopes, retaining backend/query attributes. Whole-record save/update/read, accessible legacy cleanup, pin/credential races, restart and reset intent pass. Protected cleanup still returns **-34018**; requires an explicitly selected usable entitled signing setup with authorized access to the relevant records. |
| **S2 — signing transitions/durability** | **Blocked by a named prerequisite** | Requires authorized signing identities/transition setup and a separately authorized durability environment. Graceful fixture-process exit is not power loss. |
| **N1 — TLS and parser policies** | **Fixed and verified** | New envelope regressions pass; all **16** existing native URLSession/TLS cases pass unchanged, covering trust, continuity/mismatch, redirects, cancellation/timeouts and stream boundaries. Synthetic collection/site/availability checks pass. |
| **N2 — controller compatibility** | **Blocked by a named prerequisite** | No exact controller target/access/read-only scope or version-labelled sanitized captures supplied. Need paired sites/pages, older client/device/session/monitoring shapes, v2 radio fields, VPN inventory/unknown health and large/multisite responses. 9.1.120, 9.5.21 and 10.4.57 are documented contracts, not tested deployments. |
| **U1 — safe full-form fixtures** | **Fixed and verified** | Actual Setup/Preferences and the listed form, login-toggle, compact-setting and copy actions pass with safe dependencies. This is not every product action or successful live setup; those remain in U2. |
| **U2 — #15 and release UI/lifecycle** | **Blocked by a named prerequisite** | Requires stable macOS 26, actual MenuBarExtra, short/tall displays and transitions, physical keyboard/VoiceOver, authorized successful setup/reconnect and sleep/network QA. Beta-host fixtures and programmatic focus cannot close this row. |
| **M1 — F1–F5 review/certification** | **Mitigated but unverified** | Independent current-source review and final patch/harness review completed. No current F1/F2/F3/F5 bypass demonstrated; F4's new parser gap fixed. Missing original formal finding records/baselines and independent diverse re-attack prevent formal certification. |
| **V1 — checks/preservation/resources** | **Fixed and verified** | Final ordinary/native execution, hashes, whitespace, harness syntax, scoped UI cleanup and preservation recorded. Protected storage incompleteness stays in S1; it is not hidden by this row. |

### Storage and transport qualifications

Packaging still signs ad-hoc: `TeamIdentifier=not set`, no embedded entitlements.
Copying `UniFiBar.entitlements` to Resources does not grant protected access.
No usable identity was explicitly selected, so no invented team/access group or
signing change was made. Signature verification is not Keychain authorization.

One final credential writer verified its save; the competing writer visibly
reported **-25299 / duplicate item**. Independent read confirmed a coherent record.
A failed save can already have committed a coherent record; neither rollback nor
cross-process serialization is promised. Accessible credentials/pins were absent
after scoped cleanup. Each protected credential deletion still returned -34018;
item-not-found reads do not make that inaccessible backend proven empty. Signing
success in a synthetic namespace would not establish access to original records.

Native TLS tests use loopback, synthetic keys/certificates and in-memory pins;
native persistence is tested separately. They exercise production delegates and
the stream reader with 1 KiB limits and 2/4-second timeouts, not a real controller
or a measured production memory ceiling. All four listeners closed; invalid-cert
and redirect-sink servers received no requests; generated private keys were removed.
Live updater networking and physical network/interface transitions remain unverified.

### Native visual scope

Eight menu states retain visible, labelled footer controls. Connected short views
measure 320×360 pt and the tall full view 320×900 pt. Full Preferences is hosted at
480×900 pt; Setup at 420×480 pt. Owned-window programmatic switch focus succeeds;
external AX trust was observed true, without prompting or changing permission.

Inspected final `connected-compact.png`, `connected-full-scrolled.png`,
`preferences-error.png` and `setup-form-error.png`. Menu/footer and form error text
are visible. Setup's offscreen bitmap does **not** show all native button glyphs,
despite successful label/action checks; no pixel-complete appearance or contrast
approval is claimed. Preferences content extends below its viewport. These are
view-local captures, not desktop screenshots or actual MenuBarExtra evidence.

## Final checks and preservation

| Check | Actual result |
| --- | --- |
| `bash Scripts/check.sh` | **Exit 0; 197 tests / 14 suites reported passed**, portable bundle/probe checks, release build, plist and ad-hoc signature verification. `check-final.log` / `.exit`. |
| `python3 Tests/NativeAudit/run.py --run-synthetic-native-checks` | **Exit 2** for protected cleanup only; `results.json` has no test failures. Ten storage behavior calls, sixteen transport cases, UI and separate UI cleanup exit 0. `native-final.log` / `.exit`. |
| Resource/signature/provenance checks | All 37 native hashes match. No recorded owned PIDs remain across **59 recorded native commands**; all **13** owned UI-run domains checked. Earlier timeout defaults removed; no synthetic TLS private keys remain. `final-native-resource-signature-check.json`, `all-owned-processes-check.json`, `all-owned-ui-defaults-check.json`. |
| Static and preservation checks | Diff whitespace including untracked files, Python AST parse without bytecode generation, final hashes/modes/status and historical report preservation recorded in `final-static-checks.json` and `preservation-final.json`. |

`testResetAll()` is explicitly **skipped** because it unregisters the real login
item; the aggregate count must not conceal that skip. Final ordinary output has
no compiler warnings/errors and is not a clean-build claim. Native compilation
retains four deprecated call sites: three process-local Keychain interaction calls
and the process-local AX attribute setter. Intermediate compiler warnings, lookup
failures and two UI timeouts remain in iteration logs, not counted as final passes.

Of 180 entry files, **170 are byte-identical and 10 intentionally changed**:
`DeviceDTO`, `UniFiClient`, `PreferencesView`, `SetupView`, native `Main.swift`,
`UI.swift`, `run.py`, both envelope/client regression files, and `development.md`.
This report is the sole added Git-visible file. No entry file was deleted or had
its mode changed; HEAD and original dirty paths are preserved.

## Mantis outcome and handoff

The installed symlink-resolved skills and shared `CODEX_EXECUTION.md` permit safe
Codex-local review/reproduction/patching without VM/container/source-copy or external
model infrastructure. The obsolete isolation prerequisite in historical reports
does not apply to this run. Policy hashes are in `skill-provenance.json`.

`independent-review.json` records the coordinating writer's faithful summary of
the native read-only review, including final reviewed hashes and the rejected
intermediate guard. The reviewer ran no tests or state writes. No formal finding
JSONs existed to update, and no formal reproduction, calibration, exploit-chain
packet or independent re-attack verdict is fabricated. **No `VERIFIED_SECURE`
claim**: its required baseline/benign/original-input and fresh independent diverse
variant evidence is not supplied for the previous findings. Nothing certifies the
whole application; already-fixed code was not reverted to manufacture evidence.

No isolation environment, source-tree copy, dependency installation, real credential
lookup, controller discovery, login-item operation, clipboard/system-trust change,
installed-app operation, host power/network disruption, Git reset/clean/stash,
commit/push or GitHub mutation was performed. Only synthetic fixture namespaces
were modified; release artifacts were rebuilt in `.build`.

The remaining handoff is bounded:

1. **Signing/access:** select an already usable entitled identity and authorize
   the precise protected-record/transition test setup. Do not send secrets in chat.
2. **Controller evidence:** provide version-labelled sanitized response captures,
   or an exact target/access method/read-only scope covering N2's listed payloads.
3. **Release QA:** provide stable macOS 26 and authorize the actual product/display,
   keyboard/VoiceOver and lifecycle checks in [development.md](development.md#debug-and-end-to-end-qa).
   Keep #15 open until matching native evidence exists.

No additional continuation prompt or speculative feature backlog was created.
