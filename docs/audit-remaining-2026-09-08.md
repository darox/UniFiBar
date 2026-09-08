# Remaining audit — direct-host implementation and verification

**2026-09-08.** Completed the feasible work in
[the remaining-audit prompt](remaining-audit-prompt.md), continuing the existing
dirty worktree. Two demonstrated defects were fixed: self-signed TLS policy was
bypassed by the per-task delegate, and compact menus exceeded short-screen height
budgets. Native storage, transport and real-view fixtures now have an opt-in runner.
**Protected Keychain cleanup, controller compatibility and full native/stable-OS
QA remain open. Issue #15 is not closed.**

## Evidence and environment

HEAD remains `0fede8a763ba09ac3bc204d993d1d962c89d7eb9`. This is a live-worktree
audit, not an immutable snapshot or execution-isolated campaign.

- [STATE_ROOT](../.build/remaining-audit-20260908T140704Z-fed0b6d7/): entry inventory
  of **173 Git-visible files**, status, hashes/modes, acceptance criteria,
  iteration logs and final preservation checks.
- [NATIVE_ROOT](../.build/remaining-native-04d25ebe-4550-4e92-b1df-e9a2ed9ff914/):
  final native run; `results.json` records commands, owned PIDs, timings and exit
  codes. All **37 hashed production/harness inputs** matched after execution and
  during final verification.
- Host: **macOS 27.0 (26A5425a)**, Apple Swift **6.4**, selected
  `/Applications/Xcode-beta.app/Contents/Developer`, macOS SDK **27.0**.
  The package's macOS 26 deployment target does not establish stable macOS 26
  runtime compatibility.
- XcodeBuildMCP tools were unavailable. Existing SwiftPM/project scripts and
  owned AppKit hosting provided the fallback. No browser interaction was needed;
  existing [versioned primary-source research](unifi-api-contracts-2026-09-08.md)
  was reused, not represented as new controller evidence.

The previous [finding dispositions](audit-issues-2026-09-08.md) remain historical;
the following tables update their remaining gates. Artifact links are local,
ignored `.build` evidence and must be retained separately if cleaning build output.

## A. Storage, signing and lifecycle

| Remaining item / acceptance criterion | Disposition | Current evidence and limit |
| --- | --- | --- |
| F1: native whole-record save/update/read/delete and accessible legacy cleanup | **Verified unchanged** | Production `KeychainHelper` and `PreferencesManager` pass synthetic native save, update, readback and cleanup. A deliberately injected update error preserves the existing native record. No credential source changes in this pass. |
| F1/F3: competing processes and restart retain coherent credentials/pins | **Verified unchanged** | Separate fixture processes restore URL/key/trust mode and a persisted pin. Two pin writers produce one winner and one conflict; independent read confirms one whole pin. Credential writers leave one coherent URL/key/trust record, not a split pair. This is bounded fixture evidence, not cross-process serialization or power-loss durability. |
| F2: persistent reset intent blocks reconnect after interrupted cleanup | **Verified unchanged** | One fixture process exits before its gated cleanup starts. The next finds the leftover synthetic credential but does not reconnect. Explicit save clears intent; subsequent scoped reset removes accessible records and reports protected cleanup failure. Existing fake lifecycle/cancellation/reset regressions also pass. |
| F2: protected-backend access and complete cleanup | **Blocked by a named prerequisite** | `storage-cleanup.log` retains protected deletion **`-34018`** and the runner exits **2**. Requires an explicitly configured usable signing identity/build with access to the relevant protected records. An inaccessible backend is not proven empty, even when a read returns item-not-found. |
| Signing/backend transitions and power-loss durability | **Blocked by a named prerequisite** | Requires an authorized signing-transition fixture setup and separately authorized durability testing. Neither an ad-hoc build nor graceful fixture-process exit verifies these behaviors. No host power, sleep or signing changes were performed. |

### Actual signing result and cleanup

`Scripts/package_app.sh` signs with `codesign --force --sign -`. The final bundle
has `Signature=adhoc`, `TeamIdentifier=not set` and no embedded entitlements from
`codesign -d --entitlements -`. `build_common.sh` merely copies
`UniFiBar.entitlements` into Resources; its `$(AppIdentifierPrefix)` placeholder
does not configure an identity or grant access. No usable identity is configured
by this packaging path; no identity or key was imported or selected speculatively.
Ad-hoc signature verification passed, but that is not protected-Keychain access.

The source-fixable part of F2 was already implemented: preserve the error, give
signing guidance, continue other cleanup and retain reset intent. That remains
verified. Removing the protected-backend query, changing its attributes or
ignoring `-34018` would conceal the missing prerequisite, not fix access.

Every native Security operation passes through `NativeScope`: original class,
service and predeclared account are validated, then **both service and account**
receive the run UUID. Backend/accessibility/matching attributes stay intact.
Service-wide pin cleanup expands into exact known accounts before any native
delete. The protected and legacy credential queries retain their true/false
data-protection flags; pin queries retain the production default backend.

The final run's ten storage behavior commands exited 0. One credential writer
verified its save; the other visibly reported **`errSecDuplicateItem (-25299)`**.
The harness permits a native duplicate or readback rejection for a competing
writer and requires a verified winner plus an independent coherent-record read.
It does not suppress production errors, claim every save succeeds, or promise
rollback after commit/readback failure.

Final cleanup found no accessible credential or pin records; protected deletions
still failed for each exact credential account. Scoped defaults had no remaining
values; Foundation may retain an empty domain. Process-local Keychain interaction
was restored with status 0. These observations concern synthetic namespaces only,
not the original application records. Earlier iteration cleanup failures remain
in their logs and are not converted into success by this final run.

## B. Controller contracts and real transport

| Remaining item / acceptance criterion | Disposition | Current evidence and limit |
| --- | --- | --- |
| Self-signed TLS acceptance, continuity and mismatch detection through the actual task delegate | **Fixed and verified** | Real loopback handshakes failed before the fix and pass afterward. Task authentication now forwards to the same existing `PinnedCertDelegate`. `taskDelegatePreservesCertificatePolicy` covers valid, expired and replacement certificates with fake storage. |
| Redirect, certificate rejection, cancellation, timeout and stream-size boundaries | **Verified unchanged** | All **16** final real URLSession/TLS cases exit 0. Same-origin redirect succeeds; cross-origin/downgrade are rejected. Host/date/default-trust rejection, pin mismatch, chunking, exact/over-limit sizes, declared length, cancellation and timeout have current native evidence. |
| F4: collection byte budgets, site identity and explicit availability | **Verified unchanged** | New aggregate regression rejects two individually valid approximately 8 MiB pages exceeding the 16 MiB collection budget. Existing synthetic tests cover paired sites, pagination, malformed/empty/over-limit responses and optional-source recovery. Native views display unavailable/refreshing states and unknown VPN health. |
| Supported-controller versions, older APIs, v2 radio fields, VPN runtime health and real deployment sizes | **Blocked by a named prerequisite** | No exact controller target/access/read-only scope or sanitized captures were supplied. Contracts for 9.1.120, 9.5.21 and 10.4.57 are documentation evidence, not runtime validation. The earlier legacy/VPN/radio unknowns remain. |
| Live updater networking and physical network/interface transitions | **Mitigated but unverified** | Fake updater checks and the shared reader's native fixtures pass. No live GitHub/update transport, interface disruption or real controller transition was exercised. |

### TLS root cause and scope

`UniFiClient.request` supplies `SameOriginRedirectDelegate` to
`session.bytes(for:delegate:)`. Its default task-authentication handling did not
forward to the session's pinning delegate: valid synthetic self-signed certificates
failed with `NSURLErrorDomain/-1202`, and mismatch state was not set. The shared
task delegate now forwards challenges to the existing pinning policy when present;
normal TLS retains default handling. Certificate identity/date/persistence rules
and same-origin redirect checks were not relaxed.

Before/after evidence: `STATE_ROOT/native-transport-first.log`,
`native-transport-second.log`, and final `NATIVE_ROOT/transport-*.log`.
Final mismatch sets `certChanged=true`; invalid certificates receive no HTTP
requests. Pin continuity in the TLS group uses an in-memory store with a fresh
delegate/session. Actual Keychain persistence is verified separately in group A,
not claimed as one end-to-end persisted TLS test.

Fixtures bind only `127.0.0.1`, disable fixture proxy use, use synthetic certificates
and per-session trust, and send only `synthetic-loopback-only` as the API key.
The reader boundary is 1 KiB with 2/4-second fixture timeouts, not a measured
production memory limit. `loopback.json` records all four listeners closed,
no requests to the cross-origin sink or invalid-certificate servers, and unchanged
synthetic keys on valid requests. Generated private-key files were removed.

Understated `Content-Length` yielded the declared four bytes in Foundation;
discarded trailing bytes are framing evidence, **not a valid JSON/controller
success**. A provisional cancellation change was removed after a differential
showed both production variants cancel correctly once the fixture supplied a
content type and enough bytes to avoid MIME-sniff buffering. See
`STATE_ROOT/cancel-differential/results.json`. No cancellation bug fix is claimed;
`boundedResponseData` and `ResponseLimitTests.swift` retain their entry behavior.

No endpoint aliases, legacy pagination parameters, guessed radio-band mappings,
VPN health inference or speculative site-picker functionality were added.

## C. Native views, accessibility and compatibility

| Remaining item / acceptance criterion | Disposition | Current evidence and limit |
| --- | --- | --- |
| Connected compact/full sizing within short/tall budgets | **Fixed and verified** | Offscreen compact sizing was **392 pt for a 360 pt budget**. Both connected modes now have a maximum height; full mode also uses it as a minimum. Parameterized full/compact regressions pass at 360/600/1000 pt. Setup/loading/error remain naturally sized. |
| Real-view content, scrolling and footer bounds | **Verified unchanged** | Final native fixture covers eight menu states: setup, loading, error, connected full/compact/tall/empty/unavailable. It hosts actual scroll views, scrolls content, captures fixtures and checks all three footer buttons' labels/roles/visible bounds. This does not exercise the actual MenuBarExtra popover. |
| Diagnostic control labels and subsection readability | **Fixed and verified** | Diagnostic switches have explicit accessibility labels; the private-detail switch is found and operated by label. Shared subsection headings use `.secondary` instead of nearly invisible `.quaternary`. Final dark fixture captures were visually inspected. Full VoiceOver and contrast-compliance claims are not made. |
| F5: both real copy actions redact by default; private details require one-copy opt-in | **Verified unchanged** | Real menu and DiagnosticsSection actions write only to an injected sink. Default copies omit the synthetic private marker; explicit opt-in includes it; the next copy is redacted again. The shared production default still writes to the clipboard; that backend was deliberately not invoked. |
| #15, full Setup/Preferences interactions, keyboard/VoiceOver, display and stable-OS QA | **Blocked by a named prerequisite** | Requires native product QA on stable macOS 26, actual short/tall displays and transitions, physical keyboard/VoiceOver, authorized controller and lifecycle checks. Programmatic fixture focus is only partial evidence. Full Setup/Preferences were not instantiated because their dependencies can create real clients or operate the login item. |

Native menu width is **320 pt**. Setup/loading/error measured **193/101/187 pt**;
short connected views measured **360 pt**, and tall full mode **900 pt**. The
long-content scroll document was **894 pt** with **307/847 pt** viewports. Actual
screen visible sizes were read as 1920×1050 and 1512×949 points; no display was
changed. `NATIVE_ROOT/ui.log` records these measurements and cleanup.

The fixture owns its AppKit windows, never activates them, and captures only
`NSHostingView` content, not the desktop. Programmatic native-switch focus
succeeded without global input. External accessibility trust was observed **true**;
missing permission is not the blocker reported here. Process-local accessibility
traversal does not establish actual keyboard navigation or spoken VoiceOver output.
Owned windows closed and the fixture defaults domain had no values afterward.

Inspected final images: `connected-full-scrolled.png`, `connected-compact.png`,
`connected-unavailable-scrolled.png`, and `diagnostics.png` under `NATIVE_ROOT`.
Before/after compact sizing is in `STATE_ROOT/focused-ui.log` and `layout-green.log`.
Dark fixtures demonstrate improved heading visibility, not exhaustive appearance,
localization, contrast or accessibility validation.

## Verification, preservation and next gates

| Final command/check | Result / evidence |
| --- | --- |
| `bash Scripts/check.sh` | **Exit 0; runner reports 195 tests / 14 suites passed**, portable bundle/probe checks, release build, plist and ad-hoc signature verification. `STATE_ROOT/check-final.log` and `.exit`. |
| `python3 Tests/NativeAudit/run.py --run-synthetic-native-checks` | **Exit 2**, solely for protected cleanup; `results.json` has no test failures. Sixteen transport cases and the UI group exit 0; ten storage behavior commands exit 0. `STATE_ROOT/native-final.log` and `.exit`; detailed commands/logs in `NATIVE_ROOT/results.json`. |
| Final signature, source and owned-resource inspection | Signature metadata/strict verification exit 0; no recorded fixture PIDs remain (`ps` exits 1 with no matches); listeners closed; no generated private keys remain; all native input hashes match. `STATE_ROOT/final-native-resource-signature-check.json`. |
| Diff whitespace, all untracked text files and Python AST parse | Exit 0; includes new harness/report files without creating `__pycache__`. Commands and outputs in `STATE_ROOT/final-static-checks.json`. |
| Entry/final preservation inventory | `STATE_ROOT/preservation-final.json`, `final-files.json`, `final-status.txt` and `final-head.txt`. |

`testResetAll()` is explicitly **skipped**, because it unregisters the real login
item; the runner's aggregate count must not conceal that skip. The final ordinary
check has no compiler warnings/errors, but was incremental, not a clean rebuild.
Native compilation reports four deprecated API call sites: three process-local
Keychain interaction calls and the process-local accessibility attribute setter.
These warnings remain visible in `NATIVE_ROOT/compile.log`. An earlier focused
build also reported a pre-existing redundant `#require(strdup(...))` warning;
earlier harness compile/AX failures are retained as iteration evidence, not
misclassified as additional production defects.

Of **173** entry files, **164** are byte-identical and **nine** intentionally
changed: `UniFiClient`, `DiagnosticsLog`, `SectionHeader`, `MenuContentView`,
`PreferencesView`, `CertificatePinTests`, `MenuLayoutTests`, `UniFiClientTests`,
and `docs/development.md`. There are no entry-file deletions or mode changes.
Six new files are the five `Tests/NativeAudit/` files and this report. HEAD and
all original dirty status paths are preserved; historical reports are unchanged.
Build artifacts are outside that source-preservation claim.

No VM/container/account/worktree isolation, real app launch/termination/install,
real credential/pin/preferences access, controller discovery, login-item action,
system trust/clipboard change, dependency installation, Git reset/clean/stash,
commit/push or GitHub publication/closure was performed. Exact synthetic
namespaces protect user data; they do not meet formal Mantis execution
prerequisites. Formal reproduction, independent re-attack, calibration and
`VERIFIED_SECURE` certification were **not performed or claimed**.

The smallest next actions are:

1. **Signing/storage:** provide an explicitly configured usable signing identity
   and authorized access to the protected records; rerun scoped native storage
   and signing-transition checks. Do not interpret repeated `-34018` as success.
2. **Controller compatibility:** provide sanitized version-labelled captures,
   or an exact authorized target/access method/read-only scope. Needed evidence:
   paired sites and first/middle/last/empty official pages on 9.1.120, 9.5.21 and
   10.4.57; older active-client/device/session/monitoring shapes and truncation
   behavior; v2 radio fields; VPN inventory/absent health; large/multisite results.
3. **Release UI/lifecycle:** complete [native QA](development.md#debug-and-end-to-end-qa)
   on stable macOS 26 with actual MenuBarExtra, short/tall screens and display
   changes, keyboard/VoiceOver, authorized setup/reconnect and physical
   sleep/network transitions. Retain before/after screenshots and platform data;
   keep #15 open until its full acceptance criteria pass.
