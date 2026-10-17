# Finish the remaining UniFiBar audit work — unattended, on this Mac

Continue from the current worktree through implementation, verification and a
final report. Address the remaining findings in `docs/audit-issues-2026-09-08.md`,
not a new whole-project audit or speculative feature backlog. Fix demonstrated
defects; close verification gaps only with evidence from the relevant runtime.

Work directly on this machine. Do not provision a VM, container, separate macOS
account or isolated worktree. Disposable fixture namespaces protect user data;
they are **not execution isolation**. Follow applicable installed skill contracts:
ordinary local tests do not waive Mantis prerequisites or earn formal reproduction,
independent re-attack or `VERIFIED_SECURE` claims.

## 1. Establish current state

Work in `/Users/dario/Documents/dev/UniFiBar`. Read `AGENTS.md`, its referenced
instructions, and applicable domain/ADR documents if present. Read:

- `docs/audit-issues-2026-09-08.md` for current dispositions and open gates.
- `docs/unifi-api-contracts-2026-09-08.md` for verified contracts and unknowns.
- `docs/development.md` for existing checks, fixture seams and native hazards.

Consult older reports only for relevant history. Recheck current source and every
caller before editing; historical test counts are not current verification.
Create a fresh private artifact directory under `.build/remaining-audit-<unique>/`.
Record HEAD, Git status, scoped source hashes and actual OS/toolchain versions.
Inspect any prior harness before reusing it; old build artifacts are not proof
about current source. Preserve all pre-existing changes and historical reports.

**Done when:** each remaining item has a testable acceptance criterion, current
evidence and any missing prerequisite. Distinguish bugs from unverified behavior.

## 2. Apply these host boundaries throughout

Allowed unattended: focused source/tests/docs fixes, existing project checks,
bounded synthetic native tests, offscreen rendering, loopback-only test servers
and a fixture UI harness when its dependencies are demonstrably safe.

- Keep real credentials, pins, app preferences, login items and the installed or
  running UniFiBar untouched. Never run `compile_and_run.sh`, broad process kills,
  broad Keychain deletion, the disabled real-reset test or real reset UI actions.
- Before native storage calls, enforce exact run-specific service/account scopes
  for **every** read, write and delete, including fallback, migration and cleanup.
  Use synthetic records. Preserve Security query attributes being tested; inject
  only the namespace boundary. Track created resources and verify scoped cleanup.
  An inaccessible record is not proven absent, and failed cleanup stays visible.
- Launch only fixture-owned processes/bundles after verifying all paths to
  credentials, pinning, client construction, updater, reset and login-item actions.
  A renamed bundle alone is insufficient. Bind test servers only to loopback;
  use synthetic keys/certificates and per-session trust, never system trust changes.
- Keep operations bounded by time, response size, concurrency and owned PIDs.
  Terminate only fixture processes; no host reboot/sleep, interface disruption,
  resource-exhaustion experiments or physical power-loss tests. Simulated events
  and fixture-process termination must be labelled as such.
- Preserve Git history and user state: no reset, clean, stash, commit, push,
  GitHub publication/closure, dependency installation, OS upgrade or signing-key
  import. Use real controllers only when an exact test target, authorized access
  method and read-only operation scope have explicitly been provided. Do not
  discover controllers or retrieve stored credentials to fill that gap.

If a check exceeds these boundaries, record the exact prerequisite and continue
independent work. Reserve approval requests for genuinely necessary scope changes;
do not stall the whole run on a missing controller, identity or UI permission.

## 3. Work the remaining queue

### A. Native Keychain/signing and lifecycle

Inspect packaging and code-signature/entitlement metadata. Explain the actual
`errSecMissingEntitlement (-34018)` path; do not invent an entitlement, team or
identity, or suppress the failure. Use an existing explicitly configured signing
identity only if already usable without new authorization, and only for fixtures.

Adapt the existing injection seams for native synthetic save/update/read/delete,
legacy cleanup, restart/reset intent, competing fixture processes and pin continuity.
Exercise the current production implementations rather than copied logic. Preserve
the original backend behavior when applying run-specific query namespaces. Keep
ordinary tests free of real Keychain dependencies; native checks should be opt-in.

**Done when:** each accessible backend has current, scoped results and cleanup
evidence. Inaccessible backends, signing transitions and power-loss durability
remain explicitly unverified when their prerequisites are unavailable. Report
which part of `-34018` is fixable in source versus dependent on signing/access.

### B. Controller contracts and real transport

Reuse `UniFiClientTests`, the existing transport seam and bounded reader. Add only
the minimum harness needed to exercise actual URLSession/TLS behavior against
loopback fixtures: valid and rejected certificates, pin persistence/mismatch,
redirect policy, cancellation, chunked/understated/oversized bodies and timeouts.
Prevent synthetic API keys from leaving the fixture scope. Do not replace the
production policy with a permissive test delegate just to complete a handshake.

Use versioned primary sources and explicitly supplied sanitized captures to test
paired sites, first/middle/last/empty pages, optional failures, older API shapes,
VPN inventory and radio fields. Keep fixture provenance clear: a synthetic
schema-shaped response is not a controller capture. Validate aggregate collection
budgets and UI-visible incomplete/unavailable states where coverage is missing.

Preserve explicit site selection policy, unknown VPN health and omitted radio-band
inference unless evidence justifies a correction. Do not invent legacy pagination,
endpoint aliases or v2 radio meanings. With no authorized controller/capture,
complete available replay/transport work and list exact missing versions/payloads.

**Done when:** demonstrated transport/parser bugs have regressions and fixes;
supported-controller claims are limited to the versions and evidence actually tested.

### C. Native UI, accessibility and stable-OS compatibility

Extend existing offscreen tests first. For gaps requiring interaction, add the
smallest fixture harness that renders the real views with safe dependencies;
do not build a parallel UI implementation or make normal app launches use fakes.

Check connected full/compact menus, long/empty/unavailable content, scrolling and
footer reachability; setup/loading/error states; keyboard focus and accessibility
labels; diagnostic-copy redaction and private-detail opt-in. Prefer a fixture
clipboard sink so tests do not overwrite the user's clipboard. Measure supported
screen sizes and capture fixture-only screenshots without unrelated desktop data.

Use available native macOS tools for native UI. For public web documentation, use
T3's preview tools: status, open if needed, snapshot before interaction, and
condition-based waits. Do not substitute browser screenshots for native UI QA.
Use XcodeBuildMCP when available; otherwise document the fallback to existing
SwiftPM/project tools. Missing automation/accessibility permission is a specific
blocker, not permission to fake interaction or change host settings unattended.

Record the actual OS and SDK separately. A newer/beta host, older deployment
target, offscreen measurement or injected wake event does not establish stable
macOS compatibility, physical display transitions or real sleep/wake behavior.

**Done when:** observed UI defects are patched and retested; each #15/native QA
acceptance criterion has evidence or an explicit unmet prerequisite. Keep #15
open if its required coverage remains incomplete.

## 4. Verify fixes and preservation

Use minimal shared fixes, native APIs and existing dependencies. Leave a runnable
regression for each nontrivial change; retain fail-closed storage, redirect,
certificate and response-limit behavior. Avoid speculative product features.

Run focused checks during implementation, then `bash Scripts/check.sh` on the
final source. Keep native fixture checks separate with explicit prerequisites
and results. Run whitespace checks including new files. Record exact commands,
exit codes, skips, warnings and logs; a portable pass is not a complete pass.

**Done when:** final checks cover the final source, owned-resource cleanup is
accounted for, and entry/final status and hashes show only intentional changes.

## 5. Deliver and stop

Write one new dated report under `docs/`, linking this run's evidence. Give every
remaining item one disposition: **fixed and verified**, **verified unchanged**,
**mitigated but unverified**, or **blocked by a named prerequisite**. Separate
source inspection, fake tests, native fixture results and real-controller/OS QA.

For blockers, name the smallest concrete next action and required artifact or
authorization. Preserve cleanup failures and unexecuted checks in the report.
Do not repeat unavailable tests indefinitely, claim complete security from passing
tests, or spend the run merely restating blockers that safe fixture work can reduce.

Finish with a concise result, current verification totals, report path and remaining
release blockers. Stop when all feasible in-scope work is complete and every other
item has an honest, actionable disposition.
