# I63 Shared project tooling: each shared script exists once

Status: **ACTIVE.** T1 (shim pattern) and T2 stage 1 (changelog suite) merged in #87 (`0226b660`); T2 stage 2 (R1 to
R4) is in the second pull request. No product has adopted a shim yet; everything else is plan only.
Owner: organization CI and tooling owner.
Prepared: 2026-11-18 at engine `a094b2ea66fc6fd7a8933488a71dacda262903a4`.
Scope: `RedSalamanders/.github` and the product copies of shared tooling in `DxUi`, `RedSalamander`, `RedXe`,
`RedPrism`, `RedTilde` and `RedMonitor`.

- **Driver**: RedHome [convergence plan](https://github.com/RedSalamanders/RedHome/blob/main/Specs/Plans/WIP/Convergence_2026-11-17.md),
  Phase 5 (steps CV-5-01 to CV-5-07, register rows E and F). That plan owns the order and the gates; this one owns the
  engine design.
- **Contract**: [Specs/ProjectCommands.md](../../ProjectCommands.md) (the shim contract and every command it lists).
- **Coordinated plans**: [I62](ExplicitStateMachines_2026-11-10.md) also changes `ScopedTesting.psm1`,
  `TestRunEvidence.psm1` and `Test-Changes.ps1` in the products. T4 below takes those files into the engine, so I62's
  Pattern D work on them lands in the engine copy once T4 has moved them.

## Rules

1. A command moves byte for byte first. Only `-Root` (or another parameter whose default names the product) becomes
   mandatory in the engine, and paths to sibling commands point at the engine. A product adopts it in one pull request
   per repository that replaces its copy with the template shim; nothing else changes in that pull request.
2. Forks are reconciled only after the engine tests pin every variant's behavior. A reconciliation that changes a
   parameter set or a behavior some product relies on is written below first and waits for the owner's review.
3. A product sees an engine change only through its pin, in a pin wave of all repositories.

## Steps

| Step | RedHome | What | State |
| --- | --- | --- | --- |
| T1 | CV-5-01 | Shim pattern: `Ci.EngineBinding.psm1`, `Templates/Project/`, refusal cases | Merged in #87; RedMonitor pilot waits for its pin wave |
| T2 | CV-5-02 | Changelog suite (F-01): stage 1 moves the variant of RedXe, RedPrism, RedTilde and RedMonitor; stage 2 reconciles RedSalamander and DxUi | Stage 1 merged in #87; stage 2 R1 to R4 in the second PR; R5 waits for the owner; product shims after each pin wave |
| T3 | CV-5-03 | `BuildConsole.psm1`, `NativeBuildPolicy.targets` and the Release block, `Get-CiNativeScope.ps1`, `setup-msvc`; fixed-path files written by `Update-ProjectPin.ps1` and checked by conformance | Design below; item 3 taken as proposed on 2026-11-19. Items 1 and 2 touch the native path; item 4's shim half is done (#92), the rest waits for CV-6-05 |
| T4 | CV-5-04 | `ScopedTesting.psm1`, `TestRunEvidence.psm1`, `Test-Changes.ps1` with one parameter set: one planner, per-repository suite and path data | Engine planner, runner, schema and shims implemented. Hosted fixture evidence precedes product migration |
| T5 | CV-5-05 | One skill grammar and package-integrity policy | Design below (G1 to G13, defaults taken 2026-11-19); engine implementation merged in #95 |
| T6 | CV-5-06 | DxUi consumer interface and RedMonitor client scripts (not engine-owned) | Not started |
| T7 | CV-5-07 | `vcpkg-install.ps1`, `VcpkgTriplet.psm1`, `VisualStudio.psm1`, `Install-ClangFormat.ps1` | Not started |

## T2 stage 2: reconciling the changelog variants

Variants on 2026-11-18 (SHA-256 after line-ending normalization, first ten hex digits):

| File | Common (RedXe, RedPrism, RedTilde, RedMonitor) | RedSalamander | DxUi |
| --- | --- | --- | --- |
| `Changelog.psm1` | `cfaac3116b` | `2daadad2f4` | `d79e82cc7d` |
| `Test-ChangelogWorkflow.ps1` | `2595c68321` | `cf24e8f147` | `38b488a511` |
| `Submit-ChangelogFold.ps1` | `4d1bd6e14c` | same as common | `5da2b8616f` |
| `Fold-Changelog.ps1`, `Test-Changelog.ps1` | `3fc20a0c32`, `9e6c384d06` | same as common | help text only |
| `Release-Changelog.ps1`, `Tools/Changelog.psm1` (compatibility import) | absent | absent | DxUi only |

Differences and the proposed single behavior, chosen by the governing rule of the RedHome plan (a producer contract,
then the stricter option, then the majority, then fewer files):

| # | Difference | Proposed | Why | Changes behavior in |
| --- | --- | --- | --- | --- |
| R1 | A Git error while reading the base: common and RedSalamander treat any failure as "no changelog at the base" (fails open); DxUi lists the tree first and fails closed on other errors | DxUi | Stricter | none that pass today |
| R2 | Reused fold branch: DxUi proves its parent and exact fold and refuses unrelated files; DxUi ignores cross-repository fold pull requests | DxUi | Stricter | none that pass today |
| R3 | Two pending fragments with the same text: common folds one silently, DxUi warns, RedSalamander refuses the fold | RedSalamander's refusal, plus DxUi's warning when a fragment is skipped because its entry is already published (the retry case) | Stricter; the two do not overlap | a fold with ambiguous duplicates, which loses an entry today |
| R4 | Release cut: only DxUi has `Release-Changelog.ps1` and accepts the exact generated release transition under `-Base` | Engine command `Tools/Release-Changelog.ps1`, accepted everywhere | Additive; one exact generated transition | a repository that never runs it: none |
| R5 | A merged, unfolded fragment removed without its entry (a revert or a withdrawal): common and RedSalamander refuse it ("restore it"); DxUi accepts it (its review finding R28-53) | **Default, taken 2026-11-19.** Refuse, as five repositories do; a revert then keeps the fragment and adds its own | Stricter and the majority; DxUi's own contract would change | DxUi under the default; the other five under the alternative |

R5 is the only difference where both end states are reasonable. On 2026-11-19 the owner said "finish it", which, as for
D14 to D19 of the RedHome plan, takes the default: refuse. DxUi adopts the engine commands with that behavior. If the
owner later picks the alternative, the engine change is DxUi's withdrawal block in `Get-ChangelogFoldProblems` and its
case, and the "unfolded removal" case of the other five is dropped.

Stage 2, as implemented in the second pull request: the RedSalamander duplicate case and the DxUi release, reused-branch
and fork-filter cases are in `Tools/Test-ChangelogWorkflow.ps1`, with a new case for R1 (a missing base object); R1 to
R4 are in `Ci.Changelog.psm1` and `Submit-ChangelogFold.ps1`; `Tools/Release-Changelog.ps1` and its shim are new, so
every product adopts five shims. Next: shim `RedSalamander` once its pin includes stage 2; shim `DxUi` once R5 is
decided. DxUi also keeps `Tools/Changelog.psm1` as a module shim for its validators until they import the engine
module. DxUi's PrePush case that refuses an uncommitted tree belongs to its `Test-PrePush.ps1` (T4, register E-04),
not to the changelog suite.

## T3 design: build console, native policy, scope script, MSVC setup

Inventory on 2026-11-19 (SHA-256 after line-ending normalization, first ten hex digits):

| File | Variants | Notes |
| --- | --- | --- |
| `Build/BuildConsole.psm1` | `c1241e6886` RedMonitor, RedXe, RedPrism, RedSalamander; `a520d039d4` RedTilde; `e00e2d6051` DxUi | One lineage, each later copy stricter: RedTilde also refuses a tool exception dump (`ExceptionCode = <nonzero>`) despite a green footer; DxUi also requires the completed `Build succeeded.` / `0 Warning(s)` / `0 Error(s)` / `Time Elapsed` summary, keeps up to 16 diagnostic lines and uses bounded linear regexes |
| `Tools/Get-CiNativeScope.ps1` | `f4db2d8caa` RedPrism, RedTilde | No workflow calls it; it serves the PR-delegated native coverage (`prCoverage`) that the engine refuses. Retire it with the dead delegation code in T4, not alone, since each `ScopedTesting.psm1` still lists it |
| `.github/actions/setup-msvc/action.yml` | `a1a6d2ba61` RedMonitor, RedPrism, RedTilde, DxUi; `7d23a02d35` RedXe (logs on failure only, 14-day retention); `0aab601b7a` RedSalamander (no log upload) | The engine's own `native.yml` and `integration-execution.yml` run the product's copy (`uses: ./.github/actions/setup-msvc`) |
| `.github/actions/setup-msvc/Setup.ps1` | `bce333fd96` RedMonitor, RedTilde; RedXe, RedPrism, RedSalamander and DxUi each differ | DxUi is the most hardened (download and installer timeouts, owned process handle, path-length guard, shared Visual Studio discovery); RedPrism exports `MSBUILD_EXE_PATH` for later steps |
| `Build/NativeBuildPolicy.targets`, the Release optimization block and the MSVC 14.52 check | see register C-02, C-10, C-12 | The build-profile stream found (2026-11-18) that a consumer's copy must equal the copy in the DxUi commit it pins, because the pinned DxUi archive compiles under it and each consumer hashes its own copy into the DxUi build identity |

Proposed homes and order, each step its own engine pull request and then one product pull request per repository:

1. **`BuildConsole.psm1`** moves to `Tools/Modules/Ci.BuildConsole.psm1` as DxUi's variant (the strictest). Its summary
   rule needs every product's file logger to write the summary: RedXe logs at `Verbosity=minimal` and RedSalamander at a
   caller-chosen verbosity, so those two add `;Summary` to their `/flp` first, each in its own pull request proven by
   the six builds (D21). Products keep `Build/BuildConsole.psm1` as a module shim, which needs a module form of the
   binding (`Resolve-CiPinnedEngineModule`), added with its refusal cases.
   *Stage 1, implemented 2026-11-19:* the module binding, `Ci.BuildConsole.psm1` as RedTilde's variant (the four-repository
   variant plus the tool-exception refusal, which needs no logger change) and the shim
   `Templates/Project/Build/BuildConsole.psm1`, tested by `Tests/Test-ProjectModules.ps1`. RedMonitor, RedXe, RedPrism,
   RedTilde and RedSalamander adopt the shim after their pin wave; DxUi keeps its stricter copy until stage 2 adds the
   summary rule, after RedXe and RedSalamander log MSBuild summaries.
2. **`setup-msvc`** moves to the engine as `.github/actions/setup-msvc`, DxUi's `Setup.ps1` plus RedPrism's
   `MSBUILD_EXE_PATH` export and RedXe's upload-on-failure rule; the required MSVC family stays product data. The
   engine workflows then use `./.ci-engine/.github/actions/setup-msvc`, and products delete their copies. Only native
   jobs run it and pull requests never do, so the step is proven by one manual qualification per product after its
   pin wave; it is a native-path change and waits until the vcpkg restore failures of 2026-11-18 are fixed.
3. **`NativeBuildPolicy.targets` and the Release block** belong with the DxUi pin, not with the engine pin, because the
   DxUi archive compiles under the consumer's copy. Proposal for the owner: home them in the DxUi consumer interface
   (T6, `Build/DxUi.Consumer.*`), which already travels with that pin, and keep only the toolset check in the engine.
   This changes the homes table of the RedHome plan; taken as the proposal on 2026-11-19 ("finish it"). It still waits
   for the build-profile stream's part 1, which edits these files now.
4. **Fixed-path files** (`.clang-format`, `.editorconfig`, the common `.gitattributes` and `.gitignore` blocks) are
   written by `Update-ProjectPin.ps1` from `Templates/Project/` and checked by `Test-CiProjectConfiguration`, once the
   formatting stream (CV-6-05) has made them equal by hand; until then a check would only fail.

## T4 design: one planner, one runner, per-repository data (for the owner's review)

**Status: design accepted with its defaults on 2026-11-19, when the owner said "finish it" (the same rule as D14 to D19:
the default where the plan has one, the proposal for O1 to O4). It changes the `Test-Changes.ps1` parameter set in
four repositories; the "other end state" column stays here so the owner can still reverse any row.**

### What exists (inventory of 2026-11-19, origin/main of each repository)

| Repository | Runner | Planner and evidence | Data |
| --- | --- | --- | --- |
| RedXe | `Test-Changes.ps1` `2e5a72043a` | `Build/ScopedTesting.psm1` `46793b0ff8`, `Build/TestRunEvidence.psm1` | `Tests/test-scopes.json` (16 scopes, 34 rules) |
| RedPrism, RedTilde | `Test-Changes.ps1` `4af5c48cd6` (identical) | `Build/ScopedTesting.psm1` `5bc318df36` / `0c1f9ff177`, `Build/TestRunEvidence.psm1` | `Tests/test-scopes.json` (10 / 12 scopes) |
| DxUi | `Test-Changes.ps1`, `Test-PrePush.ps1` (six profiles) | `Tools/ScopedTesting.psm1` `789fe7599a` (41 exports), `Tools/TestRunEvidence.psm1` | `Tests/test-scopes.json` (20 scopes, 54 rules, `interactiveObligations`) |
| RedSalamander | `Test-Changes.ps1`, a forwarder to `Tools/Run-AllTests.ps1` (2,857 lines) | `TestRunPlan.Common.psm1`, `ValidationFingerprint.psm1`, `ValidationEvidence.psm1`; its `ScopedTesting.psm1` is used only by tests | `Tools/validation-impact.json`; its `test-scopes.json` feeds only dead code |
| RedMonitor | `Test-Changes.ps1` (three parameters) | `Build/Toolchain.psm1` `Get-RedMonitorChangePlan`, `Build/IndependentValidation.psm1` | none; `Tests/native-test-files.json` |

Parameters today: all six take `-Mode Affected|Full|PrePush` and `-Explain`. RedXe, RedPrism, RedTilde and DxUi also
take `-BaseRef`, `-Scopes`, `-Configuration`, `-Platform`, `-Force`, `-SkipBuild`; DxUi adds `-ParallelSuites`;
RedSalamander adds `-ResumeFrom`, `-Interactive`, `-TestRoot`, `-AllowAlternateVolumeTestRoot`, `-Suite`, `-CaseFilter`,
`-CommandsFamily` and has no `-Scopes` or `-Force`; RedMonitor has only `-Mode`, `-Explain`, `-Force`.

Dead everywhere, because `prCoverage` is empty and the engine refuses it: the PR-delegation code in every planner, the
manifest keys `repository`, `prCoverage`, `prWorkflowDigest`, `prContractClosure`, `prContractFiles`,
`prNativeScopeModule`, the `gh` hash in DxUi's tool identity, `Tools/Get-CiNativeScope.ps1` (RedPrism, RedTilde) with
`Test-ScopedNativeCiProof`, and `toolingCommands` in RedPrism and RedTilde. Also dead: RedTilde's `projectBindings`
path and the `RedPrism` build-number branch in the RedTilde copy. A DxUi process list
(`DxUi.(ControlTests|EmbeddedTests|FoundationTests|InteractiveLease).exe`) is hard-coded in all four evidence forks.

### Proposed end state

- Engine `Tools/Modules/Ci.ScopedTesting.psm1` (planner, receipts, leases, identities) and
  `Tools/Modules/Ci.TestRunEvidence.psm1`, and the runner `Tools/Test-Changes.ps1`; each product keeps a root
  `Test-Changes.ps1` shim (the binding already supports a shim at the product root). The dead code above is deleted,
  not moved.
- Per-repository data only, in `Tests/test-scopes.json` version 2 with an engine schema: `defaultBranch`, `scopes[]`
  (`name`, `native`, `reuse`, `configurations`, `commands`), `rules[]` (`pattern`, `scopes`, `reason`, `exclusive`),
  `nativeInventory`, `runtimeFiles`, `prose` patterns and `unscoped` folders, `interactiveObligations`,
  `buildNumber` (`none` or `mergeBaseCount`), `projectBindings`, and the process names its evidence watches. Every
  literal of section 3 of the inventory becomes one of these keys.
- One parameter set: `-Mode Affected|Full|PrePush`, `-BaseRef`, `-Scopes`, `-Configuration`, `-Platform`, `-Explain`,
  `-Force`, `-SkipBuild`, `-ParallelSuites`. This adds parameters to RedMonitor and removes RedSalamander's seven
  extras from this command (see O4).

### Behaviors the single runner must pick (default by the RedHome governing rule; the owner may pick the other)

| # | Difference | Proposed default | Other end state |
| --- | --- | --- | --- |
| B1 | Default base | `origin/<defaultBranch>` from the data (four repositories) | RedSalamander `origin/HEAD`; RedMonitor hard-coded `origin/main` |
| B2 | Base cannot be resolved | Refuse, naming the remedy (four) | RedMonitor selects native Debug coverage |
| B3 | Changelog gate | First in every non-Explain run, with `-Base` in PrePush, and PrePush refuses an uncommitted `CHANGELOG.md` or `Changes/` (DxUi; stricter) | PrePush only (RedXe, RedPrism, RedTilde) |
| B4 | Iteration baseline | DxUi's: 24-hour limit, bound to tools and dependencies, off in CI, with an explicit base, `-Force` or instrumentation (stricter) | none (RedXe, RedMonitor); no age limit (RedPrism, RedTilde) |
| B5 | Reuse of a prior pass | DxUi's: also needs the suite report with exit 0 and no skips; a capability-skipped pass is never reused (stricter) | receipts alone |
| B6 | Inputs change during a run | Refuse (five) | RedXe warns and records nothing |
| B7 | Evidence location | `.build/reports/scoped-tests/<platform>-<configuration>/` (four) | RedMonitor `.build/validation-evidence/`; RedSalamander outside the repository |
| B8 | Concurrent runs | Fail-fast mutex per checkout, platform and configuration, re-entrant for nested `build.ps1`/`test.ps1` (DxUi) | RedMonitor waits up to 30 minutes; RedXe none |
| B9 | Interactive suites | Never run by this command; listed as `INTERACTIVE_NOT_RUN` from the data (DxUi). The one interactive entry point is register E-13 | RedSalamander `-Interactive` |
| B10 | Host architecture | Exact match for runtime tests (DxUi; stricter); a cross build stays a build | RedXe, RedPrism, RedTilde run x64 tests on an ARM64 host |
| B11 | Independent checks | Each non-native scope runs its `commands` in a child `pwsh`; formatting is such a scope everywhere (RedPrism, RedTilde, RedMonitor; stricter) | RedXe and DxUi run `toolingCommands` in process and never check formatting |
| B12 | Build granularity | Whole profile (four; fewer moving parts) | DxUi builds a project subset in a non-full affected run |
| B13 | Unmapped path | Full fallback (five) | RedMonitor selects native Debug |
| B14 | Status tokens | One vocabulary: `NOTHING_SELECTED`, `PROSE_CHECKS_PASSED`, `SELECTED_PASSED`, `FULL_PASSED`, each followed by `; repository NOT_EVALUATED` | today's four vocabularies |

### Owner choices (taken with the proposal on 2026-11-19)

| # | Question | Proposal |
| --- | --- | --- |
| O1 | PrePush profiles: one profile per call (RedXe, RedPrism, RedTilde), the six-profile wrapper `Test-PrePush.ps1` (DxUi), or x64 tests plus ARM64 builds in one call (RedMonitor) | PrePush runs every profile the repository qualifies locally in one call, from data, and `Test-PrePush.ps1` goes |
| O2 | `-Scopes` given as one comma string (four) or as an array (DxUi) | Both: split on commas |
| O3 | RedMonitor's planner (three kinds: none, prose, native) | Replaced by data rules, with the same three outcomes |
| O4 | RedSalamander: its `Run-AllTests.ps1` planner, evidence outside the repository and resume are a different system, not a fork | Its `Test-Changes.ps1` becomes the shim like the others, and `Run-AllTests.ps1` stays its `test.ps1` behind the data's native scopes; resume and the external test root move to the register row for test runners (E-03). This needs RedSalamander's own plan first |

### Order once reviewed

1. Engine: delete nothing yet; add the schema and the planner with fixtures that pin each fork's current outputs
   (plan, reasons, tokens) for the same synthetic changes, so every behavior change above shows as a named difference.
2. Engine: implement the chosen behaviors; the fixtures then show only the accepted differences.
3. Products, one pull request each after their pin wave: data file version 2, root shim, dead code and
   `Get-CiNativeScope.ps1` deleted. Order: RedPrism and RedTilde (identical runner), RedXe, DxUi, RedMonitor, then
   RedSalamander after O4.

### T4 implementation (2026-11-19)

Engine: `Schemas/test-scopes.schema.json` (version 2), `Tools/Modules/Ci.ScopedTesting.psm1`,
`Tools/Modules/Ci.TestRunEvidence.psm1`, `Tools/Test-Changes.ps1 -Root` with the one parameter set, the bridge
`Tools/Invoke-ScopedScript.ps1` (it hands `test.ps1` a real `-Suites` array), the shims `Templates/Project/Test-Changes.ps1`,
`Templates/Project/Build/ScopedTesting.psm1` and `TestRunEvidence.psm1`, and `Tests/Test-ScopedTesting.ps1`
(17 cases on Windows). B1 to B14 and O1 to O3 are implemented. Differences from the forks, beyond the B rows:

- RedPrism's and RedTilde's `Format` scope keyed on compiled source only; that special case is dropped, so a prose edit
  reruns `format.ps1 -Check`.
- The whole-tree fingerprint leaves out the data's `unscoped` paths instead of each fork's own folder list.
- The iteration baseline (B4) binds the environment, Git and build-output identities; DxUi's separate vcpkg and
  toolchain fingerprint, project-subset builds, harness preflight, failure evidence and image archive are not ported.
- `prePushProfiles` has no version-1 source. The converted RedPrism data uses x64 Debug, Release and ASan Debug with
  tests and the three ARM64 profiles as builds; **the owner confirms this list** (O1).
- A converted RedPrism data file plans the same scopes as RedPrism's own planner for 43 representative paths.

Product migration needs, per repository: the version-2 data file, the three shims, deletion of its forks and
`Tools/Get-CiNativeScope.ps1` (and DxUi's `Test-PrePush.ps1`); its `test.ps1` writes
`.build/reports/<suite>-<platform>-<configuration>.json` with `exitCode` and `skips` (RedPrism, RedTilde and RedXe do
not yet) and takes the profile lease through `Enter-ScopedProfileLease`; RedMonitor's `build.ps1` and `test.ps1` take
the runner's parameters and its packaging and installation checks become scopes; DxUi's module path `Tools/` needs a
template of its own. RedSalamander follows O4.

## T5 design: one guidance validator (defaults taken 2026-11-19)

Inventory of 2026-11-19: RedHome `Tools/SkillValidation.psm1` and `WikiValidation.psm1`; RedXe `Build/SkillValidation.psm1`,
`SkillPackageIntegrity.psm1`, `SkillText.psm1`; RedPrism `Build/SkillValidation.psm1`, `SkillPackageIntegrity.psm1`;
RedTilde `Build/SkillPackageIntegrity.psm1`; DxUi `Tools/Validation.psm1` (skill part); RedMonitor
`Build/AgentGuidance.psm1`; RedSalamander none. RedHome, RedXe and RedPrism share one front-matter parser and the same
`name` and `description` rules; all 45 skills on `main` pass it. RedXe's integrity checker descends from RedTilde's.

Engine `Tools/Modules/Ci.AgentGuidance.psm1` and command `Tools/Test-AgentGuidance.ps1 -Root`; each product's
`validate-skills.ps1` runs the command through its `Tools/Test-AgentGuidance.ps1` shim (register E-01 puts
`validate-skills.ps1` at every root). The rules, each chosen by the governing rule (a producer contract, then the
stricter option, then the majority, then fewer files):

| # | Rule | Choice | From |
| --- | --- | --- | --- |
| G1 | Front matter | The shared parser: keys `name`, `description`, `license`, `allowed-tools`, `metadata` (one level); block scalars; YAML 1.1 typed values refused as strings; `name` equals the folder, ≤64, lowercase-hyphen; `description` ≤1024 code points, no `<` `>`, no `[TODO:` | RedHome = RedXe = RedPrism (register A-16) |
| G2 | Reading | Strict UTF-8; a byte order mark, UTF-16/32 and NUL bytes are refused, per skill | RedXe (stricter) |
| G3 | Fences | An unclosed fence in any scanned Markdown is reported with its line; the rest of the file is still checked | RedXe (stricter) |
| G4 | "Use when" | `description` contains `Use when` (case-sensitive) | RedHome plan CV-2-13; six skills change in their product's adoption pull request |
| G5 | Skill roots | `.agents/skills` only | Register A-09; RedSalamander adopts after CV-2-09 moves its `.github/skills` |
| G6 | References | RedXe's parser (balanced parentheses, reference definitions, footnotes excluded, code spans masked), fragment and query stripped, percent-decoded; the target exists, stays inside the repository, and matches the on-disk spelling case-sensitively | RedXe (stricter) |
| G7 | Reparse points | The root and everything below it, as the engine changelog contract already says; a junction above the root is accepted | Engine contract (`Specs/ProjectCommands.md`), over RedPrism's and RedMonitor's walk to the drive root |
| G8 | Harness files | `agents/openai.yaml` is refused | Register A-11 (default "none"), as RedTilde does |
| G9 | Scoped guidance | `.agents/guidance.json` lists every scoped `AGENTS.md` | RedTilde (stricter); five repositories add the file |
| G10 | Index and pointers | Root `AGENTS.md` links every skill as `(.agents/skills/<name>/SKILL.md)` and nothing else under that path; `CLAUDE.md` and `.github/copilot-instructions.md` exist, have at most six non-empty lines and link `AGENTS.md` | RedHome; DxUi, RedMonitor, RedSalamander fix their index, five repositories their Copilot pointer |
| G11 | PowerShell examples | In `powershell` fences, a `./x.ps1 -Param` line names a script that exists and parses, and only declared, alias or common parameters | RedPrism (stricter) |
| G12 | Plan index | `Specs/Plans/WIP/README.md` names each WIP plan exactly once; `Specs/Plans/Done/README.md` likewise when present | DxUi, RedMonitor, RedHome (majority) |
| G13 | Documentation project | A project of kind `documentation` (RedHome) may link sibling repositories; their existence is checked only when the caller passes `-CheckSiblings` | RedHome (register G-10); the engine schema gains the kind |

Order: engine module, command and shim with the cases of the RedXe, RedPrism, RedTilde, RedMonitor and RedHome suites;
then one adoption pull request per product after its pin wave, each fixing its own content (G4, G9, G10) in the same
change; then the hub moves RedHome to the engine command (CV-6-09). RedMonitor keeps
`Assert-RedMonitorOrdinaryGuidancePath`, which its build tooling also uses, in `Build/Toolchain.psm1`.

## Evidence

- T1 and T2 stage 1: `./Tools/Test-ChangelogWorkflow.ps1 -ScratchRoot <marked sandbox descendant>` on Windows, 33 cases
  passed on 2026-11-18; engine CI on Windows and Linux passed in #87.
- T2 stage 2: the same suite, 37 cases passed on Windows on 2026-11-19.
