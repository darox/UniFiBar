# UniFiBar — credential and reset security patch

**2026-09-08 · F1–F3 implemented and regression-checked.** This is the
user-approved patch follow-up to [the local Mantis-guided review](mantis-local-review-2026-09-08-09439d11.md),
not a formal Mantis exploitation or independently verified security result.

**Upgrade action:** users with the old separate URL/key items must re-enter both
once. Automatic migration cannot establish that an existing pair belongs together.

## Scope and provenance

Changes were made in the existing dirty worktree, preserving prior work. HEAD
remains `0fede8a763ba09ac3bc204d993d1d962c89d7eb9`; that commit alone does not
reproduce the reviewed source. Patch artifacts are under
`.build/security-patch-20260908T141016-6fa835f4/` (called `STATE_ROOT` below).
`entry-files.json` records 70 selected first-party files by SHA-256, size and mode;
`entry-head.txt`, `entry-status.txt` and `scope.md` record the starting scope.
Hashes identify live-tree bytes, not immutable pinned provenance or isolation.

The user's exploitation/patch approval authorizes these ordinary source fixes
and safe synthetic regression tests. It does not supply the isolated runtime
required by the installed Mantis contracts. `mantis-reproduce` and formal
`mantis-patch` verification/re-attack remain blocked; eligible reproduced findings
are also absent. Formal calibration/reporting remain ineligible. No formal
`repro_status: reproduced`, `VERIFIED_SECURE`, empirical score or campaign packet
was created. The original review and its stage accounting remain unchanged.

## Applied corrections

| Finding | Implementation and evidence |
| --- | --- |
| **F1 — split credentials** | `Sources/UniFiBar/Preferences/PreferencesManager.swift:53-67,146-220` stores and validates one versioned URL/key/trust-mode record. Legacy independent items are not restored. `Sources/UniFiBar/Utils/KeychainHelper.swift:75-119` writes one item and verifies readback before removing accessible obsolete records. The synthetic partial-write regression failed before the fix and passes now. |
| **F2 — hidden storage/reset failures** | `Sources/UniFiBar/Utils/KeychainHelper.swift:47-73,121-164` distinguishes absence from access/malformed/conflicting-record failures and makes deletion fallible. Only missing entitlement allows protected-to-legacy fallback; only item-not-found allows add after update. `Sources/UniFiBar/Preferences/PreferencesManager.swift:253-311` attempts all cleanup components, reports failures and retains reset intent across restart. Setup/preferences display credential errors. |
| **F3 — reset/connection races** | `Sources/UniFiBar/StatusBar/StatusBarController.swift:137-224` closes admission synchronously through `resetConfiguration()`, invalidates active/validation clients and passes connection ownership into queued saves. Preferences serializes credential operations and drains accepted work before deletion. Automatic startup/reconfiguration/refresh/polling honor reset intent. `Sources/UniFiBar/Network/UniFiClient.swift:73-92,451-453` rejects invalidated-client requests and prevents old delegates from re-pinning. |

### Deliberate behavior and limits

- Explicit save replaces credentials as a whole. Readback or obsolete-item
  cleanup can fail **after** the new item commits: an error is not rollback.
  Cancellation before storage handoff prevents queued saves; cancellation after
  handoff is not rollback and does not reconnect through the cancelled flow.
- Inaccessible storage is not proof that it is empty. Missing protected-Keychain
  entitlement during deletion reports incomplete reset even if legacy deletion
  succeeds. Ad-hoc signing may therefore keep reporting incomplete cleanup;
  native signing/backend behavior needs lab verification, not a suppressed error.
- Reset suppresses automatic credential restoration across restart until an
  explicit successful save. Cleanup continues after credential, pin or login-item
  failure. The UI dismisses only on successful cleanup; failures remain visible.
- The credential queue covers one preferences instance, not multiple processes.
  Whole-item writes do not make cross-backend migration, defaults persistence,
  cancellation or power-loss handling a global transaction.

## Verification

Commands ran from the repository root. Logs below are relative to `STATE_ROOT`.

| Command | Exit | Evidence |
| --- | --- | --- |
| `swift test --filter PreferencesManagerTests/testSaveFailureNeverRestoresMixedCredentials` — before implementation | 1, expected | `red-credential-pair.log`: injected failure in the second independent write restored the new synthetic URL despite failed save, leaving the old key. No credential was transmitted. |
| `bash Scripts/check.sh --portable` | 0 | `check-portable.log`: portable shell/Python/whitespace checks. |
| Focused Swift suite command below | 0 | `focused-fixed.log`: 59 tests in four suites at that intermediate revision. |
| `bash Scripts/check.sh` — final source revision | 0 | `check-full-final.log`: **172 tests in 11 suites passed** (line 467); release build, bundle/plist and ad-hoc signature checks passed (line 483). |
| `git diff --check` — final worktree | 0 | `diff-check-final.log`; report whitespace and local path references also checked. |

```bash
swift test --filter 'PreferencesManagerTests|KeychainHelperTests|StatusBarControllerTests|CertificatePinTests'
```

`testResetAll()` remains explicitly skipped (`check-full-final.log:40`): it
unregisters the real login item. Do not erase this skip behind the aggregate
test count. No compiler warning/error matched the final log; this was not a clean
rebuild claim. An earlier build reported an untouched `DeviceDetectorTests.swift`
redundant-`#require` warning.

The original red test now passes because there is no second independent write.
`testSingleRecordFailurePreservesPairAndTrustMode` additionally injects failure
into the new whole-record write and verifies the previous complete record remains.
Other regressions exercise backend status/readback/cleanup failures, legacy
re-entry, reset failure/retry/restart, paused reads/saves, queued cancellation and
supersession, validation invalidation before cleanup and refusal to re-pin.

All new executable checks use fake Security operations, fake clients/transports,
disposable defaults and existing offline certificate fixtures. Native reset
dependencies are replaced explicitly. XcodeBuildMCP tools were unavailable;
SwiftPM and the existing scripts were used. No app was launched, installed or
stopped; no real credentials, controller, native pin/reset/login-item operation,
remote Git/GitHub, browser, new dependency or subagent was used. Packaging does
not establish sandboxing or production-signing compatibility.

## Preservation and remaining work

`preservation-final.json` records **57 of 70 baseline files unchanged** and
exactly **13 intentionally changed existing files**, with no unexpected content
or mode changes. The only newly created visible files are
`Tests/UniFiBarTests/KeychainHelperTests.swift` and this report. All initial Git
status entries remain; HEAD is unchanged. The original audit report is unchanged.
`final-status.txt` and `verification.json` retain the final status and check/log
evidence. Build artifacts are separate from this selected-file preservation
claim; no all-host-state or between-read immutability guarantee is implied.

1. Before release, verify native Keychain/signing transitions, partial reset and
   restart behavior, TLS/pin continuity and stable-macOS compatibility in an
   isolated macOS/controller environment. Synthetic tests do not prove native
   exploitability, power-loss durability or complete interleaving coverage.
2. **F4 is not addressed:** obtain authoritative controller site/pagination
   contracts and sanitized multi-site/page fixtures before changing mappings.
3. **F5 is not addressed:** diagnostic identifier redaction remains a separate
   privacy improvement. Manual diagnostics still require review before sharing.

No speculative feature work, commit, publication or second audit campaign was
performed. Security/domain-expert review is still needed before deployment or
external disclosure.
