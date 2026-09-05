# Isolated GPT-6 Astra route and CHF 10 cap: feasibility

Research for [#23](https://github.com/darox/UniFiBar/issues/23), 2026-09-05.
Binding design: [security pilot approval](https://github.com/darox/UniFiBar/issues/18#issuecomment-5551446848).

**Result: not established; execution remains blocked.** Public documentation
supports the component technologies, but does not establish this account's exact
existing T3/Codex route, review-scoped credentials, model-only egress, or a strict
CHF 10 ceiling. Preserve GPT-6 Astra and all approved boundaries. Defer execution
pending administrator-supported evidence; do not substitute models, introduce
API billing, copy host authentication, or weaken isolation.

## Capability assessment

“Supported” below means documented, **not deployed or tested here**. “Unsupported”
means a cited mechanism does not provide the required guarantee, not that all
possible implementations are impossible.

| Requirement | Status | Evidence and remaining condition |
| --- | --- | --- |
| Exact GPT-6 Astra identity | Supported in public docs; existing route unknown | OpenAI publishes `gpt-6-astra`. That does not identify this T3 instance's provider endpoint, account entitlement, or billing mode. [O1] |
| Guest-resident agent/runtime | Components supported; combined deployment untested | Codex CLI supports Linux. T3 supports a remote server with provider installation/authentication on that machine. [O2][T2][T3] |
| Authentication without copying host stores | Documented options; account suitability unknown | Fresh device login and scoped Codex access tokens exist, subject to account/admin policy. Neither proves repository-only authority. [O3][O4] |
| Host/LAN exclusion | Lima defaults insufficient | Plain mode removes integrations, not network access; user-mode networking exposes a host-loopback address. [L1][L2] |
| Strict CHF 10 campaign cap | Not established | Subscription limits are not currency caps. API hard limits exist but permit delayed-enforcement overshoot. [O5][O6] |

## Runtime, route, and authentication

**First-party provenance:** `t3.codes` links to `pingdotgg/t3code`, which links
back to that site. T3 says it orchestrates provider subscriptions rather than
reselling tokens. Public T3 documentation/source was pinned to
`be7796d867a1e66524f19e6cfee0109c3ab447f0`; this is not a claim about the installed
build's revision. [T1][T2]

The documented candidate is **T3 server inside the guest → guest Codex CLI /
app-server → approved OpenAI route**. T3 provides a headless server and
SSH-managed remote environments; provider binaries and credentials belong on
the environment's machine. Its Codex adapter uses the app-server integration.
OpenAI documents `codex app-server` with default stdio transport and model
selection/discovery through `model/list`. No model request was made. [T2][T3][T5][O7]

A host-side UI is not automatically host-side tool confinement. The reviewer
must have no host MCP/browser/computer-use bridge, host shell endpoint, shared
Codex home, forwarded agent/socket, or other-project access. Use a fresh guest
home and separate `CODEX_HOME`, **without a shadow home**; T3 explicitly documents
that separate homes separate configuration and sessions. A new thread is needed,
not continuation through shared host state. [T4] These are design requirements,
not verified properties of the current session.

Authentication candidates, not approvals:

- **Fresh device authentication:** Codex documents headless `codex login
  --device-auth`, enabled by the user/workspace administrator. It avoids copying
  the host cache but creates account-linked credentials. Its documented scope
  does not establish “this repository and this pilot only.” The documented
  auth-cache-copy fallback is explicitly excluded here. [O3]
- **Finite Codex-only access token:** OpenAI documents `CODEX_ACCESS_TOKEN` for
  CLI/app-server, with workspace permissions, expiry, and revocation. It acts as
  its creator and is distinct from an app-server transport credential. Codex
  product scope is not a per-repository or CHF spending scope. Availability and
  preservation of this account's existing route require admin confirmation. [O4]

Minimum acceptable material is one separately issued, revocable pilot credential
with confirmed minimum authority, provisioned by a human through an approved
secret channel; no host auth/config copying. No supplied evidence establishes
such a credential for this account. Guest processes/tools must not inherit it
unnecessarily or expose it in logs. A fresh login alone is not credential
least-privilege proof.

**Exact route blocker:** obtain a non-secret administrator statement of provider,
auth mode, account/workspace, endpoint identities, exact model availability,
service tier, and applicable billing/data terms. Public model identity is now
verified, but silently replacing a subscription route with the public Responses
API would still change the approved arrangement. An existing host proxy would
also conflict with host-service denial unless explicitly resolved; do not assume
one exists or copy its settings.

## Lima containment: documented settings are not a tested boundary

Read-only local discovery identified `limactl` 2.2.0 on an arm64 macOS 27.0 host.
No VM inventory, contents, host credentials, or private runtime configuration
were inspected. The following documentation was reviewed against that version:

- `plain: true` disables mounts, dynamic port forwarding, containerd, guest
  agent, Rosetta, and agent forwarding. **Static forwarding, provisioning, and
  management SSH remain possible.** Plain mode is not deny-all networking. [L1]
- Use a separate `LIMA_HOME` and do not preserve the host environment. Review the
  fully rendered configuration, including inherited bases: the default template
  can inherit host-home sharing. Explicitly exclude shares and optional
  forwarding; `ssh.forwardAgent`, `ssh.loadDotSSHPubKeys`, `ssh.forwardX11`, and
  `propagateProxyEnv` must not introduce host access. Management port 22 is not
  removed by ordinary `portForwards` rules. [L3][L4]
- User-mode networking exposes host loopback through `192.168.5.2` /
  `host.lima.internal`. Disabling `hostResolver` does not block host reachability
  and can fall back to host DNS. An independent default-deny boundary must cover
  IPv4/IPv6, host gateways, LAN, link-local/metadata, DNS, proxy bypass, and general
  internet egress. Permit only the confirmed model route; no endpoint allowlist
  or enforcing component has yet been established. [L2]
- `user.passwordlessSudo: false` is insufficient by itself: the documented setup
  saves an initial password and grants administrative/journal-related group
  membership. Use a dedicated non-admin reviewer without access to that password,
  sudo, privileged sockets, or boundary controls. Containment must be outside
  reviewer authority. [L5]

The management path also needs explicit treatment: a T3 SSH/UI connection must
not become general guest-to-host access or a host tool bridge. T3 Connect,
Tailscale, remote UI relays, or unrelated telemetry cannot be added implicitly to
“model-only egress.” No runnable configuration is warranted until routing and
enforcement are settled. A Linux static pilot cannot validate macOS runtime or
Keychain behavior.

## Accounting and strict-cap gap

OpenAI distinguishes ChatGPT subscription authentication from usage-based API
keys. Codex usage follows the chosen plan/workspace; its current pricing guide
allows an active turn to continue after reaching usage limits. This is not a
per-pilot monetary stop. T3's bring-your-own-subscription statement does not
establish the user's plan, available credits, or overage behavior. [O3][O5][T1]

**Conditional API reference only:** the opened GPT-6 Astra model page lists USD
per million tokens: input $10, cached input $1, cache writes $12.50, output $50.
Long-context and service-tier adjustments apply. These are not a quote for this
existing Codex route or a conversion into CHF. [O1]

The current API documentation supports organization/project **hard spend
limits**, unlike mere alerts, but explicitly warns that enforcement is not
instantaneous and recorded spend can exceed the limit. It provides no numerical
maximum overshoot here. Consequently setting the CHF-equivalent amount does not
prove the requested ceiling, even if API billing were authorized. [O6]

For a genuine cap, an approved accounting mechanism must cover committed and
pending requests, retries/concurrent work, reasoning/cache charges, any auxiliary
model/tools/embeddings, and infrastructure/storage charges. It must account for
applicable currency conversion, taxes/fees, and any other usage sharing the same
allowance. These are verification requirements, **not a proposed custom billing
system**. No supporting bound exists for this arrangement. Token estimates,
post-hoc dashboards, or an arbitrary safety margin do not replace CHF 10.

## Fail-closed preflight for a later task

1. **Route:** record exact installed runtime versions, guest entrypoint, approved
   endpoint/auth identities, `gpt-6-astra` entitlement, and service tier. Resolve
   uncertainty before source or paid requests; never silently fall back.
2. **Authority:** approve the pilot credential, issuance/revocation, and
   data-handling terms. Verify effective tools/configuration exclude host
   bridges, inherited stores, connected apps, and unapproved auxiliary services.
3. **Containment:** inspect rendered Lima/OS policy; validate denial using
   synthetic canary resources, not real controllers or sensitive host services.
   Test mounts, privilege escalation, forwarding, host/LAN/metadata, IPv4/IPv6,
   DNS/proxy bypass, and approved-route-only egress. Record evidence separately
   from documentation claims.
4. **Money:** establish provider/admin-backed hard accounting including pending
   and ancillary charges. Verify stop/restart/failure behavior with a non-billing
   fixture where available. If CHF 10 cannot be proven, stop for a human decision.
5. **Execution gate:** approve the source snapshot and URL/TLS/credential static
   scope, then authorize the later pilot explicitly. Block all dynamic
   reproduction, macOS/Keychain testing, controller contact, and automatic patches.

**Smallest current action:** keep the pilot deferred and request the route,
authentication, and budget evidence. No fully compliant executable configuration
was established. No installation, VM launch, credential retrieval, paid-model
call, source upload, Mantis execution, or security audit occurred in this research.

## Sources

OpenAI pages were searched and opened on 2026-09-05; they can change. T3 links
below are pinned public source. Lima documentation describes configuration, not
validated isolation in this environment.

[O1]: https://developers.openai.com/api/docs/models/gpt-6-astra
[O2]: https://learn.chatgpt.com/docs/cli
[O3]: https://learn.chatgpt.com/docs/auth
[O4]: https://learn.chatgpt.com/docs/enterprise/access-tokens
[O5]: https://learn.chatgpt.com/docs/pricing
[O6]: https://developers.openai.com/api/docs/guides/spend-limits
[O7]: https://learn.chatgpt.com/docs/app-server
[T1]: https://t3.codes/
[T2]: https://github.com/pingdotgg/t3code/blob/be7796d867a1e66524f19e6cfee0109c3ab447f0/docs/user/install.md
[T3]: https://github.com/pingdotgg/t3code/blob/be7796d867a1e66524f19e6cfee0109c3ab447f0/docs/user/remote-access.md
[T4]: https://github.com/pingdotgg/t3code/blob/be7796d867a1e66524f19e6cfee0109c3ab447f0/docs/user/providers-codex.md
[T5]: https://github.com/pingdotgg/t3code/blob/be7796d867a1e66524f19e6cfee0109c3ab447f0/apps/server/src/provider/Layers/CodexAdapter.ts
[L1]: https://lima-vm.io/docs/config/plain/
[L2]: https://lima-vm.io/docs/config/network/user/
[L3]: https://lima-vm.io/docs/config/environment-variables/
[L4]: https://github.com/lima-vm/lima/blob/v2.2.0/templates/default.yaml
[L5]: https://lima-vm.io/docs/config/sudo/

- OpenAI: [model][O1], [CLI][O2], [authentication][O3], [access tokens][O4],
  [Codex pricing][O5], [API spend limits][O6], [app-server][O7].
- T3: [official site][T1], [installation][T2], [remote environments][T3],
  [Codex homes][T4], [Codex adapter][T5].
- Lima: [plain mode][L1], [user networking][L2], [environment][L3],
  [v2.2.0 template][L4], [sudo][L5].
