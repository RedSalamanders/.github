# I61 implementation and evidence — 2026-11-09

This is a partial implementation record for the [active organization plan](../../Plans/WIP/TestingAndIntegrationAcceleration_2026-11-09.md). Overall speed targets and hosted acceptance remain open. No release, publication, account or billing operation was performed.

## Source and obligation inventory

[inventory.json](inventory.json) records six client heads, deployed engine pins, distinct DxUi pins/API revisions, native scope names, compiler-free PR coverage and effective main rules observed through GitHub's branch-rules API. The shared engine was based on `570351e14d469f2b1cefa7762fc64c1c24a4adf7`. Organization discovery returned exactly these six clients and `.github`; none was archived.

| Owner | Current local and hosted obligations | Acceleration boundary |
|---|---|---|
| RedSalamander | Affected/family iteration; PrePush accounts for applicable local profiles. Explicit CI/Full, ASan, native architecture, desktop/device/performance and production extraction retain separate gates. | Existing focused ProjectName builds do not establish a complete partial-target receipt. New transport and prose classification change neither coverage nor trust. |
| DxUi | Affected native/tooling scopes, explicit completion profiles, native filter/watchdog checks, performance, consumer qualification and SDK extraction. Hosted normal is Release on both architectures. | Bounded ordinary workers and exact local preflight reuse; performance, foreground and consumer qualification remain independently required. |
| RedPrism | Affected tooling/runtime suites and their direct/integration closure; explicit Full/PrePush profiles and storage/runtime/stress/performance qualification. | Existing content-attested affected planning retained; no narrowed executable graph enabled. |
| RedTilde | Affected scopes, application/editor/storage/recovery/crash integration, explicit completion profiles and production smoke. | One application compilation already covers much of the runtime; do not invent target-level savings without a separate runtime/build model. |
| RedXe | Affected scopes, settings/plugin/host/package integration, explicit completion profiles and production extraction. | Host/plugin/deployment consumers remain included; no partial solution receipt is being advertised. |
| RedMonitor | Debug affected validation; Full/PrePush additionally cover Release/ASan, ARM64 cross-builds, live ETW and installation. Native ARM64 and manual UI/performance remain separate. | Current wrapper is a broad affected lane, not a fine-grained path planner. Model/client changes cannot silently skip viewer metadata and transport obligations. |
| Shared .github | Compiler-free PRs and schedules; five-minute main admission; x64 and native ARM64 Release regression before either production job; explicit diagnostic/publication workflows. | ABI-cache reuse supplies package inputs only. No required native candidate check or trusted main-adoption path has been enabled. |

The observed effective rules contain no merge-queue requirement or strict-base native candidate check. RedPrism's effective branch rules currently contain no required status checks. This is configuration evidence, not an invitation to weaken existing validation. S7 requires a concrete, accepted native gate before any equivalent local/main work can be relocated.

## Executed checks

- Shared engine: `Tools/Test-Workflows.ps1 -Root .` validated eight workflows; `Tests/Test-Engine.ps1 -TestRoot Z:/RedSalamander.Perf` passed **50/50** behavioral cases. [Raw result](engine-results.json). Native application qualification is not part of those fixtures.
- RedSalamander: the final focused planner, public wrapper, canonical result transport and scheduling pass completed **130/130** cases. Tool inventory and spec inventory each reported zero blocking findings. A RequiresBuildToolchain case requires real profile evidence and was not counted as a compiler-free pass.
- DxUi: scoped testing passed **38 cases**, including actual child-process forwarding, changed worker-limit identity, exact preflight reuse, native-source/binary/detector changes, expiry, forced/hosted freshness, failure and mutation. Parallel scheduler process tests passed **4 cases**.
- Existing sibling checks: RedPrism scoped tests passed **27 cases**; RedTilde **54**; RedXe **33**; RedMonitor build controls **41**. These do not qualify product runtime behavior.
- DxUi x64 Release canonical build passed with zero warnings/errors, elapsed **7 min 1 sec**. The first serial native attempt (Foundation, Embedded, Grid, Theme) then failed: Embedded terminated with `0xc0000409`; the other three suites and 8 filter/12 watchdog controls passed. The failed run remains failed and is not a concurrency benchmark. No ARM64 runtime or foreground acceptance is inferred.

The serial failure is retained at DxUi run `20261109T130229552Z-81776-d3ff2e9c1cd84dbeb130432cab0e8b22`, with native EXE/PDB hashes and a member-verified archive, dump and `ordinary.record`. Symbol resolution against the matching PDB identifies `PreparedLayoutAccess::Prepare` at `src/Controls/DxUi.RichTextLayout.cpp:447`, called by `TestRichDocumentGeometryMaximumStorageBudget`. DirectWrite raised a C++ exception internally during `GetOverhangMetrics`; the existing native allowance covered only the preceding `GetMetrics`. The narrow repair extends the same canonical native-call boundary to overhang metrics; HRESULT handling and observation of SDK allocations/reentrant scopes remain required. Rebuild and regression acceptance are pending. Hosted parallelism stays serial while comparison is unqualified.

## Measured and rejected optimizations

[pattern-measurements.json](pattern-measurements.json) retains four baseline/candidate rounds in each of en-US and tr-TR using the same 168 paths and current rule sets plus literal/Unicode/wildcard controls. Every decision bit matched. RedSalamander matching mean was 1,265.35 to 312.43 ms (en-US), and 1,201.64 to 296.19 ms (tr-TR). These are matcher-corpus timings, not end-to-end test latency or the plan's 3x/2x target. Only RedSalamander retained the cache; sibling/shared-engine variants showed marginal or noisy benefit and were removed. Cache entries are bounded immutable matchers, with no source, selection or result caching.

A separate paired source-hashing experiment preserved exact digests and detected a same-size/timestamp-restored edit, but had no reliable organization-wide gain. Real RedTilde mean changed from 139.18 to 149.51 ms; the candidate was removed everywhere. Raw fixtures remain in the marked sandbox, under the `i61-source-hash-45394b1c623b435392d563a0c1af1545` study. No speedup is claimed from it.

Whole restored DxUi trees currently range from about 0.49 to 20.59 GiB across clients, including accumulated checkouts/intermediates/dependencies. Blindly uploading that tree would be an expensive substitute for a compact immutable SDK. S3 still requires the latter's complete identity, symbols/licenses, atomic publication, ownership and consumer integration; the vcpkg change does not claim to provide it.

## Remaining acceptance

The 3x warm component and 2x end-to-end objectives are unchanged and unproved. S2, full S3/S4/S5, S6B and S7–S10 remain open. Preserve the WIP plan until the accepted implementation, comparisons, native/hosted qualification and normative closeout are complete. A working-branch pin, cache hit, compilation or local fixture pass cannot close those gates.
