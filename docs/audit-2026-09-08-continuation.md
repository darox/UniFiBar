# Audit continuation — 2026-09-08

Status: **complete for this bounded local remediation pass**.
Credential atomicity, contract-dependent API work and native verification remain
open as detailed below; this is not a claim that all project risks are resolved.
Scope: the remaining queue in `docs/unattended-audit-prompt.md`, not a new
whole-repository audit. All changes remain local and uncommitted.

## Entry state and baseline

- HEAD: `0fede8a763ba09ac3bc204d993d1d962c89d7eb9`, unchanged this pass.
- Preserved all 82 first-party tracked/untracked entry files under ignored
  `.build/continuation-2026-09-08-entry/`, with SHA-256 manifest, status, HEAD
  and cumulative patch. Prior uncommitted audit fixes are the baseline.
- macOS 27 beta `26A5425a`, arm64, Xcode-beta, Swift 6.4
  (`swiftlang-6.4.0.25.4`), Python 3.14.6, ShellCheck 0.11.0, OpenSSL 3.6.3.
  XcodeBuildMCP tools remain unavailable; used documented SwiftPM checks.
- Baseline `bash Scripts/check.sh`: exit 0, 127 tests / seven suites reported,
  native reset skipped; release bundle, plist and signature passed.
  Evidence: `.build/continuation-baseline.log`.
- Read-only `gh issue list --state open --limit 20 --json number,title,labels`:
  exit 0; #15 (menu height) remains the sole open issue. No GitHub writes.

Revisited only persistence/trust, connection lifecycle, updater, shared response
reading and the reported DTO/interface edge cases. Reused the historical
inventory, issue context and performance evidence; did not rerun the unchanged
session benchmark or invent app-wide speed/energy claims.

No app launch/stop, installation, live-controller request, real credential/pin/
login-item/reset operation, system-trust change, dependency addition or source
upload to auxiliary services occurred. Tests inject isolated defaults, fake
stores/clients/transports, synthetic interfaces and offline public certificates.
The separately gated Mantis campaign was not started.

## Priority-queue dispositions

### 1. Credentials and pins — partially addressed

**Credential pair atomicity: confirmed, unresolved.** A fake second-write failure
left a new controller URL beside the previous API key after preferences were
recreated. The desired preservation assertion failed. No credential production
code was changed in this continuation; no migration or fallible rollback was
activated. The isolated reproduction and failing log remain at
`.build/CredentialWriteReproductionTests.swift` and
`.build/continuation-credentials-red.log`. The temporary reproduction was moved
out of the active suite after demonstrating the unresolved defect; no existing
test was removed, disabled or weakened.

The credential helper still conflates read errors with absence and ignores
delete status. Interrupted or overlapping two-item writes can leave inconsistent
persistent credentials. A fix needs one atomic credential record, a
backward-compatible/failure-safe migration design, fake failures at every
migration boundary, and separately authorized isolated native migration/reset
verification before activation. This report does not certify credential safety.

**Pin failures: corrected at the current-path persistence boundary.** New
`Network/CertificatePinStore.swift` injects the three Security operations; the
native adapter retains existing service/account names. Missing pins differ from
read errors/malformed values. A first-writer-wins add never deletes or replaces
an existing different pin; duplicate insertion succeeds only for the same hash.
`PinnedCertDelegate` persists under its lock before granting trust and fails
closed on store failures. A failed explicit pin reset preserves the current
client/trust; successful reset disables the old delegate until recreation.

`CertificatePinTests` covers read/add/delete errors, malformed data, retries via
fresh delegates, persisted continuity across recreation, changed keys and two
delegates that both observed first use. These tests model competing first-use
writers; they are not a multi-process native-Keychain stress test.
`StatusBarControllerTests` checks that failed pin reset does not reconfigure.
Native Keychain integration remains unverified. **Reset-all still uses a
best-effort pin-delete wrapper and native login-item operations** and is not
fixed by the explicit pin-reset correction; its existing test stays disabled.

### 2. Certificate validation — demonstrated policy failures corrected offline

Offline Security.framework evaluation reproduced acceptance of expired and
wrong-host certificates behind `errSecNotTrusted`. Replaced permissive/manual
date parsing with native validity dates, explicit validity-window checks and
SSL policy evaluation anchored only to the presented leaf on that `SecTrust`
object. Trust is never installed in the system. Missing/unacceptable certificate
properties fail closed; pin continuity is still required.

`CertificatePinTests` exercises the actual authentication delegate using a
synthetic challenge, fixed verification date and network fetching disabled.
Valid self-signed, wrong hostname, expired, future and combined failures are
covered. Public EC certificates are embedded; no private keys are source/test
resources. Initial overly long validity fixtures were rejected as nonstandard
and corrected independently of the actual wrong-host/expiry regression
(`continuation-trust-diagnosis.log`).

No TLS handshake was performed. Actual controller certificate compatibility
(including IP-address SANs and long-lived/legacy certificates), OS trust-policy
variation and stable macOS 26 verification remain native gates. Normal TLS
configuration and task-delegate forwarding were preserved, not re-certified.
The earlier redirect-forwarding concern remains disproven by the SDK contract;
no redundant delegate routing was added.

### 3. Setup/preferences lifecycle — partially addressed

Both views now own/cancel validation tasks and route through
`StatusBarController.connect(using:url:apiKey:allowSelfSigned:)`. The shared flow
invalidates temporary clients on success/failure/cancellation and checks
cancellation plus a connection generation before persistence and before final
site publication/reconfiguration. A new connection or reset supersedes older
validation. Cancelled setup retry sleeps no longer publish afterward. Reset confirmation now
cancels validation and invalidates controller generations synchronously before
starting asynchronous native cleanup, rather than waiting until cleanup ends.

Controlled fake-client suspensions reproduced leaked validation clients and
obsolete writes/reconfiguration; regressions now pass for cancellation,
supersession and reset **before persistence starts**. This is not full UI or
transactional lifecycle coverage: once credential persistence starts, cancelling
cannot undo its writes/cache updates, and overlapping saves remain non-atomic.
Cancellation during later persistence/reconfiguration phases is not claimed
safe by these tests. Resolve the credential transaction first, then inject
suspensions at its commit boundaries and perform authorized native dismissal,
retry, reset and setup/preferences QA. No UI was launched.

### 4. Updates — scheduling and release-link corrections verified with fakes

`UpdateChecker` now accepts isolated defaults/clock/transport, shares one
in-flight task, timestamps successful checks, and throttles automatic retries
for five minutes after failed/cancelled attempts. Success retains the existing
24-hour interval. Cancelled responses cannot publish or consume the daily
success timestamp. Clock rollback does not suppress checks indefinitely.

`StatusBarController.refresh` invokes the gate from the existing polling
lifecycle rather than only its first successful poll. No second timer was added.
Tests reproduced the missed next-day check and duplicate requests, and cover
failure/retry, due/not-due checks, overlap and cancellation. Automatic scheduling
still depends on that lifecycle: unconfigured or permanently auth-stopped
sessions do not acquire a separate background update timer.

Published release links require HTTPS, github.com, the intended darox/UniFiBar
release path and no credentials, query/fragment, alternate port or traversal.
Seven untrusted-link fixtures are rejected. The API-version header remains
unchanged: the historical 404 did not prove it invalid. No live GitHub update
request was used as evidence for these fixes. User-facing controls remain a
proposal, not implemented functionality.

### 5. Bounded correctness — local fixes plus explicit contract/native gates

| Finding | Disposition and evidence | Residual / prerequisite |
| --- | --- | --- |
| Unbounded controller body | Shared `UniFiClient.request` uses `URLSession.bytes`, cancels its task on exit, and passes bytes through a bounded reader before decoding. Rejects oversized declared or actual length without appending beyond the ceiling; cancellation, HTTP and transport failures remain errors. `ResponseLimitTests` proves early stop with unknown/understated length, oversized declared length, empty/exact-limit bodies, cancellation and transport failure. | **16 MiB (16,777,216 bytes) per response**, chosen conservatively for a menu-bar client, not validated against production payload distributions. Large deployments may see failed/unavailable sections. This caps the accumulated body, not Foundation buffering, concurrent bodies or decoded-model/process memory. Synthetic byte delivery is not a chunked-HTTP, compression, redirect or TLS integration test. Validate those in the isolated native controller lab; add contract-backed bounded pagination rather than silently raising the cap. |
| Nil-model WAN device | `DeviceDTO.isGateway` checks the existing `wan` feature independently of model availability. Synthetic JSON regression failed before and passes after; model-based gateway/non-gateway behavior retained. | No model/schema expansion or case-normalization assumption added. |
| Active/ordered interfaces | `DeviceDetector` applies `IFF_UP` and `IFF_RUNNING`, sorts by interface name and deduplicates IPs. Synthetic linked `ifaddrs` lists reproduced inactive/unordered results; no host interfaces queried. Removed the assumption that interface order identifies Wi-Fi/default-route priority. | Name order is deterministic, not route preference or proof of Wi-Fi versus Ethernet. Existing `en*`/IPv4-only scope remains. Native multi-interface/sleep/network QA remains gated. |
| Site/API consistency and pagination | **Unresolved:** official discovery still chooses the first site, legacy/v2 paths use `default`, and lists retain existing caps/no page traversal. | Need sanitized, versioned official/v2/legacy responses showing the same two sites and first/last/empty pages, plus authoritative field/token semantics. No trustworthy new fixtures were obtained; no schema invented. Implement shared site identity and bounded pagination before site-selection UI. |
| Radio-band and #15 display assumptions | **Unresolved:** channel-only band inference cannot establish 6 GHz. No layout/radio change made. | Obtain representative 2.4/5/6 GHz payloads and authoritative radio-field meanings. Separately authorize native compact/full menu, screen changes, keyboard/VoiceOver and sleep/wake QA per `docs/development.md`, including stable macOS 26. |

## Verification evidence

All logs below are ignored local artifacts under `.build/`. Expected red runs
are pre-correction evidence, not the final worktree result. Test totals count
Swift Testing test functions as the runner reports them, not each parameter case.

| Command | Exit | Evidence |
| --- | ---: | --- |
| Baseline `bash Scripts/check.sh` | 0 | `continuation-baseline.log`: 127 tests / seven suites, reset skipped; release/plist/signature pass. |
| Temporary `swift test --filter CredentialWriteReproductionTests` | 1 | `continuation-credentials-red.log`: new URL/old key reproduced after restart; intentionally unresolved, reproduction retained outside target. |
| `swift test --filter 'CertificatePinTests\|StatusBarControllerTests'`, before/after pin fixes | 1 / 0 | `continuation-pins-{red,green}.log`: eight issues red; 19 tests / two suites green at that checkpoint. |
| `swift test --filter 'StatusBarControllerTests\|CertificatePinTests'`, before/after shared lifecycle guards | 1 / 0 | `continuation-lifecycle-{red,green}.log`: 14 assertions red; 23 tests / two suites green at that checkpoint. |
| `swift test --filter UpdateCheckerTests`, before/after updater changes | 1 / 0 | `continuation-updater-{red,green}.log`: 27 issues red; 15 tests / one suite green. Initial warning cleanup rechecked in subsequent runs. |
| `swift test --filter 'StatusBarControllerTests/testUpdateChecksContinueAfterFirstSuccessfulPoll'` before scheduling correction | 1 | `continuation-updater-poll-red.log`: second-day check count remained one instead of two. |
| `swift test --filter 'UpdateCheckerTests\|StatusBarControllerTests'` | 0 | `continuation-updater-poll-green.log`: 32 tests / two suites. |
| `swift test --filter 'DecodeFlexibleArrayTests/gatewayClassificationDoesNotRequireAModel'` before fix | 1 | `continuation-gateway-red.log`: WAN-only device incorrectly false. |
| `swift test --filter ResponseLimitTests` before reader guards | 1 | `continuation-response-red.log`: eight issues; reader consumed all 100 synthetic bytes rather than stopping at the four-byte fixture limit or at cancellation. |
| `swift test --filter 'ResponseLimitTests\|DeviceDetectorTests\|DecodeFlexibleArrayTests'` before/after interface fix | 1 / 0 | `continuation-bounded-{red,green}.log`: inactive/unordered IPs red; 15 tests / three suites green. Response and gateway regressions also passed. |

Pre-review `bash Scripts/check.sh`: exit 0, `continuation-final-check.log`:
148 tests / ten suites, native reset skipped, release/plist/signature passed,
no compiler warnings. Post-review
`swift test --filter 'CertificatePinTests|StatusBarControllerTests'`: exit 0,
25 tests / two suites (`continuation-review-green.log`), including reset-prefix,
updater lifetime and trust-time checks. Final post-review
`bash Scripts/check.sh`: **exit 0**, `continuation-final-reviewed-check.log`:
**149 tests / ten suites reported**, native reset explicitly skipped, release
bundle/plist/ad-hoc signature passed; no compiler warnings/errors. The full
script also passed shell syntax, ShellCheck, synthetic bundle/fake-curl checks
and tracked/staged whitespace checks. Compile-only attempts
with fixture warnings/errors were corrected; they are not counted as
demonstrated runtime regressions or accepted checks.

Final preservation/whitespace review: all 82 entry files remain present; 71 are
byte-identical and 11 were intentionally changed. Five new source/test/report
files bring the incremental scope to 16 files. The historical audit, executed
prompt, session benchmark, credential implementation and unrelated first-pass
fixes remain unchanged from entry. Final HEAD matches the recorded base, and
all changes are uncommitted. Current incremental diff/file list and preservation
results are `.build/continuation-incremental.patch`,
`.build/continuation-changed-files.txt` and
`.build/continuation-preservation.log`. New/untracked text was checked separately
for whitespace and private-key material; none was found. No check was disabled
to obtain the final pass.

## Feature proposals — none implemented

Existing priorities are unchanged; no new speculative proposals or GitHub issues.

1. **Share-safe diagnostics:** still highest privacy value; default-redaction and
   explicit full-detail opt-in need product selection and synthetic leak checks.
   New pin failure diagnostics avoid raw store/query/credential contents but do
   not redact existing exports.
2. **Per-section health:** the body limit adds another legitimate unavailable
   result; acceptance must distinguish size/transport failure from empty data.
   Shared response failure handling helps, but stale-state/display semantics and
   #15/VoiceOver QA are still prerequisites.
3. **Site selection:** unchanged blocker: authoritative cross-API identity and
   pagination fixtures. Connection-generation guards help switch validation,
   but do not make credential/site persistence atomic.
4. **Update controls/status:** reliability and safe-link fixes now provide the
   clock/transport seam and shared task needed for this extension. Automatic-
   traffic defaults, manual-check behavior and visible failure/privacy status
   still need selection. No toggle, notification or auto-install subsystem added.

## Independent review

Two independent read-only reviewers inspected the incremental snapshot diff and
`git diff 0fede8a763ba09ac3bc204d993d1d962c89d7eb9 --`, plus untracked files.
HEAD has no new commits, so a three-dot commit diff would miss this work. Reviews
used the live files and `.build/continuation-incremental.patch`; parent performed
checks and completed the report. Neither reviewer ran tests/native operations.

### Standards

One test-lifetime finding: the next-day updater integration test joined the
controller refresh but not the independent updater task, assuming scheduling
order and risking defaults teardown before completion. **Corrected:** explicit
fake-transport request signals are observed before joining the updater task;
the one-minute-limited test cannot initiate a missing controller check itself.
Reviewer confirmed the correction read-only. No outstanding Standards findings
or worthwhile smell heuristics identified.

### Spec

- **P2 reset ordering — corrected and re-reviewed:** Preferences reset previously
  began asynchronous native cleanup before cancelling validation/incrementing
  the controller generation. Pending validation could begin saving during that
  suspension. Cancellation/reset-state now happen in the synchronous confirmation
  action. Existing fake reset-generation coverage exercises that prefix; actual
  native cleanup remains gated.
- **Initial P1 trust-time concern — downgraded by contrary evidence:** the SDK
  documents zero from `SecTrustGetVerifyTime` as “use current time,” but direct
  conversion treats it as 2001. However the offline unset-date test **passed
  before correction on this host** (`continuation-trust-time-red.log`, exit 0
  despite its attempted-red filename). No production TLS rejection was reproduced.
  Injecting the SDK-documented zero result into the conversion then failed one
  assertion (`continuation-trust-sentinel-red.log`, exit 1). Retained a one-line
  zero-to-current-date fallback, with native implicit-time, explicit-time and
  zero-sentinel checks. This is a documented-input compatibility correction,
  **not** a confirmed current-host TLS regression. Stable-native reachability
  remains unverified.

No additional actionable scope creep or implementation errors identified.
Review totals: **Standards: one test-lifetime correction, zero heuristics;
Spec: one P2 correction plus one downgraded SDK-compatibility concern with a
documented-input guard.**

## Next gates (not passed by this local run)

1. Design the atomic credential record/migration, fake failure coverage and
   commit/cancellation semantics; isolate native reset/login-item operations
   before enabling their tests. Do not rely on rollback of multiple writes.
2. Obtain explicit authorization for a separate macOS account and synthetic
   controller/certificate lab. Verify native TLS/Keychain/streamed-HTTP behavior
   and the setup/preferences/display QA on supported stable macOS 26/Xcode 26
   as well as the current beta host. A worktree or browser preview is insufficient.
3. Obtain the sanitized, contract-backed site/pagination/radio fixtures specified
   above. Replay them offline before changing mappings, completeness or band
   reporting. Features, issue publication, deployment and the Mantis campaign
   remain separately selected/authorized work.
