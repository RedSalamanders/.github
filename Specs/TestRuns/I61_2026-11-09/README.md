# I61 implementation and evidence — 2026-11-09

This is a partial implementation record for the [active organization plan](../../Plans/WIP/TestingAndIntegrationAcceleration_2026-11-09.md). Overall speed targets and remaining hosted acceptance stay open. No release, publication, account or billing operation was performed.

## Integrated changes and hosted acceptance

The reviewed engine source `fbe6a707eb5d11847ac1a982d1c3851ea32b2baf` was integrated in
[engine PR #19](https://github.com/RedSalamanders/.github/pull/19). All six client pins and generated callers
match that source. Normal integration completed for [RedPrism #10](https://github.com/RedSalamanders/RedPrism/pull/10),
[RedTilde #99](https://github.com/RedSalamanders/RedTilde/pull/99), [RedXe #77](https://github.com/RedSalamanders/RedXe/pull/77),
[RedMonitor #39](https://github.com/RedSalamanders/RedMonitor/pull/39) and [DxUi #229](https://github.com/RedSalamanders/DxUi/pull/229)
after their applicable hosted checks passed. No branch-protection bypass was used.
[RedSalamander #209](https://github.com/RedSalamanders/RedSalamander/pull/209) has passing required compiler-free
checks and remains open for Entire reviewer approval; its new runner handoff has no final hosted native acceptance yet.

[hosted-rollout.json](hosted-rollout.json) freezes the observed run/source/job/phase snapshot with direct run links.
RedMonitor run 42626422908 passed both native Release regression branches, the AND test gate, both production
build/smoke branches and completion. RedTilde and RedXe passed both native regression branches; their production
jobs were still running at the snapshot. RedPrism and DxUi remained in native regression. Pending jobs are not passes.
These runs differ from the historical samples in source and cache state and cannot establish a controlled speedup.

## Follow-up implementation and capability evidence

[DxUi #230](https://github.com/RedSalamanders/DxUi/pull/230) merged as f73da6db47d0afa198d855e82620a0088daac7ed.
It adds selected target-union builds and receipts, the affected iteration baseline and the corrected preflight
ordering assertions. Complete local tooling validation, 43 scoped cases, 43 build/SkipBuild policy cases and
hosted compiler-free checks passed. Its [selected-build evidence](https://github.com/RedSalamanders/DxUi/blob/main/Measurements/TestingAcceleration_2026-11-09/selected-builds.json)
retains source patch/input/image hashes, exactly three cold-build targets, six output files and native results.
Cold build elapsed 148 seconds; default selected build with pre/post attestation elapsed 192 seconds. Both cold
native suites passed, including 583,358 Embedded checks. Actual Full and Grid requests refused partial proof
before native work; matching public Foundation follow-up reused its passed result in about 9.4 seconds.
These are subset diagnostics, with source-revision limits stated by the owning record, not the overall target.

RedTilde [#100](https://github.com/RedSalamanders/RedTilde/pull/100) merged old-baseline failure/interruption
revocation and a reentrant profile lease after 57 scoped cases, all validators and hosted checks passed.
RedPrism [#11](https://github.com/RedSalamanders/RedPrism/pull/11) merged as d7c53c618513ac9d5c44eac063a766d8a075f30a
with the same controls after 30 scoped cases, 76 native-ARM refusal controls, complete validation and hosted checks passed.

The first-wave DxUi x64 hosted regression at 5f65003 failed on the two stale direct-watchdog assertions before
product suite execution. Its raw log is preserved in DxUi `.build/i61-hosted-first-wave-x64.log`. The failure
is not reclassified; #230 fixes it and needs a new source-bound hosted run. RedMonitor, RedTilde and RedXe's
first-wave normal qualification completed successfully on both native regression and production architectures.

Engine [#21](https://github.com/RedSalamanders/.github/pull/21) added the manual compiler-free SDK artifact access
probe. [Run 42641065137](https://github.com/RedSalamanders/.github/actions/runs/42641065137) passed with the engine
repository's ordinary read-only workflow token. [sdk-artifact-access.json](sdk-artifact-access.json) records HTTP
302 authorization for the exact existing qualified DxUi production-x64 artifact at 2a26dfbd5df4ea2af9cd7742677c17326f3bfa94.
No SDK contents, credential or signed URL were retained. This proves only that caller's access capability;
it neither qualifies a cache entry nor proves all five consumer tokens/configurations. The artifact source does
not match the consumers' current three pins. Native source-build fallback remains mandatory on any mismatch.

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

The serial failure is retained at DxUi run `20261109T130229552Z-81776-d3ff2e9c1cd84dbeb130432cab0e8b22`, with native EXE/PDB hashes and a member-verified archive, dump and `ordinary.record`. Symbol resolution against the matching PDB identifies `PreparedLayoutAccess::Prepare` at `src/Controls/DxUi.RichTextLayout.cpp:447`, called by `TestRichDocumentGeometryMaximumStorageBudget`. DirectWrite raised a C++ exception internally during `GetOverhangMetrics`; the existing native allowance covered only the preceding `GetMetrics`. PR #229 extends the same canonical native-call boundary to overhang metrics; HRESULT handling and observation of SDK allocations/reentrant scopes remain required. The subsequent canonical x64 Release rebuild passed with zero warnings/errors in 6 min 19 sec. The original failure remains failed.

The [DxUi measurement package](https://github.com/RedSalamanders/DxUi/tree/main/Measurements/TestingAcceleration_2026-11-09)
retains an exact compressed candidate patch, source identity, ordered case lists and image hashes. Its serial
run `20261109T131955474Z-74628-95d33a4f550243ca90b1394f455f1a7f` and parallel-2 run
`20261109T132823197Z-28960-df5daf385fed47e2884f517480183b9c` used the same binaries, passed all 19 requested
nonforeground suites, the same 1,726 named cases and zero capability skips. Elapsed time was 441,376.8 ms versus
335,173.6 ms: 24.1% less, 1.317x, in one pair. This is neither a median/p95 nor the overall acceleration target.
The archived source predates the subsequent engine-only pin update; it is not final-head whole-project qualification.
Two alternating prerequisite measurements were 1,029.8/23,263.0 and 920.2/23,178.8 ms for reused/fresh native
filter/watchdog verification. Performance and desktop prerequisites were not cached. Hosted scheduling stays serial
pending native architecture acceptance; ARM64, Debug/ASan, consumers and foreground work remain separate.

## Measured and rejected optimizations

[pattern-measurements.json](pattern-measurements.json) retains four baseline/candidate rounds in each of en-US and tr-TR using the same 168 paths and current rule sets plus literal/Unicode/wildcard controls. Every decision bit matched. RedSalamander matching mean was 1,265.35 to 312.43 ms (en-US), and 1,201.64 to 296.19 ms (tr-TR). These are matcher-corpus timings, not end-to-end test latency or the plan's 3x/2x target. Only RedSalamander retained the cache; sibling/shared-engine variants showed marginal or noisy benefit and were removed. Cache entries are bounded immutable matchers, with no source, selection or result caching.

A separate paired source-hashing experiment preserved exact digests and detected a same-size/timestamp-restored edit, but had no reliable organization-wide gain. Real RedTilde mean changed from 139.18 to 149.51 ms; the candidate was removed everywhere. Raw fixtures remain in the marked sandbox, under the `i61-source-hash-45394b1c623b435392d563a0c1af1545` study. No speedup is claimed from it.

Whole restored DxUi trees currently range from about 0.49 to 20.59 GiB across clients, including accumulated checkouts/intermediates/dependencies. Blindly uploading that tree would be an expensive substitute for a compact immutable SDK. S3 still requires the latter's complete identity, symbols/licenses, atomic publication, ownership and consumer integration; the vcpkg change does not claim to provide it.

## Remaining acceptance

The 3x warm component and 2x end-to-end objectives are unchanged and unproved. S2, full S3/S4/S5, S6B and S7–S10 remain open. Preserve the WIP plan until the accepted implementation, comparisons, native/hosted qualification and normative closeout are complete. A working-branch pin, cache hit, compilation or local fixture pass cannot close those gates.

## SDK storage foundation

The immutable dependency storage layer passes 12 local synthetic controls; [results](sdk-store-results.json)
include real separate-process reader sharing and blocked quarantine, same-size/timestamp-restored corruption,
independently retained manifest digests, shortened-locator full-identity checks, interrupted source publication
and ownership initialization recovery. Original failed fixtures remain in the marked test sandbox. Complete
engine behavior still passes 50 cases and dependency metadata behavior passes seven; workflow syntax validates
nine definitions. Hosted Windows/Ubuntu acceptance is pending for this change.

The [normative storage contract](../../SDK_Cache.md) describes the implemented effects and explicit limits.
No consumer compiles or links from this store yet. The synthetic payload is not a native library. Producer trust,
full native identity acquisition, archive/headers/symbols/licenses, actual linker provenance, local candidates and
all five consumers' cold/hit/mismatch/native acceptance remain open; no SDK speedup or test verdict is claimed.
