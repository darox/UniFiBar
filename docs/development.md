# Development checks

## Setup and worktrees

Full checks need macOS 26, Xcode 26 with Swift 6.2 or later, Python 3, and
ShellCheck. Check the selected tools with `xcode-select -p`,
`xcrun --show-sdk-version`, and `swift --version`.
Install ShellCheck with `brew install shellcheck` if it is absent.

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
# Linux or macOS: shell syntax, ShellCheck, bundle staging, diff whitespace.
bash Scripts/check.sh --portable

# macOS: focused preference checks, then all tests and release packaging.
swift test --filter PreferencesManagerTests
bash Scripts/check.sh
```

The full command verifies the release bundle's plist and code signature.
It does not launch the app or test the display. It returns status 2 on Linux;
a portable pass is not a full pass. Swift compilation is the current Swift
check; this repository has no separate Swift lint configuration.

Preference and controller tests use a separate UserDefaults suite for each case
and always inject `FakeKeychain`, including non-credential tests. The `resetAll()`
test is disabled because it still unregisters the real login item; reset and certificate-pin cleanup
remain separate-account QA. Never run credential tests against the real Keychain.

### Controller fixture isolation (#25)

Use `StatusBarController(fixturePreferences:clientLoader:)` with an isolated
preferences suite, a fake Keychain, and a loader returning only fake clients.
Startup and reconfiguration reuse that loader; `nil` stays unconfigured without
loading credentials. Fixtures use the production polling loop but register no
wake/network observers. Their updater creates no manual or periodic check tasks
and does not access the host's update timestamp. Stop and await polling tasks
before removing a test's defaults suite.

```bash
swift test --filter 'StatusBarControllerTests|PreferencesManagerTests|UpdateCheckerTests'
```

This is a unit-test seam, not a sandbox or a launchable fixture app. Callers must
provide safe dependencies; ordinary construction still uses native services.
The client-construction test uses normal TLS without requests or pin access;
it does not cover self-signed certificate handling. Setup/Preferences UI can
still create real clients and perform login-item/reset/pin actions. Do not launch
the app for fixture checks. Native lab readiness, profiling, controller replay,
and the deferred Mantis review remain separate work under roadmap #16.

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
open .build/release/UniFiBar.app
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
Mark end-to-end QA complete only when these checks pass. No controller replay
fixture or automated macOS UI test exists. A missing Mac or test controller is
a blocker, not a passed test.

Preferences contains an event log and a report export. Remove controller
addresses, IPs, SSIDs, and device names before sharing a report. The existing
`probe_endpoints.sh` disables TLS validation and differs from the app's current
endpoints; do not use its result as proof of app behavior.
