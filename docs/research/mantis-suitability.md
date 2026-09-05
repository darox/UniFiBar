# Google Mantis suitability and safe execution requirements

Research for [#17](https://github.com/darox/UniFiBar/issues/17), 2026-09-05.
Upstream pinned revision: `google/mantis@d13c93fb8e9779801711daea0d65fffa133c3b2d`.

**Recommendation:** consider a narrow, human-supervised static-review pilot only
after approving the model/data boundary and an isolated environment. Defer
dynamic macOS reproduction until its containment and build setup are agreed.
This is a tooling assessment, not a security audit of UniFiBar.

## Verified capabilities and limits

- Mantis is a modular security-review **skills toolkit for coding agents**. Its
  documentation says it is platform-agnostic, has been used with Gemini CLI,
  Antigravity, and Google ADK, and should work with other coding-agent frameworks.
  It is explicitly **not an officially supported Google product**, is intended
  for demonstration, and is not intended for production use. [S1]
- The default skills emphasize generic security, business logic, and
  authorization in web/cloud applications. They can be adapted to other domains;
  custom isolated VMs and testbeds are documented adaptation paths. The inspected
  guides do **not** establish a dedicated Swift/macOS integration or verified
  coverage of AppKit, Keychain, signing, entitlements, or macOS-specific trust
  behavior. Stack-agnostic is not a coverage guarantee. [S1][S2]
- Manual use requires a configured coding agent. The optional ADK reference
  harness adds Python/venv, configuration, and a selected execution backend.
  Its `static-only` backend skips dynamic exploit execution and patch testing;
  other documented backends include gVisor, microsandbox, and GCE. Static-only
  removes the dynamic sandbox requirement, **not** model, data, or orchestration
  safety considerations. [S1][S3]

**Applicability inference, not tested support:** source-level Swift review is
plausible, with macOS-specific threat-model adaptation. Tests depending on Apple
frameworks and OS security behavior need an appropriate isolated macOS/Xcode
setup; default Linux-oriented container examples cannot establish those results.
Portable logic could be tested separately, but that would not prove whole-app
exploitability. No setup or compatibility check was run.

## Mandatory safety and evidence boundaries

1. **Contain the agent as well as the payload.** Upstream warns never to run the
   suite on a machine with access to production systems, sensitive data, or
   internal networks. Use a dedicated restricted environment and an approved
   source-only snapshot, without personal credentials, host Keychain, controller
   access, or sensitive host mounts. Human prompts are not a containment boundary.
   Unattended operation requires hardened isolation; the GCE guidance includes
   restricted egress, VPC Service Controls, and least-privilege identity. [S1][S2]
2. **No host-run reproducers.** The reproduce skill prohibits host execution.
   Payloads run inside isolation; local services may be enabled for functional
   tests, but must not expose the environment to the external internet. Prefer
   no network; any controller simulation belongs inside the isolated testbed,
   never against a real controller. [S4]
3. **Preserve uncertainty.** The documented flow builds architecture/threat model
   and a scoped plan, researches findings, deduplicates, reviews false positives,
   criticizes practical viability, reproduces, patches, calibrates risk, and
   reports. Begin with a narrow pass, not an autonomous repository-wide loop.
   Record target revision, evidence, assumptions, reproduction status, and test
   limits. A skipped/blocked reproduction is not a clean bill of health. [S1][S2]
4. **Validate through real boundaries.** The reproduce skill requires sandboxed
   public-interface/end-to-end evidence for its authoritative `reproduced`
   verdict; private-function harnesses are only intermediate evidence. Failed
   reproduction does not prove a false positive, and a successful reproducer
   does not establish exploitability in every deployment. Findings require
   manual security-expert verification before reporting; patches also need
   independent review and regression validation. [S1][S4]

## Model, private data, and cost: not yet approved

Mantis skills do not universally require Google credentials: they can use an
existing coding-agent framework. The optional reference harness documents Google
Cloud Application Default Credentials **if using Vertex AI**, plus configurable
models. Its reference architecture also describes configurable embedding-model
calls, so data approval must cover auxiliary calls, not just the principal chat
model. [S1][S2][S3]

No provider, model, hosting arrangement, retention policy, region, API quota, or
spending cap has been selected or verified. Hosted review would send supplied
source/context to that provider; the inspected documentation does not establish
automatic secret redaction or a blanket private-data guarantee. No fixed campaign
price is established: model/token use, repeated passes, embeddings, sandbox
compute, and storage depend on the chosen configuration. Check current official
provider pricing and data terms **after** choosing candidate configurations;
this report authorizes neither spending nor private-code disclosure.

## Minimal next decisions

| Option | What it can establish | Approval needed |
| --- | --- | --- |
| Narrow static pilot (recommended first) | Threat model, prioritized candidate findings, explicit coverage gaps; no dynamic validation | Exact files/snapshot, provider/data terms, budget, restricted environment, human reviewer |
| Isolated macOS reproduction after triage | Test selected findings against relevant Apple runtime behavior | macOS/Xcode testbed and containment, synthetic data/services, execution scope and budget |
| Defer Mantis execution | Continue planning without new tooling or data exposure | None; retain unresolved setup decisions |

No Mantis installation, scan, generated-code execution, host/Keychain/network
testing, controller contact, or repository-source upload occurred for this
research. Only public upstream documentation was retrieved for the assessment.

## Primary sources (immutable revision)

[S1]: https://github.com/google/mantis/blob/d13c93fb8e9779801711daea0d65fffa133c3b2d/README.md
[S2]: https://github.com/google/mantis/blob/d13c93fb8e9779801711daea0d65fffa133c3b2d/README_AGENTS.md
[S3]: https://github.com/google/mantis/blob/d13c93fb8e9779801711daea0d65fffa133c3b2d/reference/README.md
[S4]: https://github.com/google/mantis/blob/d13c93fb8e9779801711daea0d65fffa133c3b2d/mantis-reproduce/SKILL.md

- [S1: Overview, safety, setup, and workflow][S1]
- [S2: Agent reference, adaptability, model selection, and cloud hardening][S2]
- [S3: Optional ADK harness and static/dynamic backends][S3]
- [S4: Reproducer isolation and evidence contracts][S4]
