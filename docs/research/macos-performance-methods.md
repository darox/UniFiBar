# macOS performance measurement methods

Research date: 2026-09-05. Ticket: [Identify trustworthy macOS performance measurement methods](https://github.com/darox/UniFiBar/issues/19).

## Recommendation and scope

Start with **Activity Monitor and Xcode Instruments on a physical Mac running macOS 26+**. Use Time Profiler/SwiftUI for attribution and responsiveness, a separate Allocations recording for memory, and minimal sanitized `OSSignposter`/`URLSessionTaskMetrics` instrumentation only where existing traces cannot answer the question. No new profiling dependency or telemetry service is necessary.

**Do not plan around Power Profiler for this Mac app.** Apple explicitly limits it to iPhone with iOS 26+ and iPad with iPadOS 26+. Activity Monitor's Energy Impact is a **relative measure**, not watts, joules, or a battery-life prediction. [1][2]

This is a measurement proposal, not a performance finding. No app was built, run, profiled, scanned, or connected to a controller. No tools were installed or private source uploaded. Only public Apple documentation was researched. There is no measured baseline, demonstrated bottleneck, or agreed numerical product budget.

## Feasible measurements and restrictions

| Question | Smallest useful tool | What it establishes and what it does not |
|---|---|---|
| Idle CPU/energy | Activity Monitor CPU/Energy; Time Profiler for spikes | CPU behavior, relative Energy Impact, App Nap, and Preventing Sleep. The 12-hour power average is laptop-only and unsuitable for isolating a short experiment. Time Profiler samples running code, not blocked work. [2][3][4] |
| Wakeups | Activity Monitor **Idle Wake Ups**, if exposed on the selected OS; correlate with poll/timer signposts | Apple's archived Mac guide documents sampled timer-wakeup reporting. Current availability/column placement needs local verification. Timer callbacks, thread wakeups, and whole-machine sleep/wake events are not interchangeable. A poll count is a labeled proxy, not a system-wakeup measurement. [5] |
| Memory | Activity Monitor for screening; Allocations with generation marks | Allocations tracks heap and anonymous VM allocation history. It is not interchangeable with physical footprint or resident memory. Record the exact metric/unit and compare retained allocations after repeated interactions, not only one peak. [6][7] |
| Menu responsiveness | Instruments 26 SwiftUI template, Time Profiler, hang/hitch analysis; app-specific signposts if needed | Long body/platform updates and unnecessary updates. Apple explicitly describes macOS AppKit views hosted in SwiftUI. Signposts time an app-defined interval, not automatically click-to-pixels latency. Absence of a hang flag does not prove instant response. [4][8][9][10] |
| Polling latency/overhead | `URLSessionTaskMetrics` plus poll/decode/publish signposts | Task/transaction duration, redirects, connection reuse, resource fetch type, available DNS/TCP/TLS/request/response timings and transaction byte counts. Task duration begins at task creation and excludes subsequent decoding/rendering; one task can have several transactions. [11][12] |

**Versions:** Instruments is bundled with Xcode; the new SwiftUI instrument shipped in Instruments/Xcode 26. Xcode 26 requires macOS Sequoia 15.6+, but a macOS 26-only app still needs macOS 26+ to run. Record exact compatible Xcode, Instruments, and runtime versions. The reviewed SwiftUI guide establishes macOS applicability but does not specify the minimum OS for every diagnostic lane: verify the chosen runtime emits the data. Do not depend on Xcode 27 beta features. `OSSignposter` is available on macOS 12+, and task/transaction metrics on macOS 10.12+; individual newer metric properties still require normal availability checks. [3][8][9][10][11][12][13]

**Do not import iOS assumptions:** Apple's memory guide includes iOS memory-warning, jetsam, and simulator advice, not Mac product memory budgets. Archived Mac energy tools/UI are historical guidance, not guarantees that `timerfires`/DTrace work unchanged today. Do not disable SIP or weaken signing/security controls to obtain traces. If wakeup reporting is unavailable, record that limitation and decide separately whether deeper investigation is justified. [5][6]

## Repeatable capture protocol

These are recommendations for the future measurement task, not executed steps or Apple-mandated sample sizes.

1. **Fix the build and environment.** Use a physical reference Mac and release-optimized build with matching symbols. Confirm the scheme's Profile configuration. Record commit, architecture, macOS/Xcode/Instruments versions, build/signing configuration, instruments, and fixture revision. Keep debugger/sanitizers/allocation stack logging out of primary timing runs; use separate diagnostic passes. Hold power source, Low Power Mode, display settings, background workload, network, and thermal starting state consistent.
2. **Define isolated data and warmup.** Use synthetic data/credentials in an isolated configuration with no route to real controllers; verify all application traffic is contained before any later launch. Fix dataset size, polling interval, error sequence, and cache/connection state. Wait for startup/initial refresh to complete before steady-state recording; keep cold startup separate. Apple's guidance recommends repeated measurement and recognizes external/device-state variation. [1][3]
3. **Predeclare sampling.** Suggested first pass: three independent runs per build/scenario, steady-state idle windows covering at least three configured poll periods, and ten identical open/close interactions per run. These are initial sampling choices, not acceptance thresholds. Extend sampling when variability or slow growth prevents a conclusion. Report count and spread; do not present a reliable tail percentile from a tiny sample.
4. **Capture separate passes.** Use Xcode **Product > Profile**, select the relevant template, record the fixed scenario, stop, and save locally. Start with lightweight CPU/energy screening, then SwiftUI/Time Profiler with needed signposts, and Allocations separately. Collecting every instrument at once is unnecessary; compare builds with identical settings. Apple documents these workflows. [3][6][8]
5. **Compare like with like.** Alternate baseline/candidate order where practical. Preserve per-run values plus median/range and record anomalies rather than silently discarding slow runs. Call noise-dominated differences inconclusive. A lower CPU number achieved through stale data, missing refreshes, suppressed errors, or fewer completed interactions is not an optimization. Set product budgets only after measurement and maintainer agreement.

### Scenario matrix

| Scenario | Action | Evidence |
|---|---|---|
| Menu closed | Leave menu closed with unchanged synthetic polling results; changed data is a separate case | CPU over a fixed interval, relative energy, available wakeups, actual polls/transactions/bytes, repeated view work, start/end memory. User-idle with scheduled work is not no work. |
| Menu interaction | Repeat the same open/close, selection, and refresh; separate first/warm opens and data-ready/loading states | Named phase durations, main-thread hot stacks, long SwiftUI updates/causes, and hang/hitch evidence. |
| Polling stress | Synthetic delayed response, timeout, authentication failure, and large dataset | Request cadence/overlap, retry amplification, cancellation, bytes, network versus decode/publication duration, responsiveness during refresh. No external fault injection. |
| Long-lived behavior | Repeat poll/menu cycles and return to the same state; allow pending work to finish | Memory growth versus plateau, retained allocations between generation marks, unexpected persistent work. A cache plateau is not automatically a leak. |
| Recovery | After approval of isolated runtime testing: sleep/resume or simulated recovery with synthetic data | Duplicate/burst work, time to useful state, eventual idle. Keep separate from steady-state comparisons and real-controller access. |

## Avoid misleading results

- **Name the real boundary.** Poll-cycle signposts may enclose fetch/decode/model publication, split only where needed. A menu callback-to-model-ready interval is not click-to-first-frame latency: `body` completion or `onAppear` is not proof the pixels appeared. Correlate UI events with SwiftUI/render evidence and observation. Use unique IDs for overlapping intervals and pair begin/end on errors/cancellation. [8][10]
- **Sampling is not exact call timing.** Apple demonstrates different call counts/durations producing identical Time Profiler samples. Add a signpost for precise operation timing; use Thread States to investigate blocked work, not to prove a hang. [4]
- **Keep unavailable network measurements unavailable.** Incomplete phases can have `nil` timestamps; reused/proxied connections may lack fresh TLS timings. Missing is not zero. Separate tasks, transactions, redirects, reuse, and resource fetch type. Store only the required numeric/enum data, not entire metrics/request/response objects. [11][12]
- **Label fixture limitations.** In-process response stubs test scheduling/model/UI work, not real DNS/TLS/sockets/controller load. Loopback HTTP(S) exercises more URL Loading System behavior but cannot predict LAN/controller latency or energy. Injected delay tests application behavior under delay. Real-controller measurements need later explicit read-only authorization; do not silently combine their results with fixture baselines.

## Privacy and approval gates

Use static signpost names and metadata-only results: no URL, hostname, IP/MAC address, username, site/device name, cookie, token, or request/response body. Task metrics contain request/response objects; logging the whole object defeats that restriction. Treat stacks, filesystem paths, memory graphs, and screenshots as potentially sensitive. [10][12]

**HTTP Traffic is not the default for real sessions.** Apple says it records both encrypted and unencrypted HTTP traffic **unencrypted in trace documents and system logs**, including headers/bodies. HTTPS therefore does not protect captured credentials/controller data. Deleting a trace or redacting a screenshot does not remove the system-log copy. Use only synthetic credentials/data in isolation by default. Real-session capture needs specific approval of contents, storage, readers, and retention. [14]

Keep raw traces/graphs/logs in restricted local storage outside Git; publish only reviewed aggregate findings and synthetic reproductions. Obtain separate approval for real-controller access and source/trace uploads to cloud tools. This research ticket authorizes neither profiling, privileged commands, production instrumentation, nor tool installation.

## Human decisions remaining

1. Choose the reference Mac and compatible Xcode/macOS pair plus a controlled capture window.
2. Approve a fixture-only measurement task and any demonstrably necessary minimal instrumentation.
3. Decide whether real-controller validation is necessary; name the target, read-only credentials/actions, and artifact policy separately.
4. After baseline collection, agree data freshness/responsiveness alongside CPU/energy/memory goals and prioritize measured improvements.

## Primary sources

Apple-owned sources inspected for this report; archived guidance is explicitly labeled.

1. [Measuring your app’s power use with Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler) — iOS/iPadOS availability, power metric limits, repeat comparisons.
2. [View energy consumption in Activity Monitor on Mac](https://support.apple.com/guide/activity-monitor/view-energy-consumption-actmntr43697/mac) — relative Energy Impact, laptop-only 12-hour metric, App Nap/sleep prevention.
3. [Monitor Usage Regularly — Mac Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/MonitoringEnergyUsage.html) — archived CPU/energy/Instruments guidance.
4. [Analyze hangs with Instruments — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10248/) — all-platform analysis; sampling/signposts at 16:50, blocked-thread diagnosis at 36:41 onward.
5. [Minimize Timer Usage — Mac Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html) — archived timer-wakeup diagnostics and tolerance.
6. [Gathering information about memory use](https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use) — Allocations/generations, memory graphs, iOS-specific caveats.
7. [View memory usage in Activity Monitor on Mac](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac) — Mac memory screening.
8. [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) — template workflow, AppKit updates, frequency/causes.
9. [Optimize SwiftUI performance with Instruments — WWDC25](https://developer.apple.com/videos/play/wwdc2025/306/) — Instruments 26 SwiftUI instrument.
10. [OSSignposter](https://developer.apple.com/documentation/os/ossignposter) — macOS 12+, interval semantics, visualization.
11. [URLSessionTaskMetrics](https://developer.apple.com/documentation/foundation/urlsessiontaskmetrics) — macOS 10.12+, task interval, transactions/redirects.
12. [URLSessionTaskTransactionMetrics](https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics) — timings, missing phases, bytes, reuse, request/response and proxy considerations.
13. [Xcode 26 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes) — SDK, host requirement, instruments.
14. [Analyzing HTTP traffic with Instruments](https://developer.apple.com/documentation/foundation/analyzing-http-traffic-with-instruments) — macOS support and unencrypted trace/system-log warning.
