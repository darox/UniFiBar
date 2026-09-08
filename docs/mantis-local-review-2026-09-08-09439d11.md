# UniFiBar — restricted local Mantis-guided security review

**Date:** 2026-09-08. **Disposition:** one bounded, analysis-only pass completed;
not a full Mantis campaign, exploit reproduction, or security certification.

## Results at a glance

| Priority | Finding | Evidence and novelty |
| --- | --- | --- |
| 1 | F1: Separate credential writes can restore one controller's key against another controller's URL | Known unresolved; code behavior supported, native disclosure not reproduced |
| 2 | F2: Keychain/reset failures can appear as absence or successful forgetting | Known unresolved; error handling supported, native outcomes untested |
| 3 | F3: Reset invalidates old connections but does not exclude new ones during cleanup | Newly traced conditional lifecycle regression/residual; static interleaving only |
| 4 | F4: Site mixing, truncation and optional errors can produce misleading monitoring | Known integrity/reliability residuals; controller-contract questions remain |
| 5 | F5: Manual diagnostic export exposes network identifiers | Known, disclosed privacy exposure; no automatic exfiltration found in this flow |

Both approved checks exited **0**. Swift Testing reported **149 tests in 10
suites**, with `testResetAll()` explicitly skipped. No source, tests, or existing
documents were edited. Proposed corrections below were not applied.

Priorities are local remediation order, not empirical Mantis risk scores or CVSS.
“Supported” means the stated code behavior was traced; it does not mean a native
attack was demonstrated.

## Baseline, scope and provenance

| Item | Recorded value |
| --- | --- |
| Code root | `/Users/dario/Documents/dev/UniFiBar` |
| State root | `/Users/dario/Documents/dev/UniFiBar/.build/mantis-local-20260908T134703-09439d11` |
| Artifact directory | `workspace/` beneath that state root |
| Entry time | `2026-09-08T13:47:03.108259+02:00` |
| HEAD | `0fede8a763ba09ac3bc204d993d1d962c89d7eb9` |
| Worktree | 35 pre-existing modified/untracked entries; 88 selected first-party files inventoried with SHA-256, size and mode |
| Installed Mantis | `https://github.com/google/mantis`, revision `d13c93fb8e9779801711daea0d65fffa133c3b2d` |
| Resolved skill source | `/Users/dario/.codex/skill-sources/google-mantis/d13c93fb8e9779801711daea0d65fffa133c3b2d/` |
| Skill integrity | All 19 `SKILL.md` files plus `README_AGENTS.md` and `schema.json` matched the installation manifest; manifest separately hashed; reference harness disabled |
| Provenance mode | Live tree / MODE-OFF; no snapshots, source copies, pinning, sync, or fabricated Mantis state |

The new state directories were created privately (0700, umask 077), with path
and symlink-escape checks. They separate artifacts; **they do not isolate
execution**. Hashes identify inspected bytes, not immutable pinned provenance.

Read project instructions, the development guide and both existing September 8
audit reports. Domain/ADR documents were absent. Inspected priority production
flows through preferences, credential/pin stores, controller transport, lifecycle,
models, relevant views, updater, diagnostics, scripts and packaging, plus their
existing test construction. The 88-file inventory includes configuration/assets;
it is not a claim of equally deep review of every file or exhaustive UI coverage.

Local history was non-shallow. Scoped history distinguished the credential test
seam (`0c78996`) and fixture isolation (`0fede8a`) from transaction fixes. Most
current audit fixes are uncommitted and must be evaluated in the worktree, not
inferred from HEAD. Historical scratch reproductions under older ignored state
were neither read nor rerun. Historical test counts were not reused.

No app launch, install, stop, real controller request, native reset/pin operation,
credential inspection, system-trust change, browsing, remote Git/GitHub action,
dependency installation, auxiliary model, embedding service or subagent was used.
Only approved checks executed target code. Normal assistant-provider processing
still applies; this was not on-device inference.

## Mantis stage accounting

The installed shared guide (`README_AGENTS.md:3-17`) requires isolated,
restricted environments and expert verification before external reporting.
This pass used analytical guidance under the stricter local prompt, not that
suite's autonomous execution machinery.

**Correction to the input prompt:** installed `mantis-review/SKILL.md:135-141`
explicitly skips the snapshot-match gate in MODE-OFF. Its `NEEDS_RESEARCH` /
`UNKNOWN` drift handling at lines 143-209 applies to MODE-ON findings that do
not match, not every unpinned review. That gate did not fire here. Formal
validation was nevertheless not run: the requested local adaptation prohibits
authoritative validation and generated helper execution, and does not satisfy
the shared isolation requirement. No snapshot drift or formal verdict was invented.

| Skill / operation | Actual status and reason |
| --- | --- |
| `mantis-history` | Guidance-only: scoped local Git history and current diffs; no extraction helper or remote history |
| `mantis-architecture` | Guidance-only: state-local architecture/trust map; no source-tree KB or formal KB pipeline |
| `mantis-threat-model` | Guidance-only: attackers, prerequisites, assets and trust boundaries mapped below and in state |
| `mantis-plan` | Guidance-only: five-boundary plan in `workspace/local-analysis.md`; no formal plan JSON |
| `mantis-researcher` | Guidance-only: direct source-to-sink tracing; no swarm, embeddings or formal finding records |
| `mantis-dedupe` | Guidance-only: common credential causes and monitoring symptoms consolidated manually |
| `mantis-critic` | Guidance-only: production callers, prerequisites and counterevidence assessed; no formal eligibility verdicts |
| `mantis-review` | Formal execution blocked by this adaptation's boundaries; additional local assessment is non-authoritative; MODE-OFF correction above |
| `mantis-reproduce` | Blocked: no isolated runtime; no generated PoC, deliberate crash, resource-exhaustion test or native attack authorized |
| `mantis-patch` | Blocked: application forbidden; no reproduced input or isolated verification/re-attack environment |
| `mantis-chain` | Ineligible: no formally validated findings; no confirmed exploit chains constructed |
| `mantis-calibrate` | Ineligible: empirical evidence/eligible formal inputs absent; no risk scores manufactured |
| `mantis-report` | Formal packet ineligible: calibrated and reproduced findings absent; this separate local report is the requested deliverable |
| `mantis-reflect` | Guidance-only: actual conversation/check outcomes; no exported normalized stage transcripts; gap recorded rather than invented |
| `mantis-summarize`, `mantis-structural-index` | Skipped as requested; existing inventory and bounded searches sufficient |
| `mantis-meta-agent`, `mantis-pipeline-adapter`, `mantis-advise` | Skipped: no continuous campaign, custom harness setup or separate advisory query needed |
| Existing project regression checks | Executed after source preflight; separate from every formal Mantis stage |

No schema-shaped finding verdicts, `repro_status: reproduced`, patch
`VERIFIED_SECURE`, snapshot history or normalized transcripts were created.
Absence of a formal packet does **not** mean absence of vulnerabilities.

## Architecture and trust boundaries

| Entry / attacker-controlled input | Sensitive path | Boundary and countermeasure |
| --- | --- | --- |
| User-entered controller URL/key; local save/reset timing | Setup/preferences -> `connect` -> credential store -> restored client -> `X-API-KEY` | HTTPS/URL validation and task generations exist; pair identity and transaction ordering remain vulnerable to partial operations |
| Controller responses and accepted TLS peer | URLSession -> redirect/pinning policy -> bounded body -> DTOs -> menu | Controller controls identifiers/metrics; network adversary needs accepted TLS or first-use TOFU opportunity, not merely LAN access after a valid pin |
| Keychain status, signing/backend changes, competing app instances | Credential namespace and host-scoped certificate pins | OS storage is trusted but fallible; no cross-user extraction or existing credential access assumed |
| Delayed requests and local lifecycle events | Poll/wake/path/manual work -> `WiFiStatus` publication | Generation checks protect superseded results; resetting, stopping and cancelling have different semantics |
| GitHub response; explicit copy/share; operator probe invocation | Update metadata/release link; general pasteboard; shell environment/output | Updater does not carry the controller key; diagnostics contain identifiers; operator environment is not protected merely by removing a key from argv |

## Ranked findings and minimal proposals

### F1 — Non-atomic credential pair and commit lifecycle

**Known unresolved. Confidence:** high for partial-write/read behavior;
conditional confidentiality impact, not natively reproduced.

**Locations:** `Sources/UniFiBar/Preferences/PreferencesManager.swift:108-144`;
`Sources/UniFiBar/Utils/KeychainHelper.swift:59-78`;
`Sources/UniFiBar/StatusBar/StatusBarController.swift:136-155`;
`Sources/UniFiBar/Network/UniFiClient.swift:87-100`.
Production callers: `Sources/UniFiBar/Views/SetupView.swift:113-124` and
`Sources/UniFiBar/Views/PreferencesView.swift:202-227`.

**Evidence / prerequisites:** with persisted `(URL_A, key_A)`, saving URL_B
succeeds at line 137, then saving key_B fails at line 138 or execution stops
between writes. Storage can retain `(URL_B, key_A)`. After restart, independent
reads load that pair; validation checks syntax, not that the key belongs to the
destination. The request attaches that key to URL_B. A user must be changing
controllers and a partial failure/interruption must occur; a recipient able to
accept the HTTPS request at B could receive A's key. A network attacker alone
does not choose B through this code.

Actor isolation serializes individual calls, not the multi-await transaction.
Reads, concurrent saves and reset can interleave. `connect` checks cancellation
and generation before/after the whole save, but cannot undo already committed
items or the cache publication inside `save`.

**Counterevidence:** cache updates follow both successful writes, so a failed
save does not necessarily leak immediately in the current process. Existing
TLS/redirect controls still apply, but cannot detect a mismatched initial
URL/key pair. The current fake-store failure fixture rejects saves generally;
it does not establish safety when only the second write fails. Earlier scratch
evidence is historical, not a reproduction in this pass.

**Minimal proposed correction:** store the credential pair as one versioned
Keychain record and serialize commit/load/reset with an explicit admission
policy. Define cancellation semantics at the commit boundary. Preserve existing
service/legacy lookup compatibility; migrate only after validating a complete
old pair, retain old records until the new record is committed and verified,
and surface migration failures. Do not substitute multi-write rollback, which
can also fail or race.

**Future acceptance:** fake-store failures at each write/migration boundary,
restart after interruption, overlapping save/read/reset and cancellation after
persistence begins must never return a mixed pair or revive superseded state.
Native migration/signing behavior needs isolated macOS verification before use.

### F2 — Storage errors and incomplete reset are hidden

**Known unresolved. Confidence:** high for suppressed status information;
native retention/backend transitions remain unverified.

**Locations:** `Sources/UniFiBar/Utils/KeychainHelper.swift:24-56`,
`Sources/UniFiBar/Utils/KeychainHelper.swift:66-99`;
`Sources/UniFiBar/Preferences/PreferencesManager.swift:158-180`;
`Sources/UniFiBar/Network/UniFiClient.swift:532-534`;
`Sources/UniFiBar/Views/PreferencesView.swift:46-54` and
`Sources/UniFiBar/Views/PreferencesView.swift:248-250`.

**Evidence / prerequisites:** read failure or malformed data becomes `nil`;
every failed update attempts an add, not only item-not-found; deletion ignores
its result. Reset also suppresses pin-removal and login-item errors, clears the
cache/settings and dismisses despite promising to remove credentials. Native
permission/lock/storage failures can therefore leave credentials or pins behind
while the app appears reset. Retained credentials can be loaded on restart.

The data-protection probe chooses the legacy backend for any non-success, not
only missing entitlement. Backend selection stays fixed for that process;
there is no explicit migration between namespaces. A changed signing/backend
condition can hide or reveal older records. These outcomes require the native
conditions; they were not induced here.

**Counterevidence:** normal successful deletion works. Dedicated certificate-pin
reset now propagates storage failures and preserves existing trust; this finding
concerns reset-all and the credential helper, not a blanket claim that pin errors
are ignored. No other-user credential access is established.

**Minimal proposed correction:** make reads/deletes fallible, distinguish missing
from inaccessible/malformed, and add only after item-not-found. Return an honest
incomplete-reset result, stop controller work regardless, and prevent silent
rehydration of undeleted credentials. Coordinate migration/backend decisions
with F1 rather than adding a second competing store. A reset-state marker may
be needed to preserve the user's intent across restart; do not claim deletion
succeeded when only the UI was cleared.

**Future acceptance:** fake status matrix plus isolated macOS tests for locked /
unavailable stores, signing changes, each deletion failure, restart after partial
reset, pin cleanup and login-item cleanup. Keep the native reset test disabled
on a normal developer account.

### F3 — Reset has no admission gate for new connection work

**Newly traced conditional regression/residual in the uncommitted ordering fix.**
Confidence is high that the exclusion mechanism is absent, moderate for the
production interleaving; UI/native timing was not exercised.

**Locations:** `Sources/UniFiBar/Views/PreferencesView.swift:47-50`,
`Sources/UniFiBar/Views/PreferencesView.swift:70-75`,
`Sources/UniFiBar/Views/PreferencesView.swift:248-250`;
`Sources/UniFiBar/Preferences/PreferencesManager.swift:166-180`;
`Sources/UniFiBar/StatusBar/StatusBarController.swift:136-155` and
`Sources/UniFiBar/StatusBar/StatusBarController.swift:182-205`.

**Evidence / prerequisites:** reset synchronously invalidates the current
connection generation, then launches async cleanup. There is no shared
reset-in-progress flag rejecting subsequent connects. Conditional schedule:
cleanup suspends at unregister; a fresh user connection validates, saves and
reconfigures; cleanup resumes, deletes credentials and clears preferences.
The new client/poll need not be invalidated because `reset()` no longer calls
`resetState()` after cleanup. This can leave activity inconsistent with “Reset
& Forget.” It requires a new local action during the cleanup window and suitable
scheduling, not an unauthenticated remote trigger.

**Counterevidence:** the early generation bump correctly rejects old validation
that has not reached persistence. Existing fixture tests cover that case. The
diff shows the late reset was moved to this early prefix, but the older code
also lacked complete transaction exclusion; the earlier version is not claimed
secure. This is distinct from F1's persistent mixed pair, though both should be
fixed at one lifecycle boundary.

**Minimal proposed correction:** establish shared reset admission before the
first suspension, reject/defer new connections and reconfiguration entry points
until cleanup completes, and serialize/drain any accepted credential commit.
Keep the early invalidation. Merely restoring a final `resetState()` does not
solve writes racing with deletion.

**Future acceptance:** a fake cleanup seam paused at unregister and each delete;
attempt new connects from setup/preferences, release cleanup and assert no
revived credentials, retained client, polling or stale publication. Cover
startup/manual/event/pin-reset reconfiguration through the same admission rule.
Do not run the native reset routine to investigate this on the current host.

### F4 — Monitoring can mix sites and hide incompleteness or errors

**Known residuals, consolidated by user-visible integrity impact.** Confidence:
high for hardcoded paths, caps and error-to-empty behavior; actual cross-version
site mapping is not verified. Not an authorization-bypass finding.

**Locations:** `Sources/UniFiBar/Network/UniFiClient.swift:129-155`,
`Sources/UniFiBar/Network/UniFiClient.swift:244-285`,
`Sources/UniFiBar/Network/UniFiClient.swift:314-355`;
`Sources/UniFiBar/StatusBar/StatusBarController.swift:393-426`;
`Sources/UniFiBar/Models/WiFiStatus.swift:349-410` and
`Sources/UniFiBar/Models/WiFiStatus.swift:443-451`;
`Sources/UniFiBar/Views/MenuContentView.swift:65-102` and
`Sources/UniFiBar/Views/MenuContentView.swift:165-175`.

**Evidence / prerequisites:** discovery selects the first official site, while
v2/legacy calls use `default`. A multi-site controller whose first official site
does not map to that legacy site can mix unrelated data. Post-decode caps limit
clients to 5,000, sessions to 1,000, devices to 500 and optional sections further;
there is no completeness indicator or pagination. A local client outside the
retained prefix can appear absent. Devices can turn decode failure into `[]`;
optional failures become nil/empty while primary success has already marked the
view connected/fresh. Optional sections can disappear instead of showing failure.

**Counterevidence:** a single default site within caps may behave correctly.
Some monitoring failures are recorded in diagnostics. The body cap is a useful
resource bound, not evidence that every listed item is shown. A compromised
controller already controls returned data; this does not create new cross-tenant
authorization. Transport faults, larger sites and valid multi-site deployments
are sufficient reliability prerequisites without assuming an attacker.

**Minimal proposed correction:** distinguish unavailable, empty, incomplete and
last-success state in existing sections. Before changing site IDs, endpoint
schemas or pagination, obtain authoritative versioned contracts and sanitized
two-site / first-last-empty-page fixtures. Then share the correct site identity
and paginate within explicit limits. Do not guess API mappings or add a broader
dashboard/data layer to address this.

### F5 — Diagnostic sharing includes identifying network detail

**Known and documented. Confidence:** high for explicit export contents and
pasteboard sink; low-priority privacy improvement, not an automatic leak.

**Locations:** `Sources/UniFiBar/Utils/DiagnosticsLog.swift:63-167`;
`Sources/UniFiBar/Views/PreferencesView.swift:348-359`;
`Sources/UniFiBar/Views/MenuContentView.swift:211-221`;
`README.md:84-86`.

**Evidence / prerequisites:** user-triggered copy writes plain diagnostics to
the general pasteboard, including controller host, IP, network/AP/gateway/VPN
names, firmware and event detail. Disclosure requires clipboard access under
the OS's rules or the user sharing that text with another party.

**Counterevidence:** export does not take an API-key argument. Network error
logging uses codes/domains instead of raw bodies/URLs. The README correctly
discloses GitHub update checks and tells users to redact diagnostics before
sharing. No automatic diagnostics upload was found in the inspected flow.

**Minimal proposed correction / acceptance:** default to redacted identifiers
in this existing export, with explicit full-detail opt-in. Later use synthetic
unique identifiers to check both copy entry points; do not use real network data
or claim all arbitrary event text is safe merely because an API-key field is absent.

## Mitigations revalidated and remaining verification gaps

### TLS, pins and redirect handling

`Sources/UniFiBar/Network/CertificatePinStore.swift:22-49` distinguishes missing
pins from errors/malformed values, uses add-if-absent with duplicate equality,
and propagates deletion errors. `Sources/UniFiBar/Network/UniFiClient.swift:427-493`
fails closed on pin-store errors, persists before trust acceptance, retains a
mismatch state and disables the old delegate after successful explicit reset.
Competing fake-store delegates are covered; real multiprocess Keychain behavior
and reset races are not.

`Sources/UniFiBar/Network/UniFiClient.swift:496-516` checks native leaf validity
dates, uses SSL hostname policy and leaf anchors on that trust object only, and
maps the documented zero verification time to now. The earlier report's
zero-time discussion is not evidence of a reproduced production TLS regression:
the unset-time policy fixture had already passed on this beta host. Current
offline fixtures do not establish native URLSession handshakes, IP SAN handling,
legacy long-lived certificate compatibility or stable-macOS behavior.

Normal certificate validation remains default; self-signed TOFU is opt-in
(`Sources/UniFiBar/Network/UniFiClient.swift:40-61`). TOFU cannot authenticate the
first peer against an independent identity. The redirect delegate permits only
the same HTTPS host/effective port without userinfo
(`Sources/UniFiBar/Network/UniFiClient.swift:394-400`), through the shared GET/POST
request path. Suspended-task fixtures are not native redirect/TLS integration
coverage; no evidence here justifies duplicating TLS delegation logic.

**Hypothesis only:** the pin delegate compares challenge host strings exactly
at `Sources/UniFiBar/Network/UniFiClient.swift:456-458`, falling back to normal
TLS for a different string, while pin keys use the raw host without port
(`Sources/UniFiBar/Network/CertificatePinStore.swift:52-55`). Equivalent hostname
spellings/native normalization might select different pin identities or policy
paths. No normalization mismatch or pin bypass was demonstrated. Test case,
trailing-dot, address spelling and port/redirect behavior in an isolated native
lab before deciding on canonicalization and migration; do not silently discard
existing pins. A default-TLS fallback still requires system-accepted trust.

### Lifecycle suspension-point coverage

All locations in this table are in `Sources/UniFiBar/StatusBar/StatusBarController.swift`
unless a different file is named. These are source assessments, not claims of
complete temporal verification.

| Await boundary | Protection / residual |
| --- | --- |
| `start`, lines 83-102: load and discarded-client invalidation | Checks refresh generation after load; discarded path terminates; no reset-in-progress admission |
| `reconfigure`, lines 104-132: old-client invalidation, load, first refresh | Checks generation after each suspension; cancellation alone is not checked as a separate lifecycle condition |
| `connect`, lines 136-155: validation, temporary invalidation, save, reconfigure | Temporary client always invalidated; cancellation/generation checks precede commit and follow save; F1/F3 remain |
| Preferences read/save/reset | `PreferencesManager.swift:108-180`: separate awaited store operations allow reentrancy; cache/settings publication is not an atomic transaction |
| Site discovery and error paths, lines 306-348 | Generation checks before publication, including after certificate status; reset-site-cache awaits end the branch without subsequent UI publication |
| Primary self fetch/error paths, lines 351-400 | Generation checked on success/error and after certificate status before publication |
| Optional batch awaits, lines 405-458 and 485-515 | Generation checked after each complete batch; sessions/AP/gateway use unstructured tasks that may outlive parent cancellation |
| Poll refresh/sleep, lines 207-225 | Cancellation/generation checked after refresh and at loop entry after sleep; `stopPolling` alone does not advance generation |
| Wake/path callbacks, lines 247-289 | Generation checked after sleep/refresh; tasks not individually owned, and queued callbacks capture generation when their task begins |
| Pin reset, lines 170-179; reset cleanup, lines 182-205 | Pin failure preserves trust; subsequent reconfigure lacks its own operation token. Reset schedules old-client invalidation without awaiting completion |
| Teardown, lines 72-81 | Cancels observers/poll, but does not advance generation or invalidate client; production caller is application termination, limiting long-lived impact |
| Views | Setup/preferences own validation tasks and check cancellation after connect. Setup retry sleep is cancellation-aware. `PreferencesView.swift:180-189` publishes loaded view state after a read without a cancellation check; reset task is separately unstructured |

Thus the existing fixes materially improve supersession safety, but “every
await is cancellation-safe” would be false. Secondary teardown/observer concerns
are not promoted to independent production exploits without reachability evidence.

### Response decoding, updater, scripts and packaging

| Area | Supported mitigation / limit |
| --- | --- |
| Controller body | `Sources/UniFiBar/Network/UniFiClient.swift:98-124`: streamed 16 MiB accumulated-body limit, expected-length check and cancellation; not a bound on Foundation buffering, decoded objects or total concurrent memory. Synthetic bytes, not chunked/compressed native network traffic, were tested |
| Identifiers / numeric data | `Sources/UniFiBar/Network/UniFiClient.swift:363-365`: restricted ASCII path identifiers; POST bodies use JSON serialization. Flexible-array decoding requires the wrapper key. WiFiStatus range checks guard subtraction/conversion and session aggregation tolerates duplicate MACs/invalid durations; clamped RSSI avoids overflow. Channel-only band inference still needs API contracts, not guessed semantics |
| Updater | `Sources/UniFiBar/Utils/UpdateChecker.swift:57-126`: single-flight, daily-success/five-minute-retry scheduling, cancellation around fetch and intended GitHub release-link allowlist; no binary download/install. Default `URLSession.shared.data` is unbounded and follows native redirects, but the URL is fixed GitHub and no controller key is sent. Hostile input requires GitHub/trusted-TLS compromise; no low-prerequisite DoS asserted. Automatic checks depend on polling; manual checks remain available |
| Probe script | Source and fake-curl fixtures support TLS verification by default, explicit insecure opt-in, curlrc/glob suppression, timeouts and header-over-stdin rather than argv. Environment/shell history remain sensitive; output prints a response prefix after buffering the response. No real host was probed |
| Build/package | `Package.swift` has no external dependencies/plugins. `Scripts/build_common.sh:53-55` copies the entitlements file as a resource; `Scripts/package_app.sh:32-33` signs ad hoc without applying it or enabling hardened runtime. A copied plist and successful signature verification do not establish sandboxing, notarization or production Keychain compatibility. No speculative entitlement change proposed |

## Verification and preservation

### Current execution evidence

Both commands ran from `/Users/dario/Documents/dev/UniFiBar`, after inspecting
their scripts, package targets and fixture construction for side effects.

| Exact command | Exit | Actual evidence |
| --- | --- | --- |
| `bash Scripts/check.sh --portable` | 0 | Shell syntax/ShellCheck, existing Python bundle and fake-probe checks, whitespace checks; log explicitly says Swift/macOS QA not run in portable mode |
| `bash Scripts/check.sh` | 0 | Portable checks plus Swift Testing summary, release build/bundle, plist and ad-hoc signature verification; app neither launched nor installed |

Logs and exit files are `workspace/check-portable.log`,
`workspace/check-portable.exit`, `workspace/check-full.log` and
`workspace/check-full.exit`. The full log's line 97 records the skip:
`testResetAll()` unregisters the real login item and requires separate-account QA.
Line 394 reports “149 tests in 10 suites passed”; the skip must not be erased by
that aggregate wording. No compiler `warning:` / `error:` matched in that log.

Toolchain: macOS 27.0 beta `26A5425a`, arm64; Xcode-beta developer directory,
SDK 27.0; Swift 6.4 (`swiftlang-6.4.0.25.4`, clang `2100.3.25.1`);
Python 3.14.6; ShellCheck 0.11.0; Git 2.55.0; OpenSSL 3.6.3.
XcodeBuildMCP tools were unavailable; the prompt-approved SwiftPM checks were
used. No browser verification was performed or needed.

The checks use fake credential/pin stores, isolated disposable defaults, fake
clients/update transports, embedded public certificate fixtures with network
fetching disabled, suspended redirect tasks and synthetic response/interface
data. Python probes replace curl and use synthetic credentials. These are
regression results, **not native exploit reproduction or sandbox containment**.
No additional executable tests or exploit helpers were generated.

### Worktree preservation

Entry artifacts are `workspace/entry.json`, `workspace/entry-status.txt`,
`workspace/entry-files.json`, `workspace/skill-provenance.json` and
`workspace/tool-versions.txt`. Pre-report recheck found **88/88 inventoried files
unchanged in SHA-256, size and mode**, with identical HEAD and Git status
(`workspace/preservation-before-report.json`). A final recheck is recorded in
`workspace/preservation-final.json` and `workspace/final-status.txt`; the only
new visible worktree path from this pass is this report. Approved checks also
created ordinary build/temp artifacts and disposable test-defaults suites.

This verifies the selected entry files at the measured points, not all host
state or immutability between reads. Existing ignored state and previous audit
scratch logs were excluded. No changes were discarded, committed or published.

## Smallest next steps

1. Have a maintainer approve F1/F2's single-record migration and fallible reset
   semantics; preserve compatibility before authorizing a focused fix.
2. Add only the missing fake commit/reset barriers and regression cases described
   in F1-F3 during that authorized implementation. Do not enable native reset
   merely to make the suite look complete.
3. Use an isolated macOS/controller setup for native Keychain/signing migration,
   reset/login-item behavior, TLS/pin continuity, redirects and stable-OS checks.
   A separate account alone limits settings exposure but is not process/network
   containment for autonomous reproducers.
4. Obtain versioned controller contracts and sanitized multi-site/page fixtures
   before F4 mapping changes. Consider F5 redacted export as a small existing-flow
   improvement, not a new telemetry feature.
5. Require expert verification before external disclosure or applied security
   patches. Start a formal Mantis reproduction/calibration/report pipeline only
   with its actual prerequisites and newly authorized scope.

Reflection: verify installed contracts rather than repeating prompt assumptions;
test green does not imply credential transaction safety; an earlier reset
invalidation is not a reset admission gate. Actual logs support the completed
checks, while normalized Mantis stage transcripts and native evidence are absent.
This pass stops here without applying fixes or starting another campaign.
