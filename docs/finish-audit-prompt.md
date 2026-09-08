# Finish the UniFiBar audit — implementation, verification and closure

Work unattended in `/Users/dario/Documents/dev/UniFiBar`, directly on this Mac.
Finish the outstanding audit work, not another whole-project audit or speculative
feature backlog. Implement demonstrated fixes, verify them against current source,
and leave the worktree ready for review. Continue every independent task while
external prerequisites are unavailable. A missing prerequisite remains open;
writing another report does not close it.

## 1. Reconcile current evidence before changing anything

Read `AGENTS.md`, its referenced instructions, and existing domain/ADR documents.
Use these sources in order:

- `docs/audit-remaining-2026-09-08.md`: latest completed pass and open gates.
- `docs/audit-issues-2026-09-08.md`: earlier finding IDs and dispositions.
- `docs/unifi-api-contracts-2026-09-08.md`: documented versions and unknown schemas.
- `docs/development.md` and `Tests/NativeAudit/`: existing commands, fixture seams
  and native hazards. Inspect the runner and dependencies before executing them.

Create a private `.build/finish-audit-<unique>/` evidence directory. Record HEAD,
dirty status, file hashes/modes and actual OS, SDK and toolchain versions. Preserve
existing changes, findings, IDs and historical reports. Old logs are reusable
only when relevant input hashes and runtime conditions match.

Build one acceptance matrix for every open or partially verified item. Each row
needs the exact behavior, relevant runtime, existing evidence, smallest next
check and any unavailable input. Check whether prerequisites have actually changed;
do not copy previous blockers or test totals as current facts.

**Done when:** every remaining item has an executable next step or a specifically
named external prerequisite, with no duplicated work queue.

## 2. Use the current local Mantis policy, not obsolete isolation requirements

For applicable security findings, read the currently installed Mantis skills and
their shared `CODEX_EXECUTION.md`, resolving that policy relative to the skill's
real, symlink-resolved directory. The installed Codex-local policy replaces legacy
VM/container, snapshot/shadow-copy and external model-provider requirements.
Older audit reports describe their historical runs, not today's skill contract.

Use relevant review, reproduction, patch and reporting stages against the current
checkout. Preserve finding schemas/history and record actual entrypoint reachability,
commands, outputs and source provenance. Reuse existing artifacts where valid;
do not build a new orchestrator, call external model/embedding APIs, start nested
Codex sessions or require a full campaign for a bounded remaining finding.

Patches are authorized. Capture a failing pre-edit check before each demonstrated
fix, patch in place, verify the benign path and rerun the failing input. Use native
read-only independent review where the skill requires it and delegation is
available/permitted; serialize edits, execution and shared-state writes. Never
describe self-review as independent. Already-fixed findings without sufficient
baseline evidence stay verification-incomplete; do not undo existing fixes merely
to recreate a baseline.

Reserve `VERIFIED_SECURE` for the exact evidence and independent re-attack required
by the current policy, including its diverse valid variants. Fixture passes alone
are not that verdict, and no per-finding result certifies the whole application.

**Done when:** applicable stages have evidence-backed outcomes; missing reachability,
baseline or independence is explicit rather than a fabricated pass or obsolete
“VM required” blocker.

## 3. Close the remaining runtime gates

### Signing and storage

Inspect the current packaging/signature configuration. Use an explicitly selected,
already usable identity only for authorized fixture signing. If a concrete packaging
defect prevents that configured identity from working, make the smallest tested fix;
preserve the existing ad-hoc default and validate the resulting embedded entitlements.
A copied entitlement file or invented team/access group does not grant access.

Exercise production credential/pin implementations through the existing synthetic
namespace adapter: save/update/read/delete, legacy cleanup, process restart,
competing writers, reset intent and scoped cleanup. Preserve backend/query attributes
and exact UUID-specific service **and account** scoping for every operation.

Keep `-34018`, duplicate-write rejection and readback failures visible. An inaccessible
backend is not empty; a failed save is not necessarily rollback. Verify protected
operations only when genuine signing/access prerequisites exist. Signed synthetic
success does not establish access to original application records. Signing transitions
need explicitly authorized identities/setup; fixture-process exit is not power loss.

### Controller contracts and transport

Retest the existing real loopback TLS suite on final source. Preserve certificate
validation, pin continuity/mismatch, same-origin redirects, cancellation/timeouts,
stream and aggregate collection budgets. Extend it only for a concrete coverage gap
or demonstrated defect; retain public-entrypoint versus internal-harness distinctions.

Use explicitly supplied version-labelled sanitized captures or an exact authorized
controller target, access method and read-only operation scope. Check paired sites;
first/middle/last/empty pages; optional failures; older client/device/session/monitoring
shapes; VPN inventory/unknown health; v2 radio fields; and large/multisite responses.
The documented 9.1.120, 9.5.21 and 10.4.57 contracts are not live-version test results.
Keep unknown radio/VPN semantics unknown until evidence supports a correction.

If captures/targets are missing, complete useful synthetic coverage and identify
the exact missing payload/version. Do not discover controllers, retrieve stored
credentials, invent endpoint aliases or weaken limits to manufacture compatibility.

### Native UI and stable-OS release QA

Use the existing real-view fixture harness first. Cover full/compact menus,
short/tall budgets, long/empty/unavailable content, scrolling/footer reachability,
setup/loading/error states, accessibility labels/focus and both diagnostic-copy
paths including one-copy private opt-in. Use fixture clipboard sinks.

For actual MenuBarExtra or full Setup/Preferences coverage, first trace every path
to storage, client creation, updater, reset and login items. Launch only an owned
fixture with verified safe dependencies; a renamed bundle is insufficient. Add the
minimum reusable seam only when it enables a concrete missing check. Keep normal
product launches on real dependencies. Do not operate the user's running app.

Use XcodeBuildMCP if available; otherwise record the native SwiftPM/AppKit fallback.
If public web research is needed, use T3 preview status/open, snapshot before
interaction and condition-based waits. Native UI requires native evidence.

Record actual OS/SDK separately. A beta/newer host, injected screen budget,
programmatic focus or simulated wake does not verify stable macOS 26, physical
display transitions, keyboard/VoiceOver or sleep/network behavior. Complete actual
checks only with the required environment and explicit authorization. Keep #15 open
until all its native acceptance criteria have matching evidence.

**Done when:** each runtime gate is verified at its claimed scope, or reduced to
an exact external input/action after all useful local work is complete.

## 4. Preserve host boundaries and verify final changes

The host boundaries in section 2 of `docs/remaining-audit-prompt.md` continue to
apply. Work in this checkout without VM/container/account/worktree isolation or
source-tree copies. Preserve real credentials, pins, preferences, clipboard, login
items, installed/running apps and system trust. Keep reproducers synthetic, bounded
and loopback-only unless a separate explicit target authorization permits otherwise.

Never run `compile_and_run.sh`, the disabled real-reset test, broad process kills,
unscoped native storage deletion, host-compromising/resource-exhaustion payloads,
OS upgrades or power/network disruption. No installs, signing-key imports, Git
reset/clean/stash/commit/push, or GitHub publication/closure without separate approval.
Treat unavailable permissions as a boundary, not an invitation to bypass controls.

Make minimal shared fixes after inspecting every caller. Leave runnable regressions;
retain fail-closed behavior. Do not suppress errors, remove guards, change fixture
expectations without justification or introduce speculative infrastructure.

Run focused checks, then on final source:

```sh
bash Scripts/check.sh
python3 Tests/NativeAudit/run.py --run-synthetic-native-checks
```

Keep ordinary and native outcomes separate. Native exit 2 is incomplete cleanup,
not a complete pass. Record exact totals, skips, warnings and commands. Check
whitespace including new files, harness syntax, final input hashes and entry/final
worktree preservation. Account for all owned processes/listeners, synthetic keys,
Keychain records and defaults; keep cleanup failures visible. No blanket cleanup.

**Done when:** final-source checks and preservation evidence exist, every new
nontrivial fix has a regression, and owned resources are accounted for.

## 5. Deliver closure, not another indefinite continuation

Write one new uniquely named dated report under `docs/`; preserve historical reports.
For every acceptance-matrix row, choose **fixed and verified**, **verified unchanged**,
**mitigated but unverified**, or **blocked by a named prerequisite**. Link evidence
and distinguish source review, synthetic tests, native fixtures, real controllers,
stable-OS QA and Mantis stage outcomes.

For each remaining blocker, provide the smallest next action and exact needed
artifact/authorization. Never request secrets in chat or commit them. Batch missing
inputs into one short handoff after completing independent work; do not repeatedly
rerun checks whose missing prerequisites are unchanged. Ask before an essential
scope expansion, not before routine in-scope fixes.

Finish concisely with fixes, actual verification totals, report path and remaining
release gates. Claim “all finished” only when every required criterion is verified;
otherwise state “all feasible local work complete” and name what still prevents
release. Stop rather than create another prompt or speculative backlog.
