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
| T3 | CV-5-03 | `BuildConsole.psm1`, `NativeBuildPolicy.targets` and the Release block, `Get-CiNativeScope.ps1`, `setup-msvc`; fixed-path files written by `Update-ProjectPin.ps1` and checked by conformance | Not started |
| T4 | CV-5-04 | `ScopedTesting.psm1`, `TestRunEvidence.psm1`, `Test-Changes.ps1` with one parameter set: one planner, per-repository suite and path data | Design to be written here before any code |
| T5 | CV-5-05 | One skill grammar and package-integrity policy | Not started |
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
| R5 | A merged, unfolded fragment removed without its entry (a revert or a withdrawal): common and RedSalamander refuse it ("restore it"); DxUi accepts it (its review finding R28-53) | **Owner choice.** Default: refuse, as five repositories do; a revert then keeps the fragment and adds its own | Stricter and the majority; DxUi's own contract would change | DxUi under the default; the other five under the alternative |

R5 is the only difference where both end states are reasonable. The engine keeps the default (refuse) until the
owner answers; DxUi keeps its own copy, and so its withdrawal behavior, until then. If the owner picks the
alternative, the engine change is DxUi's withdrawal block in `Get-ChangelogFoldProblems` and its case, and the
"unfolded removal" case of the other five is dropped.

Stage 2, as implemented in the second pull request: the RedSalamander duplicate case and the DxUi release, reused-branch
and fork-filter cases are in `Tools/Test-ChangelogWorkflow.ps1`, with a new case for R1 (a missing base object); R1 to
R4 are in `Ci.Changelog.psm1` and `Submit-ChangelogFold.ps1`; `Tools/Release-Changelog.ps1` and its shim are new, so
every product adopts five shims. Next: shim `RedSalamander` once its pin includes stage 2; shim `DxUi` once R5 is
decided. DxUi also keeps `Tools/Changelog.psm1` as a module shim for its validators until they import the engine
module. DxUi's PrePush case that refuses an uncommitted tree belongs to its `Test-PrePush.ps1` (T4, register E-04),
not to the changelog suite.

## Evidence

- T1 and T2 stage 1: `./Tools/Test-ChangelogWorkflow.ps1 -ScratchRoot <marked sandbox descendant>` on Windows, 33 cases
  passed on 2026-11-18; engine CI on Windows and Linux passed in #87.
- T2 stage 2: the same suite, 37 cases passed on Windows on 2026-11-19.
