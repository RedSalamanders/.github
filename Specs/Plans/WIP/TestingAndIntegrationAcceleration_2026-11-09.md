# I61 Testing and integration acceleration across RedSalamanders

Status: **ACTIVE — implementation in progress across the organization; first changes locally validated, native/hosted rollout and overall acceleration targets remain open.**
Priority: P0 developer feedback and integration throughput.
Owner: one organization integration owner, supported by each project's build/test owner.
Prepared: 2026-11-09. Relocated to `RedSalamanders/.github` on 2026-11-09. Revision: 8, organization implementation authorized on 2026-11-09.
Scope: `RedSalamander`, `DxUi`, `RedPrism`, `RedTilde`, `RedXe`, `RedMonitor`, and the shared `RedSalamanders/.github` CI repository.

## 1. Outcome, authority and execution boundary

Make ordinary edit/test cycles substantially faster and avoid repeating equivalent integration work. Preserve the existing ability to detect correctness, memory, architecture, performance, deployment and integration regressions.

The design principle is **one authoritative execution for each distinct validation obligation and artifact identity**. Reuse an accepted result when all of its relevant inputs and trust requirements still match. Execute only the changed or previously uncovered obligations. Different configurations, architectures, production roles and environmental scenarios are different obligations.

This document is the canonical organization-owned implementation record in `RedSalamanders/.github/Specs/Plans/WIP/`. I61 retains its original tracking identifier; RedSalamander no longer owns a separate copy. The user authorized implementation until completion across all organization projects on 2026-11-09. Execute the ordered slices, retain acceptance evidence, and update owning specifications in the same changes. The progress record below distinguishes working implementation from deployed acceptance. Publication, account/billing changes, new drive-root workspaces, foreground input, and unrelated work remain outside this authorization.

Current authority remains:

- [Shared engine guidance](../../../AGENTS.md) and [shared CI contract](../../CI.md), including the WIP-to-Done lifecycle rule.
- [RedSalamander guidance](https://github.com/RedSalamanders/RedSalamander/blob/main/AGENTS.md).
- [Validation evidence](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Testing/Testing_ValidationEvidence.md), [self-test ownership](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Testing/Testing_SelfTests.md), [test coverage](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Testing/Testing_TestCoverage.md), and [performance validation](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Testing/Testing_PerformanceValidation.md).
- [Build toolchain and receipts](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Build/Build_Toolchain.md), [unified CI](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Build/Build_UnifiedCI.md), and [portable ZIP qualification](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Installer/Installer_PortableZip.md).
- [Tooling governance](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Testing/Testing_ToolingGovernance.md) and [Changes workflow](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Core/Core_Changes.md).
- Each sibling repository's `AGENTS.md`, build/validation/CI contracts and test guide.
- The shared engine's `AGENTS.md` and `Specs/CI.md`.

The native candidate gate and cross-run adoption described below require deliberate revisions to current compiler-free-PR and evidence trust-domain contracts. Implement and qualify those revisions before reducing local or post-merge obligations. Until then, retain the existing gates.

## 2. Why do local tests, PR checks and main seem to repeat everything?

### 2.1 What happens today

The product PR workflows are compiler-free under the current unified CI policy. They run static/security/formatting checks; they do **not** normally rebuild and retest the full native product. A test suite named `PR` when run locally is not evidence that the hosted PR workflow runs it.

If a PR appears to launch native work, identify the actual repository, workflow, event, ref, profile and role. It may be an explicit qualification, a main run after another merge, a legacy workflow, or an independently dispatched investigation. Do not remove a job based on its display name.

Local `PrePush` retains work because there is currently no equivalent required native PR check to take it over. A later main run is not pre-merge protection. Automatic main qualification freezes a committed candidate and runs native x64 and ARM64 Release regression, then separate production Release/package roles. It does not automatically run the complete Debug/ASan/manual/Full matrix.

Local Debug, native ARM64 Release, ASan, and test-disabled production builds can compile similar source while proving different properties. They are not interchangeable. Re-running exactly the same checks against equivalent inputs, however, is avoidable overhead.

### 2.2 The target workflow

| Stage | Purpose | Native work in the target design | What prevents duplicate work |
|---|---|---|---|
| Local editing | Fast feedback on the current edit | Selected tests on the developer's native profile; relevant focused Release/ASan/performance investigations when needed | Targeted build/runtime closure, incremental iteration baseline, exact local receipts |
| Local PrePush | Account for the candidate's obligations | Only uncovered local obligations; equivalent required hosted work may be pending | Explain every obligation as executed, reusable, pending, or required separately |
| Cheap PR checks | Catch source, formatting, policy and security problems | Compiler-free checks remain cheap and independent | Reuse only under their own complete input contract |
| Authoritative candidate integration | Prove the exact proposed integration before merge | One required native integration campaign, with declared architecture/configuration/scenario coverage | Freeze merge inputs, build each required identity once, retain immutable artifacts and results |
| Main after merge | Verify the landed integration matches accepted evidence | Adopt matching candidate results; execute missing or invalidated obligations | Recompute identity and coverage; do not rerun merely because the event is `push` |
| Production/package | Prove distributable bytes | Build test-disabled production identities where still distinct; native extraction/smoke required | Produce each production identity once and promote those exact bytes |
| Extended qualification | Prove additional domain properties | Explicit Full, ASan, stress, performance, devices, foreground and other required gates | Separate obligations with named owners; never silently omit them |

The authoritative candidate gate is a new, planned capability. Until it is deployed, required by branch policy, and bound to the exact merge candidate, keep current local coverage and main qualification.

Admit native work when a reviewed candidate is ready for integration, or as a frozen merge-queue batch. Do not add a full native matrix to every PR push and then run the same matrix again on the merge group and main. Cheap PR feedback can run on each push; one authoritative native campaign covers the frozen integration batch. Coalesce ready changes before admission, preserve already running evidence, and invalidate only proofs whose inputs changed. Measure batch waiting, time to first failure and failure-isolation cost alongside throughput.

### 2.3 Direct answers and examples

**Why run locally and in CI?** Local checks shorten feedback on dirty work and the developer's profile. CI provides reproducible integration on native architectures, a controlled toolchain and independently retained artifacts. The target does not require every developer to run the entire integration campaign before that same campaign runs in CI.

**Why rerun after merge?** Only when the landed inputs or obligations differ, or trusted evidence is unavailable. Changes to the base branch, dependencies, generated files, version stamps, build options, test inventory, runtime closure, environment requirements or policy can invalidate the candidate proof. A different commit SHA alone is not necessarily different meaningful source, but equivalence must be proved rather than assumed.

**Can a merge commit reuse the candidate's proof?** Yes, after the new adoption contract is implemented: the exact meaningful source projection, dependencies, build inputs, artifact bytes, coverage and trust domain must match. Record both commit identities and their equivalence. Never rewrite an old receipt to pretend it executed on the landed commit.

**What about version stamping?** A build number, embedded SHA or version resource is a build input. Reserve/freeze candidate version inputs where existing product semantics permit. If landing changes them, rebuild the affected stamp/link closure and rerun every obligation whose tested artifact changed. Do not restamp accepted binaries and retain their old test result.

**Can a local pass satisfy a hosted gate?** Not by uploading a local JSON file. Current local evidence is checkout-bound and portable handoffs are narrower. Keep local and trusted hosted producers distinct. Any future additional producer requires an explicit trust/provenance contract and acceptance tests.

**Does a cache hit mean tests passed?** A dependency/build cache supplies bytes. Test receipts supply results. Neither substitutes for the other. A filtered pass covers the filtered selection, and pending CI remains pending.

**Example: leaf-control change.** Run the control's direct and integration cases locally using targeted outputs. The authoritative campaign builds the required profiles once. Main verifies and adopts its matching evidence. If another merge changes a shared host before landing, invalidate the affected proof and test the new integration.

**Example: prose-only follow-up.** Run relevant documentation/static checks. Preserve the last native outcome when the meaningful native inputs are unchanged, including a previous failure. A prose commit must not turn red native inputs green or consume an earlier unqualified code change.

## 3. Source snapshot and mandatory drift check

These are inspection anchors, not claims that the listed commits are qualified or still latest.

| Repository | Inspected local commit | Primary implementation owner |
|---|---|---|
| RedSalamander | `ab4c85e13845e99a4de92fb88a96753e30fc6727` | `Test-Changes.ps1` delegates to `Tools/Run-AllTests.ps1`; governed impact/evidence modules |
| DxUi | `0d12c464638ddc41f48d521a4a598a50870117d2` | `Test-Changes.ps1`, `Tools/ScopedTesting.psm1`, `test.ps1`, consumer qualification |
| RedPrism | `4c6b17ceb6a9ebb0c59a202350d2972705de742e` | `Test-Changes.ps1`, `Build/ScopedTesting.psm1`, `Tests/test-scopes.json` |
| RedTilde | `a35a9c82814e079f9e1f69610bd69dedcc2aab92` | `Test-Changes.ps1`, `Build/ScopedTesting.psm1`, `Tests/test-scopes.json` |
| RedXe | `ce3f62b773bb6b83b01b9fdec71f8a6b69f21d18` | `Test-Changes.ps1`, `Build/ScopedTesting.psm1`, plugin/host/package scopes |
| RedMonitor | `9140b9e94406a88e5c18bef23a9f3195d7a305ae` | `Test-Changes.ps1`, `Build/Toolchain.psm1`, `test.ps1`, `RedMonitor.proj` |
| Shared .github engine | `c611e5784c9d81654b6af04305a12d54ef76f38d` | Local checkout `Z:/src/RedSalamanders.CI`; reusable workflows, policy and receipts |

The engine checkout is not necessarily on main, and its HEAD is not every consumer's deployed engine. Read each `.ci/project.json` and reusable-workflow caller, then inspect the exact pinned engine commit. Pins differ across the organization. DxUi consumer pins and API revisions also differ; do not advance them merely to improve cache hit rates.

Before each slice, run the following read-only checks inside **each affected repository**, substituting its inspected commit:

```powershell
git status --short
git rev-parse HEAD
git diff --name-status <inspected-commit> HEAD -- AGENTS.md build.ps1 test.ps1 Test-Changes.ps1 Build Tools Tests Dependencies .ci .github Specs
git diff --name-status
git diff --cached --name-status
git ls-files --others --exclude-standard
git worktree list --porcelain
```

Reopen changed owning files and reconcile drift before editing. Include untracked inputs; a clean committed diff does not describe a dirty tree. Do not reset another owner's changes, switch a busy checkout, clean evidence, or reuse a stale line number as proof.

Organization discovery was checked on 2026-11-09: six product/library repositories plus `.github`. Refresh `gh repo list RedSalamanders --limit 100 --json name,nameWithOwner,isArchived,defaultBranchRef` before rollout; add newly in-scope repositories explicitly rather than silently ignoring them.

## 4. Verified starting facts and design consequences

| Starting fact | Evidence location | Consequence |
|---|---|---|
| There is no uniform six-profile-per-edit requirement across all projects | Each `AGENTS.md`; RedSalamander's scoped policy; RedXe's affected-configuration requirement; stronger DxUi/RedTilde/RedMonitor qualification contracts | Inventory obligations per project and stage; do not claim a universal 75% saving |
| RedSalamander already has an active impact graph | `Test-Changes.ps1`, `Tools/Run-AllTests.ps1`, `Tools/validation-impact.json`, validation evidence spec | Change the actual planner/runner; filling the standalone manifest is not the acceleration route |
| A new Changes fragment currently selects the broad unknown-input fallback | During this revision, `Get-RSValidationImpactRulesForPath` selected `fallback.unknown` for `Changes/2026-11-09-i61-implementation-handoff.md`; both edited WIP Markdown files selected `documentation.specs` | Add a reviewed valid-fragment mapping and regression control; retain changelog/document checks and conservative fallback for unknown executable inputs |
| RedSalamander Affected does not reuse results; exact Resume is Full-only | `Specs/Testing/Testing_ValidationEvidence.md` | Any additional reuse requires a reviewed contract/schema transition; do not flip a flag |
| RedMonitor has no equivalent component-scope JSON planner | `Test-Changes.ps1` runs validation, formatting, tooling, then Debug; Full/PrePush add profiles, ETW and installer work | Add explicit selection/identity support through its own entrypoints |
| Existing native receipts can be broader than a selected component | RedPrism `Get-ScopedRunIdentity` binds compiled-source and profile-artifact identities | `reuse: true` alone cannot provide component-level savings |
| Some suites intentionally depend on external state | RedPrism IO mapping names codec/clipboard state; RedMonitor has live ETW and installer controls | Separate deterministic seeded tests from state-dependent integration; do not cache unobserved state |
| Broad scope rules include actual consumers | DxUi `DxUi.Tests.Animation.cpp` tests ComboBox caret/popup behavior; RedXe Settings compiles plugin models; RedTilde Storage feeds recovery/restart | Preserve those consumers or select their exact relevant cases |
| DxUi already supports bounded suite parallelism | `test.ps1 -ParallelSuites`, `Tools/ParallelSuites.psm1`; default 1, performance/foreground serial | Expose and qualify existing support before creating a second scheduler |
| DxUi performs harness checks and performance work inside native execution | `test.ps1` invokes filter/watchdog checks and `performance.ps1` | Splitting a Tooling scope alone will not remove this overhead |
| Automatic main qualification is Release normal regression, not every Full/manual obligation | Shared `native.yml`, all project adapters, unified CI specs | Do not justify narrower local coverage with a nonexistent automatic Full fallback |
| Test-enabled and production-only roles intentionally differ | Shared `native.yml`, project macros/build receipts and portable smoke | Keep role identity and isolation until production-byte testing is genuinely equivalent |
| Dependency binary caches already exist | Pinned shared `native.yml` restores/saves vcpkg; RedSalamander also has Terminal caching | Measure hits and invalidation; extend compatible caches rather than claiming none exist |
| Changelog folds can already batch several changes | `Specs/Core/Core_Changes.md`, `Tools/Submit-ChangelogFold.ps1` | No mandatory one-extra-PR-per-feature assumption; cadence changes are a smaller workflow improvement |

Git identity needs particular care. `git rev-parse 'HEAD^{tree}'` identifies the root tree. `HEAD:tree` identifies a path named `tree` and fails in this checkout. Correct syntax alone does not make Git status a raw working-byte attestation. Account for staged contents, worktree contents, deletions, type changes, modes, attributes/filters, line endings, sparse/assume-unchanged behavior, untracked inputs and concurrent edits. See [Git index behavior](https://git-scm.com/docs/git-update-index) and [Git content conversion](https://git-scm.com/docs/gitattributes).

## 5. Performance baseline and success measures

### 5.1 Observed hosted samples

The following are workflow-created-to-completed samples inspected on 2026-11-09, excluding the preceding coordinator quiet wait. They use different commits/engine pins and are not a controlled comparison. A successful admission-only/no-op run must not be counted as native qualification.

| Project / observed run | Approximate elapsed | Recorded result and significant phase |
|---|---:|---|
| [RedSalamander 42529232995](https://github.com/RedSalamanders/RedSalamander/actions/runs/42529232995), Nov 8–9 | 190 min | Failed; x64 test build 75 min, regression step 105 min; adapter subsequently rejected summary discovery |
| [DxUi 42442938301](https://github.com/RedSalamanders/DxUi/actions/runs/42442938301), Nov 8 | 103 min | Passed; ARM64 test build 37 min, regression step 30 min, production job 25 min |
| [RedPrism 41584983562](https://github.com/RedSalamanders/RedPrism/actions/runs/41584983562), Nov 3 | 153 min | Failed; ARM64 regression step 109 min |
| [RedTilde 42445865963](https://github.com/RedSalamanders/RedTilde/actions/runs/42445865963), Nov 8 | 57 min | Passed; ARM64 regression job 30 min and production job 26 min |
| [RedXe 41496091383](https://github.com/RedSalamanders/RedXe/actions/runs/41496091383), Nov 2 | 55 min | Passed; production setup roughly 11–13 min per architecture |
| [RedMonitor 41534628904](https://github.com/RedSalamanders/RedMonitor/actions/runs/41534628904), Nov 2 | 35 min | Passed; ARM64 setup roughly 8 min in both native roles |
| [.github engine 42562818757](https://github.com/RedSalamanders/.github/actions/runs/42562818757), Nov 9 | 71 sec | Passed engine behavior/hosted-winget workflow; different coverage from a product qualification |

In the RedSalamander sample, the console reported suite success before `Tools/Invoke-ProjectCi.ps1` rejected the requirement for exactly one fresh completed CI summary. The failure remains a failure; do not convert it into a pass. Add a cheap runner/adapter handoff contract test and exact run-reference handling before paying for another long execution. Do not assume this single exception explains all historical failures.

The DxUi sample includes consumer qualification after its main test invocation. Its build phase diagnostics also show material attestation cost. Profile both instead of assuming every delay is a slow functional test or a 5–20 second hashing loop.

Local diagnostic on this documentation revision: `Test-Changes.ps1 -Explain` identified exactly three changed paths (the plan, WIP index and new Changes fragment), selected the broad advisory Full build/runtime surface, and wrote `Z:/RedSalamander.Perf/evidence/explain-plan.json`. Its matched rules were `documentation.specs` and `fallback.unknown`; direct canonical path classification confirmed that the fragment caused the latter. The reported fresh-duration estimate was 2,192,367 ms, an advisory estimate rather than elapsed test time. The command performed no native build/test and produced NOT_EVALUATED (canonical exit 2); an outer PowerShell command wrapper reported exit 1, which must not be confused with a native test failure. Preserve or copy the diagnostic through governed evidence handling before another explanation overwrites the default path. S6 owns the precise classification correction and its negative controls.

### 5.2 Required measurement record

For each measured invocation, retain source/dependency/engine identity, machine/native architecture, profile and role, invocation/selection, cold/warm definition, discovered/executed/skipped counts, result and raw evidence. Measure separately:

- Queue/admission/debounce and runner provisioning.
- Exact toolchain setup, source/dependency restore, cache lookup/download/extraction/verification.
- MSBuild evaluation, native compilation, linking, resources and runtime staging.
- Source acquisition, artifact/environment hashing, fingerprints and receipt validation; include bytes/file counts and cache misses.
- Tooling checks, harness self-checks, per-case/per-suite work, process startup and fixture setup.
- Serialization/resource waits, consumer SDK qualification, packaging/smoke and evidence upload.
- Time to first actionable failure, total elapsed time, total native runner minutes, retries, peak memory and cache storage.

Count each build once by identity and role; do not add overlapping matrix times as wall-clock savings. Diagnose long failures without shortening deadlines or disabling checks just to improve the number.

Use these representative scenarios: no change; prose-only; test-only; leaf control/plugin; shared header/host; dependency pin; tooling/runner change; cold clean extraction. Cover all six clients with their applicable cases. Reuse existing compatible traces where possible; do not launch full campaigns merely to populate a table.

Initial objectives, **not measured promises**, are at least 3x faster median warm component iteration and 2x faster end-to-end qualification on the measured pilot workloads, with no reduced declared coverage. Report absolute times, range, total compute and cache costs even if objectives are missed. Use paired repeated local measurements; use matched hosted samples where practical. Do not label a maximum of three runs as p95; collect a sufficient rolling sample (at least 20) before reporting that percentile. Retain all failing/noisy rounds.

Freeze the pilot workloads and their latency/compute acceptance thresholds in S0 before optimizing them. Other clients must retain comparable coverage and report any latency/resource regression against the same declared workload and noise policy. An unmet performance objective keeps that outcome open; a smaller result can replace the target only through an explicit owner decision based on concrete measurements, not by silently weakening closeout criteria.

## 6. Target design: identities, evidence and coverage accounting

### 6.1 Separate source, build, test and publication identities

Extend existing canonical schemas/helpers rather than introducing an unrelated receipt system.

1. **Input identity:** relevant source paths and bytes, dependency/API pins, generated inputs, resources/schemas, build/restore policy and declared environment. Preserve a complete acquisition barrier around execution. Unknown relevant inputs widen or refuse.
2. **Build identity:** input identity plus exact toolchain/SDK/CRT, architecture/configuration, compiler/linker flags, sanitizer and STL policy, test-surface macros, version inputs and artifact role.
3. **Artifact identity:** every required native/runtime/staged byte, provenance and symbol association. A selected project's runtime closure includes dynamically loaded modules, data and helpers, not just its `ProjectReference` graph.
4. **Test identity:** artifact identity plus exact case inventory/selection, fixture recipe and capabilities, runner/engine/schema policy, arguments, quarantine/outcome policy, failure detector and relevant environment.
5. **Acceptance identity:** trusted producer/run/attempt, immutable artifact/result digests, covered obligation set and promotion/adoption provenance. Publication consumes accepted production bytes without rebuilding or restamping.

Commit/event names are provenance, not substitutes for input comparison. A documentation-only commit can preserve meaningful native identity while still requiring documentation checks. A functional schema, Markdown fixture or generated source is not prose merely because of its folder or extension.

### 6.2 Reuse rules

- Reuse only terminal successful evidence with complete positive discovery/execution and matching coverage. Missing, expired, filtered-for-a-broader-request, failed, interrupted, corrupt, mutated or unexpectedly skipped evidence cannot satisfy an obligation.
- An unchanged known failure remains failed until an explicit fresh retry succeeds. An older green run cannot mask it.
- A branch/base advance, engine/policy change, changed binary or altered detector invalidates the affected proof. Report the exact changed identity component.
- A component receipt needs a reviewed complete dependency/runtime closure. Do not infer it from a filename pattern or scope label.
- Local receipts stay local until an explicit portable producer contract is implemented. Hosted adoption must verify trusted workflow provenance, immutable digests and candidate/landed equivalence independently of candidate-supplied JSON.
- External devices, clipboard/ETW state, filesystem capabilities, installed codecs, performance machines and interactive desktop state need their owning rules. Split pure seeded behavior from environmental checks; a generic environment-variable hash does not capture everything.
- Keep explicit force/fresh paths. Existing Fresh/CI/release semantics remain unchanged until the owning spec and schema transition is accepted.
- Show a per-obligation explanation: `EXECUTE`, `REUSE`, `PENDING_REQUIRED_CI`, `PENDING_MANUAL`, `NOT_APPLICABLE` with reason, or `BLOCKED`. These are proposed explanation categories, not currently implemented CLI/API values.
- Aggregation may combine compatible evidence only under the reviewed coverage contract. It must never present a focused pass as complete repository qualification.

### 6.3 Faster identity without weaker attestation

First measure repeated work. Memoize immutable Git-object and tool identities by their complete immutable key, batch native reads/hashing, and avoid reopening the same unchanged input inside one protected operation. Use content-addressed manifests for immutable cache objects. Preserve worktree/source mutation barriers and artifact ownership/epoch checks.

Do not replace raw-byte checks with mtime/size or a clean status claim. Any filesystem change journal optimization requires gap/overflow/restart detection and conservative fallback. Test attributes/filters and ignore/index flags explicitly. Do not silently change SHA-256 identity semantics to Git's normalized blob identity.

Separate runtime execution inputs from symbol/debug evidence where justified. PDBs can be essential to debugging, sanitizer/diagnostic workflows and provenance. Reduce unnecessary repeated symbol hashing through immutability and validated manifests; do not blanket-drop symbol integrity from qualification.

### 6.4 Cache design

The DxUi SDK/build cache key must cover the producer source/API and public headers, exact compiler/linker/MSBuild/SDK/CRT, native architecture/configuration, optimization/sanitizer/STL annotation policy, dependency/restore/import closure and schema version. Reuse the current consumer identity calculation, including RedSalamander's annotation-policy difference.

Publish complete immutable entries atomically after verification. One writer builds an entry; readers never consume partial state, mutate it or rebuild in place. Verify full identities and manifests even if directory names are shortened. A bad entry is a cache miss or explicit corruption failure with retained diagnostics, never a silent success. Define bounded retention, eviction leases and reader ownership; never delete an in-use entry.

Use an approved workspace/subdirectory for local cache storage, or an explicitly selected account-local location whose ownership and cleanup contract is defined. Do not create drive-root cache folders. For CI, a repository-scoped cache is not automatically shared across repositories: select an authenticated organization artifact store or qualified SDK producer artifact, with explicit read/write access, retention and integrity. Do not expose write credentials to PR code. Cache misses must still build correctly and offline behavior must be explicit.

### 6.5 Local cross-repository development

Provide an explicit local candidate SDK override through the existing consumer integration seam. Build/capture the producer's dirty-source identity, headers, library, symbols and integration files under its operation lease, then expose an immutable snapshot to consumers. Acquire cross-repository leases in a documented order; never hold a consumer write lease while waiting cyclically for its producer.

Use separate local-unpinned consumer outputs and receipts. Editing the producer invalidates the candidate snapshot; changing back to the pin invalidates affected consumer outputs. Check the actual linker input/provenance, not just a displayed label. PrePush, authoritative qualification, package and publication paths refuse unpinned outputs. Never copy a sibling library into a managed pin and call it pinned.

DxUi has five application consumers, including RedMonitor. RedMonitor also has a separate producer-header/ETW compatibility contract consumed by four applications. Include both directions in the integration graph.

## 7. Coverage and scheduling policy

### 7.1 Sound selection

Maintain a graph from production/test/generated/build/runtime inputs to the cases that exercise their behavior. Use existing source/project/inventory mechanisms, add reviewed scenario metadata where static references are insufficient, and preserve conservative fallback for unresolved inputs.

A source change can affect recovery, crash handling, performance, settings, accessibility, rendering or packaging without touching a same-named file. In particular:

- ComboBox changes retain its Animation/TextField/host/rendering/accessibility consumers unless equivalent individual cases are selected.
- RedXe plugin model/settings consumers retain Settings; host activation and actual deploy/load checks remain covered.
- RedTilde Storage/Recovery changes retain restart and editor integration; application bootstrap changes retain crash-path coverage.
- Product hot-path changes retain affected performance scenarios even if benchmark code is unchanged.
- RedMonitor producer changes retain offline client contract and required real transport compatibility; source-only verification does not prove ETW roundtrips.
- Tools/build/runner changes select behavioral self-tests through their dependency closure, including native runner code and schemas outside those folders.

Run new selection in comparison mode against broader execution before enforcement. Preserve the expected relevant failures in the historical/seeded defect corpus. A metadata validator passing is not proof that the graph is sound.

### 7.2 Scheduling

Reuse DxUi's existing `ParallelSuites` support and extend the canonical runners only where equivalent ownership can be maintained. Bound concurrency by CPU, memory, I/O and runner capacity; do not multiply compiler `/m`, test workers and architecture jobs without a budget.

Model resource requirements: immutable/pure cases may run concurrently; shared output writers serialize by existing repository/profile/dependency rules; global clipboard, ETW session, installer/alias and other shared-state cases require their own leases. Performance measurements run without competing work. Foreground suites remain serial under the existing warning/desktop lease and prior agreement to the time. No new Computer Use/manual screenshot route.

Publish one immutable result/log per process or case as supported. Preserve all outcomes and deterministic aggregation. Order cheap/high-yield checks to reveal failures early, while retaining required evidence and explicit diagnostic continuation. Do not rerun whole passing campaigns for a small failing scope when compatible exact evidence can be retained under its owning contract.

### 7.3 Configuration and gate relocation

Inventory each project's present obligations instead of imposing a fictional universal matrix. Ordinary editing should use a fast native-profile affected run. Release optimizer behavior, ASan detection, native ARM64, production packaging, interactive and performance evidence remain distinct where required.

Path patterns alone cannot reliably recognize every lifetime, COM or threading defect. A narrow risk-trigger list is not a complete substitute for sanitizer or platform qualification. ASan also does not prove race freedom.

Move expensive completion work from local to required hosted candidate integration only after the replacement executes the exact declared scope/profile, is required by branch policy, and has passed its own detection/provenance controls. If unavailable, local obligations remain. Automatic main Release cannot claim Debug/ASan or manual Full coverage it never ran.

## 8. Repository implementation map

Paths below are relative to the named repository. Read its guidance before editing; the map identifies owners, not permission to edit every listed file at once.

| Repository | Runtime/build/planning files | Existing checks and owning contracts |
|---|---|---|
| RedSalamander | `Test-Changes.ps1`; `build.ps1`; `Tools/Run-AllTests.ps1`; `Tools/Modules/Testing/{ValidationImpact,ValidationFingerprint,ValidationEvidence,TestInvocation,TestRunPlan,ScopedTesting}.psm1`; `Tools/validation-impact.json`; `Tools/Modules/Build/{DxUiDependency,DxUiPaths}.psm1`; `RuntimeDependencies.props`; `Tools/Invoke-ProjectCi.ps1` | `Tools/Tests/{ValidationImpact,ValidationFingerprint,ValidationEvidence,ScopedTesting,BuildEvidence,DxUiDependency}.Tests.ps1`; `Specs/Testing/Testing_ValidationEvidence.md`; `Specs/Build/Build_Toolchain.md`; `Tests/README.md` |
| DxUi | `Test-Changes.ps1`; `Tools/ScopedTesting.psm1`; `Tests/test-scopes.json`; `build.ps1`; `test.ps1`; `performance.ps1`; `test-consumer.ps1`; `Tools/{ParallelSuites,ConsumerBuild,ConsumerQualification}.psm1`; `Tools/Invoke-ProjectCi.ps1` | `Tools/tests/{Test-ScopedTesting,Test-TestFilter,Test-TestWatchdog,Test-ConsumerQualification,Test-ConsumerUpdate}.ps1`; actual control/embedded/consumer cases; `Specs/Testing/Testing_Validation.md`; `Tests/README.md` |
| RedPrism | `Test-Changes.ps1`; `Build/ScopedTesting.psm1`; `Tests/test-scopes.json` including derived project rules; `build.ps1`; `test.ps1`; `Build/{DxUiRestore,DxUiPaths}.psm1`; `Tools/Invoke-ProjectCi.ps1` | `Tests/Tooling.Tests.ScopedTesting.ps1`; `Tests/BuildProcessTests/DxUiRestoreTests.ps1`; direct Document/IO/Host/Runtime/Stress/Performance cases; `Specs/Testing/Testing_Validation.md` |
| RedTilde | `Test-Changes.ps1`; `Build/ScopedTesting.psm1`; `Tests/test-scopes.json`; `build.ps1`; `test.ps1`; `restore-dxui.ps1`; `Build/DxUiPaths.psm1`; `Tools/Invoke-ProjectCi.ps1` | `Tests/Tooling.Tests.ScopedTesting.ps1`; application/storage/recovery/editor/crash cases; `Specs/Testing/Testing_Validation.md`; `Tests/AGENTS.md` |
| RedXe | `Test-Changes.ps1`; `Build/ScopedTesting.psm1`; `Tests/test-scopes.json`; `build.ps1`; `test.ps1`; `Build/{DxUiRestore,DxUiPaths}.psm1`; packaging modules; `Tools/Invoke-ProjectCi.ps1` | `Tests/BuildProcessTests/{ScopedTesting.Tests,DxUiRestoreTests}.ps1`; Settings/PluginContract/HostPlugin/HostSmoke/Packaging scenarios; `Specs/Build/Build_Process.md` and `Core_DxUiIntegration.md` under `Specs/Core/` |
| RedMonitor | `Test-Changes.ps1`; `Build/Toolchain.psm1`; `build.ps1`; `test.ps1`; `RedMonitor.proj`; `restore-dxui.ps1`; `Tools/Invoke-ProjectCi.ps1`; `Tools/ClientSdk/` | `Tests/Tooling.Tests.{Build,Installation}.ps1`; Client/Settings/Monitor/Transport native projects; `Specs/Testing/Testing_Validation.md`; `Specs/Build/Build_Consumption.md` |
| Shared .github | `.github/workflows/{coordinate,native,pr,qualification,publish}.yml`; `Tools/{Invoke-Coordinator,Invoke-Admission}.ps1`; `Tools/Modules/Ci.{Policy,GitHub,Project}.psm1`; existing receipt/schema modules | `Tests/Test-Engine.ps1`; `Tools/Test-Workflows.ps1`; `Specs/CI.md`; schema/admission/receipt tests |

All six clients also own `.ci/project.json`, reusable-workflow callers, `Specs/Build/Build_UnifiedCI.md` and their current guidance. All five applications own their publication/package contracts; DxUi's SDK ZIPs remain internal and DxUi has no product publication workflow.

## 9. Ordered implementation slices

Record each slice as NOT_STARTED / IMPLEMENTED / LOCALLY_VALIDATED / HOSTED_ACCEPTED with source and evidence references; use IN_PROGRESS for a slice whose subparts have different states. Do not mark a checkbox for merely editing a plan or writing a test.

### Current implementation record — 2026-11-09

The [implementation evidence record](../../TestRuns/I61_2026-11-09/README.md) owns exact commands, measurements, delivery references and limits. The shared engine and five clients have integrated the first layer; hosted acceptance is recorded per repository and is not overall completion.

| Slice | Current state | Implemented and remaining |
|---|---|---|
| S0 | IN_PROGRESS | Refreshed all seven repositories and six client source/pin/scope/effective-main-rule inventories. Hosted native candidate checks and merge-queue/base requirements are absent in the observed rules. Full warm/cold cost accounting and pilot acceptance remain open. |
| S1 | IN_PROGRESS | RedSalamander #209 merged as c883bbf55aad0b56eef8e600349adeb80b6d9cf5 with the strict runner/adapter summary handoff. Fresh manual campaign 42674161785 lost x64 before tests to a dependency HTTP 504; ARM64 regression remains in progress. Follow-up #210 merged as 99624c5385c6c0d42f8d1c6f8be54cbe69f506ef with bounded dependency retries and 49 current lifecycle controls passing. Its native campaign 42687608134 is queued behind the preserved active campaign. Native handoff acceptance remains open. |
| S2 | IN_PROGRESS | DxUi PR #230 integrated evaluated target-union routing and coverage-bound receipts. Cold x64 Release built exactly library/Foundation/Embedded with zero warnings/errors; both native suites passed, Embedded observed 583,358 checks. Default selected build and public/direct Foundation execution passed; actual Full and added-Grid requests refused before native work. Full final tooling passed. Other projects/profiles and overall elapsed acceptance remain open. |
| S3 | IN_PROGRESS | Shared ABI-cache fallback and same-run SDK library inputs are integrated. DxUi #234/#235/#236 merged exact historical-source SDK production, complete portable input acquisition and immutable SDK publication/reader leases. All three unchanged pins passed x64 SDK gates; an independent leased SDK client compiled/linked/ran with 391 header checks and no source-library build. Shared #27 merged the explicit native producer; DxUi #237 adds its caller and remains under validation. The current shared branch adds the explicit local application reader/close contract and live-owner MSBuild guard, with 60 engine controls passing. Raw bootstrap identity acquisition dropped from 29–31s to about 4s with identical maps and retained path/byte controls; this is a narrow diagnostic, not overall acceleration acceptance. RedMonitor pilot integration, authenticated distribution, native ARM64, local candidates and overall speed targets remain open. No application SDK build has passed yet. |
| S4 | IN_PROGRESS | RedSalamander immutable pattern compilation cache measured with identical decisions. Rejected hashing and sibling pattern-cache experiments were removed. DxUi PR #230 integrated profile iteration baselines with 43 scoped and 43 build-policy cases and complete tooling validation passing. RedTilde PR #100 integrated old-baseline failure/interruption revocation and profile leases (57 cases/all validators passed); RedPrism PR #11 merged the same controls after 30 scoped and 76 ARM refusal controls, complete validation and hosted checks passed. Dependency-scoped native-result reuse remains open. |
| S5 | IN_PROGRESS | DxUi scoped parallel option/identity and exact local filter/watchdog preflight reuse integrated in PR #229. Same-binary x64 Release serial/parallel-2 runs passed the same 1,726 named cases and 19 suites with zero skips; one pair improved elapsed time by 24.1%. Local prerequisite reuse measured about 1s versus 23s fresh in two alternating pairs. Hosted architecture acceptance remains open and hosted scheduling remains serial. |
| S6A | IN_PROGRESS | Root #209 and #210 merged valid-fragment routing and coordinated 904a8cb engine/prose ownership. RedXe #78, RedMonitor #40 and RedTilde #101 preserve runtime Markdown/example bytes. Five other clients deployed matching 904a8cb pins/callers; DxUi subsequently adopted e3c637b in #232. RedXe, RedTilde and RedMonitor adoption campaigns passed both native roles/architectures. RedMonitor #33 reused its identical successful native inputs without rebuilding. RedPrism's genuine ARM64 timeout remains red; a prose commit must preserve that outcome. Final selection/detection comparison and source-bound acceptance remain open. |
| S6B | NOT_STARTED | Case-level narrowing and broader historical/seeded failure comparison remain required. |
| S7 | NOT_STARTED | Trusted required candidate native gate and branch-policy enforcement remain required. Local native obligations have not been removed. |
| S8 | IN_PROGRESS | Same-run DxUi Release library inputs can avoid duplicate compilation while preserving actual regression and production SDK smoke. RedMonitor #33 demonstrates existing exact-input main outcome reuse. Adoption of trusted pre-merge candidate test results remains unimplemented. |
| S9–S10 | NOT_STARTED | Cadence acceptance, controlled organization-wide speed/detection measurements and final rollout/closeout remain required. |

Operational corrections during execution: generated `.ci-engine` checkouts in DxUi, RedTilde and RedXe were stale relative to their already-consistent source pins; restored those generated checkouts to their existing exact pins and reran the scoped checks. No producer dependency pin was advanced to hide a fixture failure.

S5 original native failure: Embedded failed in serial x64 Release before comparison, in the existing maximum-document geometry case. Matching dump/PDB evidence resolves the failure to DirectWrite overhang metrics inside the fatal observer. PR #229 repaired that opaque call using the established per-call native boundary. A zero-warning rebuild and two full noninteractive x64 Release runs then passed, retaining the original failed attempt separately. The [DxUi evidence](https://github.com/RedSalamanders/DxUi/tree/main/Measurements/TestingAcceleration_2026-11-09) owns exact source patch, image identities, suite/case lists and limits. Keep hosted scheduling serial until architecture acceptance succeeds; one local pair does not establish the overall 3x/2x targets.

The subsequent first-wave DxUi hosted x64 run at source 5f65003 failed its tooling prerequisite on two stale
source-contract assertions expecting the old direct watchdog call. That failed run remains failed. PR #230 fixes
the assertions, preserves real helper invocation/failure controls and passed complete local tooling validation.
Hosted acceptance must execute the integrated follow-up source; do not retry or relabel the old source as green.

The follow-up DxUi campaign at f73da6d failed its x64 tooling prerequisite because a local-baseline fixture
inherited hosted CI environment flags. PR #231 isolates only the fixture child's local environment and adds
an explicit hosted refusal case; real hosted execution still cannot adopt or publish local iteration baselines.
All 43 scoped controls passed with CI/GITHUB_ACTIONS/compiler-free flags enabled, complete tooling passed and
the exact static adapter now executes that compiler-free suite before native work. Engine #24 admits only this
reviewed DxUi command. Both native regression architectures passed at 0cc1ac0 in run 42659996089;
GitHub subsequently reported an internal server error and never started production. The campaign remains
failed, with production qualification unproved; neither earlier failed campaign is relabelled.

The same-run/attempt DxUi library/PDB input handoff merged in engine #25 and DxUi #232. It binds complete
canonical v2 inputs and exact bytes, cannot grant Full/test results, and retains source fallback and every
extracted-SDK gate. Eleven synthetic product controls, actual x64 producer/transfer/package execution,
53 shared engine controls and all workflow syntax checks passed. Source-bound timings and limitations live
in the DxUi measurement record. Final main 63ffc056151095e1776fab3a0fea6f22cb709e17 did not start native jobs
because of another GitHub internal error; both hosted architectures remain required. This does not yet
supply pinned SDKs to any of the five product consumers.

S3 acquisition facts refreshed after the access probe: the five consumers currently use three distinct SDK pins:
RedSalamander 4cdf1ce52c7785446698e346b8aec058ed6a9283 (API 4), RedXe/RedPrism/RedMonitor
f2e328a0a26a18ca66bf4b2aea77bf010c9515e1 (API 4), and RedTilde
21fae0dc66000b04504ba7862169533ac2943be8 (API 5). The access probe's qualified source 2a26dfbd
matches none of these pins. It must never be substituted for them. Cache identity must also bind each actual
consumer wrapper, imported native policy, CL/_CL_ options, configuration and annotation mode; matching pin/API
alone is insufficient. Source builds remain the fallback while this complete SDK contract is implemented.

Execution order follows the dependencies, not a requirement to finish every numbered slice serially. Start S0, then deliver the small S6A documentation/fragment classification correction alongside S1 and S2. Continue SDK/identity/scheduling work as its prerequisites close. Keep S7/S8 gate relocation and adoption behind their stronger acceptance barriers. Do not delay a proved, narrowly scoped removal of unnecessary native selection until the larger cache or CI redesign is complete.

### S0 — Freeze the obligation inventory and measure actual costs

- [ ] Owner: integration owner with all six client owners. Dependencies: none.
- [ ] Enumerate every current local/PR/main/production/extended obligation, its profile, role, native-host requirement, test inventory, producer/trust domain, input identity and exact gate. Include RedMonitor ETW/installer and DxUi consumer qualification.
- [ ] Reconcile actual deployed workflows/settings with source; identify duplicate legacy/event jobs by immutable run/role identity. Inspect active workflows rather than enabling or deleting them speculatively.
- [ ] Capture the scenario/phase metrics in section 5 and the current coverage/resource graph. Record missing data as unknown.
- [ ] Produce a per-project table of likely savings, effort and fix risk from measured critical paths. Include total runner minutes; do not sum percentages.
- [ ] Freeze pilot latency/compute targets, comparison workloads and noise/acceptance rules. Include first feedback, ready-to-merge and ready-to-release latency: moving a native wait before merge changes where the wait appears, and is beneficial only when the complete delivery path or feedback improves.
- [ ] Acceptance: another agent can reproduce a representative warm/cold invocation and account for every current obligation. Existing failed runs retain their actual status.
- [ ] Rollback: measurement is additive; no gate or receipt acceptance changes.

### S1 — Repair and prove the runner-to-CI evidence handoff

- [ ] Owner: canonical runner and adapter owners; shared engine verifies portable references. Dependencies: S0.
- [ ] Replace time-based recursive summary rediscovery with a runner-emitted exact run ID/summary reference through the existing output seam. Bind source, profile, role, coverage and trusted producer.
- [ ] Verify readiness and the producer/consumer schema contract with cheap isolated fixtures before a long campaign; keep final positive execution, artifact and immutable-result verification.
- [ ] Cover missing/multiple/stale/corrupt summaries, successful native exit with absent cases, interrupted archive/promotion, source mutation, zero discovery, wrong profile/role and failed Release detector.
- [ ] Acceptance: a valid canonical handoff succeeds; every invalid control fails before acceptance. No fallback to console text or accepting the newest file. Validate on both native hosted architectures where the handoff differs.
- [ ] Rollback: disable the new transport/consumer together and retain original evidence; never fall back to broader acceptance.

### S2 — Build only selected targets and their complete runtime closure

- [ ] Owner: each build/runner owner. Dependencies: S0; use S1 evidence where relevant.
- [ ] Derive selected compile targets plus dynamic plugin/resource/schema/helper staging from current project and runtime manifests. Reuse RedSalamander's existing focused `ProjectName` route and centralized runtime staging rather than duplicating it.
- [ ] Represent a multi-target build as one operation/receipt over its actual target and runtime union. Do not publish a solution-wide receipt after a partial build.
- [ ] Preserve profile artifact/dependency/package lock ordering, warning policy, provenance and exact `SkipBuild` admission. Adding a target or changing a shared header/restore input widens closure.
- [ ] Test a cold empty output directory, missing staged plugin/schema/resource, stale unrelated outputs, shared-input edits and concurrent disjoint profiles. Prove unrelated projects are not invoked using build logs.
- [ ] Acceptance: selected scenarios pass from clean outputs with correct deployment, zero accepted warnings/errors, and incompatible receipts refuse `SkipBuild`. Compare elapsed and build target counts with the full-build baseline.
- [ ] Rollback: select the existing full build; invalidate partial receipts rather than relabeling them.

### S3 — Reuse immutable SDK/dependency builds and support isolated local candidates

- [ ] Owner: DxUi producer integration plus all five consumers; RedMonitor SDK owner for its distinct producer path. Dependencies: S0 and S2 closure model.
- [ ] Implement section 6.4 through the existing full consumer fingerprint, with verified headers/imports/libraries/symbols/licenses and actual linker provenance. Define the organization artifact distribution mechanism and access before claiming cross-repository CI sharing.
- [ ] Preserve vcpkg/Terminal caching already deployed. Measure download/verification versus rebuild; incompatible pins/policies remain different entries.
- [ ] Add the explicit local candidate snapshot seam in section 6.5. Retain pin/API validation on qualification paths and distinct local outputs.
- [ ] Cover wrong compiler/SDK/CRT/architecture/configuration/API/annotation/macro policy, corrupt/incomplete entry, interrupted publish, concurrent writers/readers, eviction of an active reader, cold cache, offline cache behavior, dirty producer edits and switching back to the pin.
- [ ] Exercise a producer SDK against all five consumers at the intended exact pins/candidates; separately retain RedMonitor client-header and transport obligations.
- [ ] Acceptance: an exact hit invokes no producer compilation and yields identical accepted inputs; every mismatch rebuilds/refuses correctly. A cache hit never supplies a test verdict. Unpinned outputs cannot pass qualification/package gates.
- [ ] Rollback: bypass the cache/local override and rebuild from the exact managed pin; preserve corrupt-entry diagnostics and in-use data.

### S4 — Reduce identity overhead and add dependency-scoped local reuse

- [ ] Owner: evidence/runner owners. Dependencies: S0, S1 and S2; S3 entries use this identity model.
- [ ] Optimize measured repeated hashing/acquisition before changing semantics. Reuse immutable calculations, batch work and retain source/artifact barriers.
- [ ] Give deterministic component cases their complete source/test/runtime closure; split environmental cases instead of enabling blanket native-scope reuse.
- [ ] In RedSalamander, extend canonical schemas/promotion and the Affected/Resume mode matrix deliberately. Preserve existing Fresh semantics unless the owning contract explicitly changes.
- [ ] Cover every identity/receipt control in section 10, including a same-size edit with preserved timestamps, Git conversion/index flags, mutation during testing, changed runner/detector, expired evidence and a corrupt cache manifest.
- [ ] Acceptance: negative controls produce no incorrect reuse; an unrelated change outside a proven closure can preserve that component result; required global checks still run. Publish reuse/refusal reasons and measured acquisition/hash cost.
- [ ] Rollback: raise the cache-policy version and force fresh execution. Never rewrite previous receipts or silently recompute their acceptance digest.

### S5 — Parallelize safe work and avoid repeated harness setup

- [ ] Owner: test harness owners. Dependencies: S0 and S4 identity model.
- [ ] Wire DxUi's existing bounded `ParallelSuites` through its scoped entrypoint and CI adapter; verify its current implementation before extending it. Add resource metadata to other canonical runners only where needed.
- [ ] Cache successful filter/watchdog/lease/harness verification only under complete runner, native test binary, detector, policy and environment identities. A change to native harness code outside Tools invalidates it.
- [ ] Profile DxUi consumer qualification, repeated MSBuild/process startup and synthetic tooling fixture setup. Share immutable prepared inputs where semantics permit; keep independent negative controls and isolated mutable fixtures.
- [ ] Separate ordinary functional iteration from expensive performance campaigns, while selecting affected performance from product hot-path impact. Full/required qualification retains its coverage.
- [ ] Compare serial/concurrent case sets, outcomes and evidence. Exercise crashes/timeouts and shared-state collisions; measure memory, I/O contention and total compute. Keep benchmarks/foreground work serial.
- [ ] Acceptance: equivalent detection and result aggregation, no desktop takeover, no cross-case contamination, bounded resource use and measured elapsed improvement.
- [ ] Rollback: set concurrency to 1 and disable harness-result reuse without changing required test selection.

### S6 — Correct prose classification early, then enforce sound fine-grained selection

- [ ] Owner: scenario owners with planner owner. Dependencies: S6A's reviewed prose/fragment classification needs S0 only and can ship in the first implementation wave; S6B's executable case-level selection needs S0, S2 and S4.
- [ ] Map production inputs to direct and integration cases using existing inventories/graphs, including dynamic consumers, generated inputs and negative controls. Preserve specific matching-rule accumulation, rename sides and conservative unknown fallback.
- [ ] Correct the reproduced RedSalamander valid-Changes-fragment fallback through the canonical impact manifest. A valid prose fragment plus plan/index edits should select changelog/document validation without native work; malformed fragments must still fail validation, and executable/unknown inputs must retain conservative selection. Test the actual public explanation entrypoint and its canonical NOT_EVALUATED exit, not only a matching helper.
- [ ] Add case-level subsets where whole-suite fan-out is expensive. Retain ComboBox animation/text/host, plugin Settings/deployment, storage recovery/restart and affected performance.
- [ ] Run comparison mode with broader execution and a reviewed historical/seeded defect corpus. Report each discrepancy and repair the graph before enforcing narrower execution.
- [ ] Acceptance: every expected relevant failure is selected/detected; additions/deletions/renames/shared inputs and unknown paths fail closed. Explicitly record what the comparison corpus does not establish.
- [ ] Rollback: disable narrow enforcement and execute the existing broader plan; keep discrepancy evidence.

### S7 — Establish the required candidate integration gate, then relocate local work

- [ ] Owner: shared CI and branch-policy owner with client adapters. Dependencies: S0–S2, S4 and S6; use S3/S5 improvements as accepted.
- [ ] Implement a trusted, source-frozen candidate workflow/controller as a reviewed change to the current compiler-free-native routing policy. Candidate code gets no publication/account credentials; isolate untrusted cache writes. Keep static/security PR checks independent.
- [ ] Admit only integration-ready heads/batches under a bounded organization/native-architecture capacity budget. Select one authoritative event path rather than parallel full PR and merge-group campaigns. Define batch membership, stale-member/base invalidation and failure isolation; retain compatible completed evidence instead of restarting every member unconditionally.
- [ ] Freeze repository, PR head, base, synthetic merge tree, meaningful input digest, engine, dependency pins, version inputs, coverage and profile matrix. Native x64/ARM64 execution and real failure probes remain mandatory where declared.
- [ ] Bind a required branch/merge-queue check to that exact integration. Recheck available repository capabilities. If the hosting setup cannot prevent a stale-base candidate from satisfying merge policy, retain existing local/main obligations and report that capability gap.
- [ ] The matrix must explicitly place existing Debug/ASan/Full/performance/interactive obligations; some may remain local/manual. A Release success never closes absent profiles. Require a real ASan detector for sanitizer claims.
- [ ] Only after hosted positive/negative acceptance and required-check verification, let PrePush delegate the exact equivalent obligations and revise local completion policy. Do not label pending native CI a pass.
- [ ] Acceptance: stale head/base, fork/untrusted origin, changed pin/engine, missing architecture/profile, failed/disabled detector, zero execution and pending/cancelled checks cannot satisfy merge. API uncertainty keeps work local.
- [ ] Rollback: restore prior local coverage first, then disable candidate delegation; do not leave a coverage gap while removing the replacement gate.

### S8 — Adopt matching candidate evidence on main and avoid duplicate production work

- [ ] Owner: shared evidence/CI with each production adapter. Dependencies: S1, S4 and S7.
- [ ] Extend the current same-workflow/checkout trust boundaries explicitly. Main recomputes meaningful source/build identity and complete coverage, validates the original trusted run/attempt and retained immutable bytes, then emits a new adoption record referencing the original execution.
- [ ] Test code merge plus prose, changed base, changed version stamps, altered dependency/adapter/policy, changed runtime bytes, a newer failure, expired artifacts and cancellation. Reuse matching obligations only; execute missing ones.
- [ ] Preserve separate test-enabled and test-disabled production identities. Initially eliminate repeated work within the same role and compatible immutable dependency closure.
- [ ] Evaluate speculative production compilation only after runner-capacity measurements. Split compilation from smoke/promotion; RedSalamander smoke still requires the tested harness/regression artifacts. Both architecture regression gates must pass before production qualification or publication. New policy must explicitly define any earlier isolated compilation.
- [ ] Prefer testing production-compatible core libraries/binaries directly where architecture allows it. Moving a test hook into a DLL does not by itself prove equivalent production behavior. A larger removal of test/production divergence is a separately reviewed sub-slice with runtime, ABI, macro and clean-extraction proof; retain dual builds until it passes.
- [ ] Acceptance: a matching landed candidate runs no duplicate native campaign for the covered identity; a changed identity cannot adopt it. No object/output sharing contaminates production, and publication promotes exact qualified bytes.
- [ ] Rollback: disable adoption and run fresh main qualification. Disable speculative builds independently. Keep accepted immutable artifacts and original failures.

### S9 — Tune admission and changelog cadence after capacity evidence

- [ ] Owner: shared scheduler and release workflow owners. Dependencies: S0 and accepted scheduling/adoption.
- [ ] Compare current 300-second coalescing with a shorter/adaptive idle admission using queue time, merge bursts and total native minutes. A zero/30-second timer is a candidate setting, not an assumed universal win.
- [ ] Preserve cumulative meaningful-input identity, failed-state retention, no cancellation of admitted native work by newer pushes, stale-queued refusal and exactly-once admission. Test sustained merges and starvation explicitly.
- [ ] Change the shared engine's policy and independent admission verifier together; do not only edit a product wrapper or documentation. Deploy matching pins/callers to all six clients.
- [ ] Keep fragments in feature changes. Use an integration/release batch fold rather than assuming one fold PR per feature. Any scheduled writer is a separate authorized capability; current automation must not start opening PRs merely because cadence changed.
- [ ] Acceptance: measured latency benefit without an unaccounted compute/queue regression; no dropped obligation, duplicate native admission or accidental native work for excluded-only changes.
- [ ] Rollback: restore the previous debounce/cadence without overwriting CI state or existing changelog history.

### S10 — Complete all-seven rollout and close the plan

- [ ] Owner: integration owner. Dependencies: required S0–S9 deliverables; record any optional production-architecture experiment explicitly outside the accepted cut.
- [ ] Pilot isolated improvements in DxUi and RedMonitor, then RedXe, RedTilde, RedPrism and RedSalamander as their evidence is ready. Shared engine changes require engine acceptance plus each deployed client's matching adapter/pin acceptance.
- [ ] For each repository record source, engine/adapter pins, accepted slices, local checks, exact hosted runs, covered profiles/roles, measured results, pending manual/domain gates and rollback.
- [ ] Reconcile I32 scoped-testing ownership, I53 native policy, I56 hosted acceptance, I60 release readiness and each sibling's current WIP plans. Do not create a second owner for their product/runtime fixes or claim old red runs are repaired by a faster runner.
- [ ] Synchronize durable behavior into owning domain specs, guidance, public help, schemas and inventories. Keep product-specific ABI, deployment and sandbox policies deliberate.
- [ ] Complete section 12's gates before moving this plan to Done. Do not leave mandatory requirements only in this plan.

## 10. Required behavior and regression controls

These are test scenarios for the changed mechanisms, not a requirement to write a test for every helper. Extend existing meaningful fixtures and native cases.

| ID | Scenario | Required observable result |
|---|---|---|
| V01 | Clean tracked inputs, timestamp-only touch, identical commit/staging | Stable semantic identity; no needless rebuild/retest solely for metadata |
| V02 | Staged A then unstaged B; untracked addition; tracked ignored input; deletion/rename/type/mode change; Unicode paths | Actual consumed inputs represented; relevant obligations selected; conflict stages refuse |
| V03 | Same-size edit with restored timestamp; assume-unchanged/sparse/index flags; line-ending/attribute/filter changes | No stale proof accepted from Git status or stat-only equality |
| V04 | Source/dependency/artifact changes during build/test or snapshot acquisition | Run/receipt invalidated; no reusable success published |
| V05 | Relevant source/test/generated/schema/resource/runtime input changes; valid versus malformed Changes fragments and prose-only edits | Dependent build/tests execute; executable specs never treated as prose; valid fragments retain static checks without native work, while malformed fragments fail validation |
| V06 | Unrelated edit outside a proven component closure | Component reuse allowed where environmental/trust requirements also match; global validators retain their own obligations |
| V07 | Missing/extra/corrupt/wrong-profile runtime plugin/helper/schema/PDB association | Explicit build/staging or integrity refusal, not a warm-checkout accidental pass |
| V08 | Partial targeted build followed by Full or incompatible SkipBuild | Partial receipt cannot authorize broader artifact use |
| V09 | Concurrent cache writers/readers, interrupted publication, eviction, shortened-name collision, bad manifest | Readers see complete verified entries only; active entries preserved; full identity checked |
| V10 | Local producer changes; pinned/local switch; wrong API/toolchain/annotation policy; consumer link path differs | Snapshot invalidation, isolated outputs, actual provenance verification and qualification refusal when unpinned |
| V11 | Empty/filter-reduced inventory, absent results with exit 0, stale summary, failed/disabled detector, unexpected skip | No complete pass or reusable broader result |
| V12 | Serial versus parallel execution; shared clipboard/ETW/install state; crash/timeout/cancel | Same applicable coverage and failures, correct leases, contained child cleanup and retained evidence |
| V13 | Performance run alongside competing jobs; changed fixture/hardware/baseline | Reject non-comparable acceptance; preserve diagnostic data |
| V14 | Leaf control/plugin/storage edit with integration consumers outside its directory | Relevant integration cases remain selected and detect seeded regressions |
| V15 | Base/head/pin/version/engine advances between candidate testing and merge | Stale proof rejected; matching obligations recalculated |
| V16 | Same meaningful landed inputs; later prose commit; previous failed inputs; expired/cancelled run | Verified adoption only for matching successful evidence; failures/pending states never turn green |
| V17 | Production/test-enabled mix, restamped bytes, missing native smoke, modified ZIP | Production and publication refuse |
| V18 | Bursty and sustained merges; queued obsolete candidates; repeated retry; partial matrix failure | No duplicate/dropped admission; stale candidate stops before expensive setup; required failures remain blocking |
| V19 | External codec/device/ETW/clipboard/installer capability changes with unchanged binaries | Environmental obligation remains fresh or explicitly unmet; no synthetic cached pass |
| V20 | Modified runner/module/schema/policy/negative-control binary outside a naive Tools glob | Complete dependency closure invalidates harness/test acceptance |

Before narrowing coverage, replay a bounded, recorded historical/seeded defect corpus through both old and candidate execution. State which defects each mechanism is intended to catch. Include missing-runner-evidence and stale-artifact defects as well as product bugs. Any missed expected failure blocks the relevant optimization.

## 11. Commands, evidence locations and execution discipline

### 11.1 Documentation-only validation for this revision

From RedSalamander, validate its outgoing index/change fragment and product-owned references:

```powershell
./Tools/Test-Changelog.ps1
./Tools/Test-Changelog.ps1 -Base origin/main
./Tools/Get-SpecInventory.ps1 -FailOnFindings -OutputRoot .build/SpecInventory/i61-handoff
git diff --check
```

In the shared .github checkout, check `git diff --check` and all changed local Markdown destinations, confirm that the WIP index has exactly one link to this file, and verify the lifecycle rule in `AGENTS.md` plus the WIP/Done indexes. No native workflow or engine behavior has changed in this relocation.

These commands check documentation/workflow structure and do not establish implementation or native qualification. The spec inventory's governed disposable reports are build/tooling outputs under `.build`, not a native test-data sandbox.

### 11.2 Planning and implementation checks

Read current help/parameters before invocation. The following entrypoints exist at the inspection snapshot; proposed future switches/receipt categories in this document are not executable until implemented.

| Repository | Planning and focused execution route |
|---|---|
| RedSalamander | `./Test-Changes.ps1 -Explain -TestRoot $MarkedTestRoot`; affected run through the same wrapper; focused `-Suite Commands/Compare/FileOps` where appropriate; use canonical entry selection for tooling tests |
| DxUi | `./Test-Changes.ps1 -Explain`; `./Test-Changes.ps1 -Scopes ComboBox,Animation -Platform x64 -Configuration Debug` is an example focused native route, not whole-repository acceptance |
| RedPrism / RedTilde / RedXe | `./Test-Changes.ps1 -Explain`; affected/default and explicit scopes/profiles supported by their current help; affected tooling tests through their canonical runner |
| RedMonitor | `./Test-Changes.ps1 -Explain`; wrapper currently has Mode/Explain only, not the other projects' scope/profile switches; Full/PrePush select its current multi-profile/ETW/installer work |
| Shared .github | `./Tools/Test-Workflows.ps1 -Root .`; `./Tests/Test-Engine.ps1 -TestRoot $MarkedTestRoot`; dependency-status controls when their owning code changes |

`$MarkedTestRoot` means an already authorized, correctly marked root accepted by that repository's runner. It is not an instruction to initialize one. RedSalamander native test data/evidence stay under its exact marked `X:/RedSalamander.Perf`; other repositories retain their own current contracts. No test links, mounts or cleanup may escape the owning sandbox.

While editing implementation, run affected checks and meaningful V01–V20 controls for the changed slice. Before delivery, use the repository's supported PrePush command and applicable profile/domain obligations; do not assume the wrappers have identical parameters. A delegated check remains pending until it actually passes.

When RedSalamander Full is explicitly required, use `./Tools/Run-AllTests.ps1 -Suite Full -ValidationMode Fresh -TestRoot $MarkedTestRoot` with the required native profile. `SkipBuild` requires a compatible byte-verified receipt; exact Full continuation uses `-ValidationMode Resume -ResumeFrom <run-id>`. Noninteractive selection can leave foreground work pending; do not add `-Interactive` without agreement to the time. Preserve canonical exit 2 / NOT_EVALUATED rather than translating it into repository success.

For any tooling edit, first read `Tools/README.md`, the owning tooling-governance contract/skill and current command help. Update inventory/classification, exports, callers, complete dependency keys, public help, focused tests, specs and a dated Changes fragment in the same change. Keep stable entrypoints and thin compatibility shims where required.

Native build changes retain the owning zero-warning/zero-error acceptance, exact toolchain/dependencies, diagnostic formats and Release optimization policy. Do not weaken flags, detector assertions, timeouts or platform requirements to make a result green. Follow crash-forensics before rerunning a failed native scenario; preserve dumps/raw logs and terminate only operation-owned descendants.

### 11.3 Evidence and review package

Use each owning runner's approved evidence root. In RedSalamander, archive the small source-bound narrative/index under `Specs/TestRuns/`; raw generated test/performance scratch and logs stay in the marked sandbox. Never copy whole sandbox trees, private machine content or credentials into the repository.

For every implemented slice retain: exact source/pin/engine/adapter identity; command and supported parameters; selected and excluded obligations with reasons; native architecture/profile/role; baseline/candidate phase metrics; raw run references and immutable digests; negative-control outcomes; failures/skips/pending gates; reviewer and rollback. Preserve original evidence after a retry.

## 12. Acceptance, rollback and closeout

### Required acceptance

- [ ] All seven repositories are accounted for, with current source/deployed-engine drift reconciled.
- [ ] The obligation inventory names where every previous required check is executed or validly reused. No gate was removed before its replacement was accepted.
- [ ] Relevant V01–V20 controls and historical/seeded detection comparisons pass on the changed source. Claims state the tested corpus, not universal proof.
- [ ] Targeted builds work cold with complete runtime staging, correct receipts and accepted compiler diagnostics.
- [ ] Exact SDK/cache hits avoid compilation; mismatches, corruption, races and local-unpinned outputs cannot qualify.
- [ ] Parallelism retains coverage, ownership, resource budgets and evidence; performance/interactive work retains its own requirements.
- [ ] Candidate integration is genuinely required and tied to the tested merge inputs before local coverage is delegated.
- [ ] Main adoption verifies original trusted evidence and landed identity without rewriting execution provenance. Changed artifacts/coverage trigger the appropriate work.
- [ ] Both native architectures and all applicable domain/profile gates are represented honestly. Production/package smoke and exact artifact promotion remain intact.
- [ ] Per-project measured outcomes report latency, compute, retries and limitations. The frozen pilot performance targets are met, or an explicit owner decision accepts a revised measured outcome. Missed targets without that decision remain open in WIP; do not close them with an unmeasured speedup or an unowned follow-up.
- [ ] Every deployed engine pin and workflow caller agrees; six client integrations pass the new shared behavior. Engine self-tests alone are insufficient.
- [ ] Existing product failures remain assigned to their current owners. An unrelated baseline failure may be recorded separately, but cannot be relabeled passed, silently waived, or used to claim full product/release acceptance.
- [ ] Normative contracts, schemas, help, inventories and dated fragments are updated with implemented behavior; this plan contains no sole surviving requirement.

### Rollback and stop conditions

Disable optimizations independently: concurrency to 1, cache bypass/fresh execution, broad selection, fresh main qualification, previous admission timing. Restore local coverage **before** withdrawing its replacement hosted gate. Increase policy/schema versions to invalidate incompatible evidence; preserve old receipts, failing runs and in-use cache entries.

Stop only the dependent slice on an unresolvable source/ownership conflict, missing required branch capability, inability to prove input/runtime closure, unknown producer trust, incorrect reuse, missed expected failure, sandbox violation, unowned-process interference, or unreconciled native diagnostic. Continue independent authorized work where possible. Escalate the concrete missing decision/evidence; do not weaken acceptance or infer approval from elapsed time.

Paid runner pools/artifact services, visibility/security/account changes, publication and focus-taking runs need their existing specific authorization. Prepare a concrete measured configuration before requesting a decision. No such infrastructure or publication action is part of this documentation revision.

### Closeout

Implementation completion and product qualification are separate records. Reconcile [I32](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Plans/WIP/ScopedTesting_2026-10-05.md), [I53](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Plans/WIP/NativeBuildPolicyCoherence_2026-10-28.md), [I56](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Plans/WIP/CI_HostedAcceptance_2026-10-31.md), [I60](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Plans/WIP/PreProduction_ReadinessAndSimplification_2026-11-07.md) and sibling ownership before closeout.

Only after the accepted implementation cut and its required implementation, test, evidence and specification gates close, move this file within the shared .github repository from `Specs/Plans/WIP/` to `Specs/Plans/Done/`. Remove its WIP index entry, add its Done index entry, update inbound links and record the exact implementation/evidence references and any separately owned product qualification. Move durable requirements into the owning normative contracts before closeout. A plan, static check, partial implementation or pending CI cannot justify the move.

The shared engine's `AGENTS.md` owns this lifecycle rule. RedSalamander's exact-path Done-admission mechanism remains specific to that repository; it is not an existing shared-engine command or gate. Do not edit frozen historical Done records or fold a product feature's Changes fragment during this move.

## 13. Disposition of the original options

This table preserves the original identifiers for handoff continuity; the corrected design and slices above are the implementation authority within this non-normative plan. Effort/risk are planning estimates, not measured savings. Starting facts in section 4 were statically verified; future latency and cache effectiveness require execution evidence.

| Original option | Disposition and implementation owner | Effort / change risk |
|---|---|---|
| 1A narrow scopes | Replace filename-only trimming with complete consumers, exact cases and comparison evidence; S6 | Medium–large / high if unsound |
| 1B enable reuse | Build complete component identities; split environmental suites; extend RedSalamander's real mode contract; S4 | Medium–large / high |
| 1C tooling/benchmark split | Pursue dependency-scoped harness reuse and explicit affected performance; retain negative controls; S5 | Medium / medium |
| 2A single-profile local completion | Use a fast native profile during editing; relocate completion only after a required equivalent candidate gate; S7 | Large organization change / high |
| 2B target-only builds | Prioritize complete compile/runtime staging and correctly scoped receipts; S2 | Medium / medium |
| 2C Git-index/PDB shortcut | Reject the shortcut; optimize acquisition without weaker byte/symbol identity; S4 | Medium–large / high |
| 3A shorter quiet window | Measure latency/throughput; change shared policy and verifier together; S9 | Small code, medium rollout / medium |
| 3B parallel/single production build | Remove same-role duplication first; isolate speculative compilation; production equivalence is a separately reviewed sub-slice; S8 | Medium–large / medium–high |
| 3C shared DxUi cache | Prioritize full compatible immutable SDK entries and real cross-repository distribution; include RedMonitor; S3 | Medium–large / medium–high |
| 4A fold cadence | Use existing batching; consider integration/release cadence without claiming a 50% guarantee; S9 | Small / low |
| 4B local DxUi override | Prioritize immutable local candidate SDKs with isolated outputs and enforced taint/provenance; S3 | Medium / medium–high |

The implementation record and linked evidence state the delivered subparts, native outcomes and measured limits. Overall 3x/2x targets and unfinished acceptance remain open. The initial catalog's universal percentage savings and low-risk labels are replaced with source-backed constraints, ordered work and observable acceptance.
