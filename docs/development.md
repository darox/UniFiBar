# Development checks

## Setup and worktrees

Full checks need macOS 26 or 27, Xcode 26 or 27 with Swift 6.2 or later,
Python 3, and ShellCheck. Check the selected tools with `xcode-select -p`,
`xcrun --show-sdk-version`, and `swift --version`.
Install ShellCheck with `brew install shellcheck` if it is absent.
Install SwiftLint with `brew install swiftlint` and actionlint with
`brew install actionlint` if they are absent. `.github/actionlint.yaml` declares
the preview runner labels that GitHub omits from its public label list.
SwiftLint runs in `check.sh` and in CI. `.swiftlint.yml` documents
which rules are off and why.
Xcode 26 ships the macOS 26 SDK, so keep to APIs that exist there: macOS 27
additions such as `.textFieldStyle(.bordered)` fail to build with Xcode 26 and
belong behind a compiler or availability gate when they are worth adopting.

Run commands from the repository root. For separate work:

```bash
git worktree add -b audit/my-change ../unifibar-my-change HEAD
cd ../unifibar-my-change
bash Scripts/check.sh --portable
```

Each worktree has its own `.build` directory. Running apps still share the
bundle ID, Keychain entries, settings, and login item. Use a separate macOS
test account for setup, credential, certificate, and reset tests.
`compile_and_run.sh` stops all processes named UniFiBar before it builds;
use `package_app.sh` if the running app must stay open.

## Checks

```bash
# Once per clone: refuse to publish the refs/t3 checkpoints.
Scripts/install_hooks.sh

# Linux or macOS: shell syntax, ShellCheck, bundle staging, diff whitespace.
bash Scripts/check.sh --portable

# macOS: focused preference checks, then all tests and release packaging.
swift test --filter PreferencesManagerTests
bash Scripts/check.sh
```

`check_secrets.sh` scans tracked files and every ref's reachable history for known
token shapes, private-key headers and secret-bearing file types. It is a tripwire,
not proof. Add a pattern when a new credential shape appears.

The history scan exists because an ignored file is not a safe file. Agent tooling
(the T3 Code checkpoints under `refs/t3`) commits the whole working tree, ignored
files included. If the scan reports a file, rotate the credential first, then
delete the refs that hold it:

```bash
Scripts/prune_checkpoints.sh
```

Push explicit branches and tags only. Never `git push --all` or `git push --mirror`,
which would publish those refs. Run `Scripts/install_hooks.sh` once per clone to
point Git at `Scripts/hooks`. The pre-push hook then refuses to publish any
`refs/t3/*` ref, including a `--mirror` push.

The full command verifies the release bundle's plist and code signature.
It does not launch the app or test the display. It returns status 2 on Linux. A portable pass is not a full pass.
Do not launch the bundle through `.build/release/UniFiBar.app`. That path is a
symlink, and launchd refuses it. Copy the bundle first, or open
`.build/out/Products/Release/UniFiBar.app`.
SwiftLint enforces the style gate. `check.sh` skips a missing tool with a notice
on a developer machine and fails when `CI` is set, so a workflow cannot pass with a
gate that did not run.
CI runs the portable gate plus lint on the macOS 26 image, and lint plus the full
test suite on the macOS 26 image. It repeats lint and tests on the `xcode-27` preview image, which
carries Xcode 27 and the macOS 27 SDK. That job is non-blocking while GitHub
marks the image as preview.

### macOS 27 verification

Verified on macOS 27.2, build 26B5112a, with Xcode 27.1 and the macOS 27.0 SDK:

- `swift test` passes, 227 tests in 15 suites, including `CertificatePinTests`.
- `package_app.sh` builds, assembles and ad-hoc signs the release bundle.
- `codesign --verify --deep --strict` passes and the bundle reports `minos 26.0`.
- The app launches from the built bundle and stays running.

The same run found two launch traps that are not code defects:

- An entitlement placeholder such as `$(AppIdentifierPrefix)` fails in an ad-hoc
  signature. macOS rejects it and launchd refuses the bundle. `package_app.sh`
  fails loudly instead.
- Launchd refuses the bundle through the `.build/release` symlink. Use the real
  path or a copy.

Preference and controller tests use a separate UserDefaults suite for each case
and always inject `FakeKeychain`, including non-credential tests. Native `testResetAll()`
remains disabled because it unregisters the real login item. The other reset tests
inject both `removePins` and `unregisterLoginItem`; never omit those dependencies
when testing reset. `KeychainHelperTests` replaces every Security operation with
an in-memory fixture. Native reset and certificate-pin cleanup remain lab QA.
Ordinary credential tests must never access the real Keychain. The explicit native
fixture command below is the only direct-host exception: exact synthetic namespaces,
not application records.

### Sandboxed agent runs

Restricted sandboxes (for example AI agent shells) block parts of the build.
Run tests there with explicit cache paths:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/pm-cache swift test \
    --disable-sandbox --scratch-path /tmp/ufb-build
```

`CertificatePinTests` need live Security framework access. Their SecTrust
success paths fail in sandboxed processes even at a clean checkout. Treat a
certificate failure in a sandbox as environmental until an unsandboxed run
proves otherwise. The full suite also touches `NSUserDefaults` suites and can
stall on host-only paths under a sandbox; run `bash Scripts/check.sh` once on
the host before you trust sandbox results.

`Scripts/benchmark_sessions.sh` builds and runs the synthetic session
benchmark. It is a manual tool, not part of `check.sh`.

### Credential format and reset lifecycle

Credentials now use one versioned `com.unifbar.credentials.v1` item under the
existing `com.unifbar.app` service, including the certificate mode. Old independent
URL/key items are never automatically paired or sent: users must re-enter both
values once. A verified explicit save removes accessible obsolete records only
after writing and reading back the new record. A cleanup/readback failure can
happen after the new record commits; an error is not proof of rollback.

The helper checks both Keychain namespaces, rejects conflicting accessible
records, and falls back from data protection only for missing entitlement, not
for lock/access errors. An inaccessible namespace may retain older entries.
Reset reports this as incomplete even if it removed the accessible copy; do not
hide that error merely to make ad-hoc signing appear equivalent to release signing.
Test signing/backend transitions in an isolated macOS environment before release.

UI reset calls `StatusBarController.resetConfiguration()` synchronously. It closes
connection admission, invalidates active/validation clients and drains credential
operations before deleting credentials, all app pins and the login item. Other
cleanup continues after an individual failure. Reset intent remains in defaults
across restart until an explicit successful credential save; reopening alone does
not revive undeleted credentials. Cancellation before commit prevents a queued
save; cancellation after commit begins is not rollback and does not reconnect.

The queue serializes one preferences instance, not multiple app processes. Do not
run old and new app versions together to validate migration. Fake-store restart
tests do not prove native Keychain behavior, power-loss durability or isolation.

### Controller fixture isolation (#25)

Use `StatusBarController(fixturePreferences:clientLoader:)` with an isolated
preferences suite, a fake Keychain, and a loader returning only fake clients.
Startup and reconfiguration reuse that loader; `nil` stays unconfigured without
loading credentials. Fixtures use the production polling loop but register no
wake/network observers. Their default updater creates no manual or periodic check tasks
and does not access the host's update timestamp. Updater integration tests may
instead inject an updater with isolated defaults, a fake clock and a fake transport.
Stop and await polling tasks
before removing a test's defaults suite.

```bash
swift test --filter 'StatusBarControllerTests|PreferencesManagerTests|UpdateCheckerTests'
```

This is a unit-test seam, not a sandbox or a launchable fixture app. Callers must
provide safe dependencies; ordinary construction still uses native services.
The client-construction test uses normal TLS without requests or pin access;
it does not cover self-signed certificate handling. Setup/Preferences default to
real client creation; Preferences also defaults to native login-item and clipboard
operations. Full-form fixtures must explicitly inject `makeClient`, and Preferences
must also receive `loginItemIsEnabled`, `setLoginItemEnabled` and `copyReport`.
These do not replace the safe controller/preferences dependencies above. Do not
launch the real app or invoke unrelated reset/pin/updater actions for fixture checks.
Native release QA, profiling and real-controller replay remain separate work under
roadmap #16.

### Continuation regression fixtures

`CertificatePinTests` injects fake Security operations and evaluates public,
offline certificates at a fixed date with network fetching disabled. It does
not perform a TLS handshake, read native pins or change system trust.
`ResponseLimitTests` supplies synthetic asynchronous bytes; `DeviceDetectorTests`
supplies a synthetic interface list, never the host's interfaces.

Controller responses are streamed with a **16 MiB (16,777,216-byte) per-response
ceiling**, including unknown or understated lengths. Oversized bodies fail rather
than decode partial JSON. Foundation buffers and decoded models still use memory;
this is not a process-wide memory bound. Large deployments may now receive an
error or unavailable optional section instead of a large response. Obtain real
controller captures before claiming complete large-site support. Official sites,
devices and configured VPN tunnels now follow the documented offset/limit pages
(up to 200 requested entries per page), validating offsets, counts, unique IDs,
progress and a stable total. Budgets are **5,000 entries, 100 pages and 16 MiB
across a collection**; exhausted or inconsistent results fail, never publish a
partial list. Each controller resource request has a 30-second timeout.

Older APIs have no verified pagination contract here. Returned active clients
are searched in full up to 10,000 entries; legacy collections allow up to 5,000
entries. Over-limit responses fail rather than return a prefix. Nearby APs are
explicitly presented as the top ten by signal. These are post-decode entry
limits, not a decoded-memory bound or proof of server-side completeness.

`UniFiClientTests` replays synthetic schema-shaped responses through an explicit
offline transport, with injected local addresses and no native pin/credential
access. Its source contracts are documented in
[the API research](unifi-api-contracts-2026-09-08.md). Tests cover paired site
identity, pages, malformed/changing/over-limit collections, unsupported schemas,
empty responses, cancellation and absent VPN status. Legacy envelopes with non-null
`meta` must contain string `rc: "ok"`; explicit error/unknown codes or malformed
metadata fail, including WAN health. Missing/null metadata remains accepted.
Success envelopes retain empty/null-data handling, and flexible-array endpoints
still accept bare arrays. These are fail-closed parser policies, not live captures.
Optional metrics are cleared on a new primary result and marked refreshing;
failed, empty, disabled and inapplicable sources are distinguished. No stale
metrics are retained under a fresh connection timestamp.

Update metadata uses the same bounded stream reader with a **1 MiB** ceiling,
an ephemeral session and a 30-second resource timeout. Existing fake-updater
checks cover oversized-response failure backoff; `ResponseLimitTests` verifies
the shared reader's actual/declared-length, cancellation and transport behavior.

`Tests/test_build_bundle.py` uses the actual bundle assembly function and
tracked image assets in a temporary directory. `true` from `PATH` supplies an
executable fixture; an `iconutil` test double replaces macOS icon conversion.
The check verifies metadata, file contents, executable permissions, rebuilds,
paths with spaces, and missing optional icons. It needs no network or key.

```bash
python3 Tests/test_build_bundle.py --benchmark
```

This measures shell staging only: seven rounds of twenty bundles after two
warm-up bundles. It does not measure Swift compilation, icon conversion,
signing, controller latency, or app runtime.

## Debug and end-to-end QA

Use the Swift extension with `.vscode/launch.json` for code debugging. Its
working directory now works with any checkout name. A bare SwiftPM executable
does not have the packaged app's metadata and icons. Use the bundle for UI QA.

On a separate macOS test account, after the full command passes:

```bash
open .build/out/Products/Release/UniFiBar.app
log stream --style compact --predicate 'subsystem == "com.unifbar.app"'
```

1. Open the menu, open Setup, and connect to an authorized test controller.
   Confirm that the detected device and displayed metrics match the controller.
2. Check normal and compact modes, all sections, scrolling, and footer buttons.
   Check both short and tall screens and a display change. For issue #15,
   confirm that the menu is not compressed to a few rows and that the footer
   remains reachable. Save before and after screenshots with screen dimensions.
3. Check refresh, a lost connection, recovery, and sleep/wake. Confirm that
   Preferences changes persist. Test invalid credentials and certificate changes
   only on the test controller.
4. Check the setup, loading, connected, and error states. Check keyboard access
   and VoiceOver labels. Quit and reopen the app.

Record the commit, macOS/Xcode versions, commands, exit codes, and screenshots.
Mark end-to-end QA complete only when these checks pass. `MenuLayoutTests` measures
offscreen setup/error and connected full/compact layouts at synthetic 360/600/1000
point height budgets. Native fixtures below add real TLS and view/action checks,
but do not launch the product's MenuBarExtra or establish live controller, physical
display, keyboard/VoiceOver or sleep/wake compatibility. A missing test controller
is a blocker, not a passed test.

### Opt-in direct-host native fixtures

```bash
python3 Tests/NativeAudit/run.py --run-synthetic-native-checks
# Or select one group: --only storage | --only transport | --only ui
```

Requires macOS, the selected Swift/Xcode tools, Python 3 and an existing OpenSSL.
Not invoked by `check.sh`. No VM, separate account, system trust changes,
dependencies, installed-app launch or login-item actions. This is namespace
separation, **not execution isolation**. Current Codex-local Mantis policy permits
safe local checks, but a fixture pass alone does not establish formal reproduction
or independent re-attack; apply the installed policy's evidence gates.

The runner compiles current production sources excluding the real app entry points.
Each run records source hashes, commands, PIDs, statuses and fixture-only images in
private `.build/remaining-native-<UUID>/`. Native credential and pin operations
preserve backend attributes while enforcing exact synthetic service/account scopes,
including cleanup. Process-local Keychain interaction is disabled and restored.
Restart and interrupted-reset fixtures exit only their own processes; these are
not power-loss tests. Competing writes may report native duplicate/readback failures;
the assertion is a coherent committed record, not cross-process serialization.
Protected deletion returning `-34018` remains visible as **exit 2**, even when
accessible records are removed. Packaging remains ad-hoc, not an entitled identity.
UI defaults cleanup also runs in a separate owned command after the UI process
exits or times out; cleanup failure remains a runner failure.

Loopback TLS uses synthetic certificates, production trust/redirect/stream policies,
an in-memory pin store, 1 KiB boundary fixtures and shortened 2/4-second timeouts.
Native persistence is checked separately. It never contacts a controller. The UI
harness hosts real menu, diagnostics, Setup and Preferences views in owned AppKit
windows without activating them. It uses fake storage, an offline rejecting client,
fake login-item operations and clipboard sinks, and captures only those views.
It enables accessibility traversal only inside its own fixture process; no permission
or system VoiceOver setting changes. Form actions cover empty submission, URL
validation before client creation, normalized inputs, authentication errors, compact
preference persistence and login-toggle load/failure rollback. Programmatic actions
are not keyboard/VoiceOver or real login-item validation. Successful credential
connection and physical lifecycle checks still need an authorized QA environment.

See [the finish-audit report](audit-finish-2026-09-08.md) for actual results
and release gates. A beta-host fixture pass is not stable macOS 26 or 27 verification.

Preferences contains an event log and a report export. Both copy actions redact
identifiers and arbitrary text by default, retaining typed metrics, error titles,
HTTP authentication codes and event times/categories/levels. Raw events remain
local; Preferences requires an explicit one-copy opt-in for private details.
Review full-detail exports for credentials and network identifiers before sharing.
`probe_endpoints.sh` requires HTTPS and certificate validation; use
`CURL_CA_BUNDLE` for a trusted private CA. Its three monitoring requests match
the app's default-site paths and methods only; it does not discover or select
non-default sites. Curl does not exercise the app's TLS pinning or
decoding. Run it only against an authorized test controller. Portable checks use
a fake curl and never send these requests.
