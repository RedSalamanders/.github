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
nine definitions. These local checks preceded the hosted acceptance recorded below.

The [normative storage contract](../../SDK_Cache.md) describes the implemented effects and explicit limits.
No consumer compiles or links from this store yet. The synthetic payload is not a native library. Producer trust,
full native identity acquisition, archive/headers/symbols/licenses, actual linker provenance, local candidates and
all five consumers' cold/hit/mismatch/native acceptance remain open; no SDK speedup or test verdict is claimed.

Engine [#22](https://github.com/RedSalamanders/.github/pull/22) subsequently merged as
95187e6fc913984f2a7e105b3b57ad8991b24eca after Windows/Ubuntu engine and SDK controls and both hosted winget
resolution checks passed. Six consumer pins remain at fbe6 until a behavior-changing rollout requires adoption;
the SDK storage is still inactive for native consumers.

## Prose ownership and later hosted snapshot

[hosted-followups.json](hosted-followups.json) retains the later run/source/job/phase snapshot. All four first-wave
RedMonitor, RedXe, RedTilde and RedPrism campaigns completed native x64/ARM64 regression and production successfully.
The first DxUi campaign remains failed because of its x64 tooling prerequisite. Its integrated follow-up and
RedTilde's later baseline-control campaign were still running at this snapshot. These are diagnostic phase costs,
with different sources/cache states; they do not establish a controlled speedup.

RedXe [#78](https://github.com/RedSalamanders/RedXe/pull/78) merged as 3bcdc0bea21baaf48436fbeb46f5a056f1cf07f7
after 35 scoped cases, complete independent tooling and hosted checks. Unknown/runtime Markdown and fixture README
bytes retain native ownership and evidence; hosted exclusions name known prose locations instead of all Markdown.
RedMonitor [#40](https://github.com/RedSalamanders/RedMonitor/pull/40) merged as 4a0de7870cf87fd05136e6a874f0cea84d0870f2
after complete validation, formatting, tooling and hosted checks. Its ten actual public-wrapper process/Git cases
retain cumulative native edits, Full/PrePush matrices, early changelog refusal, nonzero exits and mutation barriers.
Native recording fixtures establish routing only. Existing native source/build controls still pass all 41 checks.

RedTilde's docs/examples are shipped by package.ps1 and include the paired-performance fixture. They retain full
selection and native byte identity, including new Markdown, README and binary assets. The correction passes 58
scoped cases and complete canonical Tooling validation. Initial fixture failures are preserved; the build guard
fixture now copies the actual scope policy it depends on. Ordinary prose remains independently validated.

Shared current-conformance controls reject global Markdown-extension exclusions, while historical manifests remain
readable for original artifact/source verification. Explicit pin maintenance migrates the original default and
uses only committed templates from a clean reviewed engine. [Local controls](prose-policy-engine-results.json)
and subsequent hosted/client adoption must be recorded against the final source before that rollout closes.

## Coordinated adoption and SDK input handoff

The later [hosted-adoption snapshot](hosted-adoption.json) preserves exact sources and outcomes after the
initial snapshot. RedTilde's baseline campaign, RedXe's prose campaign and RedMonitor's public-wrapper campaign
all completed both native regression and production architectures successfully. Later pin-adoption campaigns
and RedPrism's baseline campaign remain separately identified; a queued or running job is not passed.

Engine [#23](https://github.com/RedSalamanders/.github/pull/23) and [#24](https://github.com/RedSalamanders/.github/pull/24)
passed Windows/Ubuntu behavior and both hosted winget controls. The five integrated clients now pin source
904a8cb6824da010e2ddcd787d2037c610b0df9c with matching workflow callers: DxUi #231, RedTilde #101, RedPrism #12,
RedXe #79 and RedMonitor #41. RedSalamander #209 remains pending Entire review; its separate successor worktree
contains the same coordinated pin without changing the head the user is reviewing.

DxUi's f73da6d native campaign failed x64 tooling before product execution because its fixture inherited CI
flags and expected a local iteration baseline. The raw failure remains `.build/i61-hosted-followup-x64.log`.
PR #231 preserves production refusal, explicitly tests the hosted route and isolates the local fixture child.
Its 43 scoped controls passed under hosted/compiler-free environment flags, complete tooling passed and the
static adapter now runs this reviewed compiler-free regression before native builds. The new native campaign
at 0cc1ac0d2c240168a625bf15c2db8707669faa56 is recorded independently; it has not yet completed acceptance.

The current SDK-library handoff branches add separate library-only provenance, using DxUi's complete v2
source/dependency/evaluated-profile/toolchain identities and library/compiler-PDB bytes. Synthetic Git/file
tests cover changed inputs, same-size/mtime corruption, missing symbols, dirty commits, failure revocation,
same-run/attempt transfer, Full/performance receipt refusal and actual production routing. Eleven controls
pass, including 13 incompatible evaluated-profile variants; actual installed x64 Release profile admission
also passes. The shared current-run/attempt workflow contract and four seeded violations pass within 53
engine controls; all nine workflow definitions pass syntax validation. Raw local evidence is retained at
`Z:/RedSalamander.Perf/unified-ci/engine-20261109T171441329Z-60d839ecea764841a41a0bf24cb7f9c3/results.json`
and DxUi `.build/i61-sdk-transfer-controls-v3.log` / `.build/i61-sdk-actual-profile.log`.
These are controls and profile admission, not native SDK compilation, consumer qualification or a speedup claim.
Native timings, final source-bound build/transfer/package proof and both hosted architectures remain required.

## Integrated follow-up and failure classification

The [later source/job snapshot](hosted-qualification-followup.json) supersedes pending statuses above without
changing historical run results.

- RedSalamander [#209](https://github.com/RedSalamanders/RedSalamander/pull/209) merged at
  c883bbf55aad0b56eef8e600349adeb80b6d9cf5. Entire approval is no longer pending. Main run 42672143943
  and its retry failed at GitHub startup without native jobs. Fresh ordinary manual qualification
  [42674161785](https://github.com/RedSalamanders/RedSalamander/actions/runs/42674161785) admitted the
  same source; both architectures were building at this snapshot. It is not yet accepted.
- RedMonitor [#33](https://github.com/RedSalamanders/RedMonitor/pull/33) was reconciled against main,
  retaining the newer 904a8cb engine/callers and the original App Installer fix already in its ancestry.
  Its remaining diff was historical prose. It merged at cdd700db2a7652218ec828494a2b83dd311a828b.
  The coordinator recorded `Native inputs unchanged; original outcome: succeeded.` and linked the
  actual successful [42658151208](https://github.com/RedSalamanders/RedMonitor/actions/runs/42658151208)
  campaign. This is verified avoidance of a redundant native campaign, without a new test execution claim.
- RedXe 42658141677, RedTilde 42658161980 and RedMonitor 42658151208 completed native x64/ARM64
  regression and production successfully after coordinated adoption.
- DxUi [#232](https://github.com/RedSalamanders/DxUi/pull/232) and
  [#233](https://github.com/RedSalamanders/DxUi/pull/233) merged current-run library-input reuse and
  complete metadata queries; engine [#25](https://github.com/RedSalamanders/.github/pull/25) merged the
  corresponding optional artifact handoff. Exact native x64 timings, output hashes and limitations are
  retained in [DxUi measurements](https://github.com/RedSalamanders/DxUi/tree/main/Measurements/TestingAcceleration_2026-11-09).
  Both regressions at 0cc1ac0 passed in [42659996089](https://github.com/RedSalamanders/DxUi/actions/runs/42659996089),
  but a GitHub internal error prevented production startup. Final 63ffc056 run 42669734857 also failed
  GitHub startup without native jobs. These runs remain failed; production/hosted handoff acceptance is open.
- RedPrism [42645222119](https://github.com/RedSalamanders/RedPrism/actions/runs/42645222119) at
  d7c53c618513ac9d5c44eac063a766d8a075f30a passed x64 regression but genuinely timed out in native ARM64
  hidden WARP self-test after 5,400s. No product termination was attempted. Evidence finalization then failed
  to pin an active error log and masked the primary timeout. Preserved stdout ends at session/rendering
  self-test entry; the earlier deliberate crash-probe dumps are not hang evidence. The underlying hang
  remains undiagnosed and red. Later campaign 42658161657 failed GitHub startup without jobs.

Pinned-source SDK producer tooling is locally validated at DxUi 288c76737ec180753aab926e17b98922509a747d.
Complete tooling passes. All three unchanged source pins built x64 Release with zero warnings/errors.
The oldest API4 source pin 4cdf1ce5 also passed extracted native SDK compilation/link/run, header/license
closure, PDB isolation/missing-PDB and first-party-warning rejection controls; other package checks are
pending at this snapshot. Native ARM64, authenticated distribution, consumer integration and local
candidates remain open. An SDK input is never a product test verdict.

## Native SDK byte handoff and producer rollout

DxUi #234, #235 and #236 merged respectively as 7dea6e886f437c88cbcfbbc84e98f6a914edd23b,
54ea8335d5625761187caff93065d1336c10c040 and cb31c4f85602ad34d0a0fd6cd87c30d5d0b4e041.
All three current source pins built and passed their native extracted SDK gates on x64. Complete input
acquisition across independent checkouts matches, while old v2 build/test receipts retain location binding.
At reviewed producer snapshot 6c89bb60c01e14ab4008e300ea73b44d206efb24, the f2e328a0 SDK passed every
native gate and was stored with a full pre-archive payload witness. An independent checked-out/restored
source compiled, linked and ran the SDK consumer from the immutable payload under a reader lease: 391
headers stayed in SDK/toolchain, the original producer PDB stayed exclusively held, and no source library
was built in the reader checkout. Open/close input verification took 32,313/26,796ms and native client
compilation/execution 12,059ms; this is one diagnostic, not a controlled overall speedup result.
Exact identities, SDK receipt and limits live in
[DxUi's SDK store record](https://github.com/RedSalamanders/DxUi/blob/main/Measurements/TestingAcceleration_2026-11-09/sdk-input-store.json).

The first storage prototype's logs remain retained; a full pre-archive byte witness was added before any
independent client consumed an entry. Five store controls cover late stage/header changes, stored corruption,
source mutation, profile/policy/symbol mismatch, misses and failure-safe lease release. Complete tooling
validation and final focused/spec/changelog checks pass. No application adoption or ARM64 result is claimed.

The shared manual producer freezes the exact SDK source/API, reviewed tooling snapshot and storage-engine
pin separately. It permits only explicit DxUi-main dispatch, verifies normal main ancestry before native
setup, uses read-only tokens and uploads attempt-bound dependency artifacts only after native SDK checks.
All/x64/ARM64 selection allows a missing architecture to be retried independently. Actual Git fixtures and
the extracted real resolver script pass within 57 engine controls; ten workflows pass syntax checks.
Final local engine evidence is `Z:/RedSalamander.Perf/unified-ci/engine-20261109T200136901Z-6fd07f625f7a41cca8d496c020a0b9cc/results.json`.
Earlier failed fixtures remain retained. Hosted deployment and both native architectures remain required.

Canonical-checkout bootstrap hardening passes the same 57 engine controls and ten workflow syntax checks.
The controller's raw maps matched the independently acquired SDK provenance for all three full pinned
source checkouts and the clean 6c89bb60 tooling checkout (recorded in the local SDK worktree's
`.build/i61-sdk-canonical-provenance.json`). A real Git fixture preserves size/mtime, hides the mutation
with assume-unchanged, observes a clean status, and still refuses the changed raw bytes. String-valued
API revisions also refuse. Final engine evidence:
`Z:/RedSalamander.Perf/unified-ci/engine-20261109T202241902Z-a180fe185bb64d5596d176688ea78e78/results.json`.
Canonical checkout bytes are explicit inputs, not a normalization of old proof. Hosted x64 regression
for DxUi campaign 42682591817 passed; ARM64 remains pending at this observation.

RedSalamander #210 merged at 99624c5385c6c0d42f8d1c6f8be54cbe69f506ef. Its
49 current Ghostty lifecycle controls include real curl 504 recovery, permanent 404 refusal and bounded
persistent failure, without relaxing hashes or offline behavior. The separate historical five-notice
assertion mismatch remains evidence with sealed source bytes unchanged. Prior campaign 42674161785
still records its x64 HTTP 504 build failure; queued 42687608134 targets the actual merged retry fix.

## Local application SDK input seam and bootstrap cost

Shared producer #27 merged as 6816011e6b8024896ab70ab1320823564da045e2 after all hosted engine and
winget checks passed. DxUi #237 deploys its main-only caller; complete validation/tooling, the compiler-free
adapter, changelog and seven workflow definitions passed locally. Hosted producer execution remains open.
Canonical local SDK 0.1.611097 passed native x64 build, extracted consumer, header/license/symbol isolation
and first-party warning controls with unchanged f2e328a0 source. Its store key is
766c9e4b9351a7f896f913fce9f08b74f598fc0a5edb0fa0b97aa199bd00a9fb and independent manifest SHA-256
50b5a816c693b61fb737ea8093c998ef81c748f10595742994ece009450ede87.

The current shared local application seam adds strict independent descriptors, application lock/profile
admission, full raw source/tooling/storage-engine bootstrap, a complete native input reader, before/after
descriptor/storage checks and a live-owner MSBuild witness. Sixty engine controls pass, including actual
cross-process handle checks, stale/profile/lock refusal, missing source and junction refusal, and mutations
hidden from Git with preserved size/mtime. Evidence:
`Z:/RedSalamander.Perf/unified-ci/engine-20261109T203619583Z-f3a842510d55481e8c73deadf9e798af/results.json`.
RedMonitor's adapter, matching notice packaging and explicit fallback are being integrated; no application
SDK success or native ARM64 qualification is claimed at this snapshot.

[Bootstrap timing diagnostics](sdk-bootstrap-io.json) retain identical raw hashes for the original implementation
and direct-IO candidate. Interleaved candidate/baseline/baseline/candidate timings were 4402/30601/29289/3969ms.
The original 30639ms baseline and three 3945–4316ms candidate repetitions are retained too. Every file and
ancestor is still checked for reparse paths at each read; missing files fail. No timestamp/index shortcut,
reduced hash coverage, normalization or test verdict was introduced. These same-host warm diagnostics ran
alongside other work and do not establish the plan's overall speedup targets.

## Resume acceptance — 2026-11-10

Background actions were left running. DxUi [42703189525](https://github.com/RedSalamanders/DxUi/actions/runs/42703189525)
at 56f498d39c705aced252dae4885c546ede0c85ff passed x64/ARM64 regression, the global test gate,
and both production SDK branches. Historical cancelled/failed runs retain their original outcomes.
SDK producer [42695804476](https://github.com/RedSalamanders/DxUi/actions/runs/42695804476) passed
both native architectures for unchanged f2e328a0a26a18ca66bf4b2aea77bf010c9515e1; the other two consumer pins
still require hosted production.

RedMonitor [#43](https://github.com/RedSalamanders/RedMonitor/pull/43) merged as
3eabe20239fc8382f3b5143694657b36cc20cb32. Its committed measurement record owns the actual SDK-bound
x64 Release application build, seven runtime cases, real ETW, clean-extraction packaging, fourteen effective
MSBuild guard cases and complete Source-fallback PrePush. Cross-builds are not native ARM64 runtime proof.
Its main qualification [42773597824](https://github.com/RedSalamanders/RedMonitor/actions/runs/42773597824)
is pending. DxUi [#238](https://github.com/RedSalamanders/DxUi/pull/238) merged as
1e8fcaac26eb099c3b1e5fa838652bf4b0447c97 with hosted normal Release concurrency two;
[42773652579](https://github.com/RedSalamanders/DxUi/actions/runs/42773652579) remains pending.

RedSalamander [42703183362](https://github.com/RedSalamanders/RedSalamander/actions/runs/42703183362)
at 99624c5385c6c0d42f8d1c6f8be54cbe69f506ef reached tests on both architectures and failed validation.
Original artifacts and job logs are preserved under
`Z:/RedSalamander.Perf/evidence/i61-resume-20261110`. They identify a >MAX_PATH Git fixture,
a reused partial-command scratch destination and an obsolete manual-platform assertion. The initial repair
passed all 66 selected checks twice, zero skips, under run
`20261110T071130Z-11820-ef20947db9ee415e868790fb7dfe10f6`.
ARM64 additionally failed hosted boundary retirement. Preserve its nested cause before attempting a fix;
no foreground, focus, retirement or failure assertion has been waived. Production was correctly blocked.

The candidate-input foundation has four additional behavioral cases (64 total), including independent
controller identity, ordered actual synthetic-merge parents, full source drift and strict data-only schema.
The original recomputed-digest tamper failure is preserved separately; the corrected controls passed under
`Z:/RedSalamander.Perf/unified-ci/engine-20261109T212221406Z-0492a0c9ee224f2db5082d452c6db49a/results.json`.
Public API/fetch acceptance is a separate remaining gate. No native candidate workflow, required status,
local delegation or main adoption is enabled by this input-only foundation.

The current REST acquisition correction passed 65 engine controls under
`Z:/RedSalamander.Perf/unified-ci/engine-20261110T072402001Z-c60f100a1e2d4a93918b1b7a0627f2e1/results.json`.
Hosted Windows/Linux engine controls and native winget checks passed for a60c15c4c48f6b38d02b99954e504f20eb607de5.
The public command then acquired [RedSalamander #211](https://github.com/RedSalamanders/RedSalamander/pull/211)
from independent current REST PR, main and merge-ref snapshots, with the [complete frozen input descriptor](candidate-211-inputs.json).
It uses the actual current REST merge-ref API; the initial missing-field refusal is not relabelled as success.
This positive probe runs no product code and supplies no native qualification verdict.

[SDK transfer evidence](sdk-transport.json) records the successful real x64 producer download and atomic import,
including its server archive digest, original raw manifest digest and complete input key. The public command
also passed. Sixty-seven engine controls and thirteen storage controls passed, including native job/attempt,
workflow/engine, missing/duplicate/expired metadata, corruption, unsafe archives and cross-store raw manifest
preservation. Synthetic fixtures establish refusal/integrity behavior; consumer adoption and native runtime
remain separate. The local compiler recipe has another key, so this hosted import does not prove a local hit.
