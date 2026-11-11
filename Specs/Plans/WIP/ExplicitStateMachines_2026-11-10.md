# I62 Explicit state machines across the shared CI engine and organization tooling

Status: **ACTIVE — plan only; code implementation has not started.**
Priority: P1 integration reliability, developer ergonomics (DX) and agent safety (AX).
Owner: organization CI and tooling owner, coordinated with each project's build/test owner.
Prepared: 2026-11-10.
Planned-at commit: `cd5e327b63d8acd4904f107a8b1b7d177103842d` (`RedSalamanders/.github`).
Scope: `RedSalamanders/.github` shared coordinator, admission, release publication, SDK consumer witness leases, and cross-repository Pattern D state-record convergence with `DxUi`, `RedSalamander`, `RedTilde`, `RedPrism`, `RedXe`, and `RedMonitor`.

- **Owning contracts**: [shared engine guidance](../../../AGENTS.md), [shared CI contract](../../CI.md), [integration candidates contract](../../Integration_Candidates.md), [SDK cache contract](../../SDK_Cache.md), and [emergency merge contract](../../EmergencyMerge.md).
- **Coordinated plans**: [I61 testing and integration acceleration](TestingAndIntegrationAcceleration_2026-11-09.md) owns candidate integration acceleration, ABI-indexed cache reuse, and hosted rollout (`S0`–`S10`). This plan (`I62`) owns explicit discriminated state transitions (`Pattern D`) and three concrete state-tearing repairs (`ISM-26`) inside the shared engine, plus alignment with the six client repositories' sibling `ExplicitStateMachines_2026-11-10.md` plans. Merging or executing an engine slice does not implicitly advance any consumer's `.ci/project.json` pin.

## 1. Inspected snapshot and mandatory pre-execution drift check

| Repository | Planned-at `origin/main` SHA (`2026-11-10`) | Sibling WIP plan | Primary Pattern D scope |
| --- | --- | --- | --- |
| `RedSalamanders/.github` | `cd5e327b63d8acd4904f107a8b1b7d177103842d` | `Specs/Plans/WIP/ExplicitStateMachines_2026-11-10.md` (this file) | `Ci.GitHub.psm1`, `Ci.Candidate.psm1`, `Ci.Publication.psm1`, `Ci.SdkConsumer.psm1` |
| `RedSalamanders/DxUi` | `8af272753cec60a68cbdb3a8b2a7bef0563116ac` | `Specs/Plans/WIP/ExplicitStateMachines_2026-11-10.md` | `Test-Changes.ps1`, `Tools/ScopedTesting.psm1`, `Tools/SdkLibraryInputs.psm1`, `Tools/TestRunEvidence.psm1` |
| `RedSalamanders/RedSalamander` | `99624c5385c6c0d42f8d1c6f8be54cbe69f506ef` | `Specs/Plans/WIP/ExplicitStateMachines_2026-11-10.md` (`I62`) | `ValidationEvidence.psm1`, `ScopedTesting.psm1`, `DxUiDependency.psm1`, `ArtifactOperationLock.psm1` |
| `RedSalamanders/RedTilde` | `98852533ffc09b76c13fbc20884ac1e2a742ee88` | `Specs/Plans/WIP/ExplicitStateMachines_2026-11-10.md` | `Build/ScopedTesting.psm1`, `Build/TestRunEvidence.psm1` |
| `RedSalamanders/RedPrism` | `500eff00cacbeb0a79bdb17b3960552bb000c4dc` | `Specs/Plans/WIP/ExplicitStateMachines_2026-11-10.md` | `Build/ScopedTesting.psm1`, `Build/TestRunEvidence.psm1` |
| `RedSalamanders/RedXe` | `cde3877c88a4fb25cc42014aeee41ac2469f1dac` | `Specs/Plans/WIP/ExplicitStateMachines_2026-11-10.md` | `Build/ScopedTesting.psm1`, `Test-Changes.ps1`, `restore-dxui.ps1`, `Build/DxUiRestore.psm1`, `Build/TestRunEvidence.psm1` |
| `RedSalamanders/RedMonitor` | `77239c80471f7f07ba4801c6081bc08b7d9ae47d` | `Specs/Plans/WIP/ExplicitStateMachines_2026-11-10.md` | `Test-Changes.ps1`, `Build/` |

Before executing any slice in this repository, run these read-only drift checks:

```powershell
git status --short
git rev-parse HEAD
git diff --name-status cd5e327b63d8acd4904f107a8b1b7d177103842d HEAD -- AGENTS.md Specs Tools Templates .github Tests
git diff --cached --name-status
git ls-files --others --exclude-standard
git worktree list --porcelain
```

Reopen every modified module and reconcile line anchors against `I61` changes before editing. Do not force-push, rewrite `refs/heads/ci-state` on live repositories during testing, or bump client `.ci/project.json` pins without an explicit consumer PR.

## 2. Architectural decision — Pattern D discriminated state records

`Get-RSWingetPublicationState` in [Ci.WingetPublication.psm1](../../../Tools/Modules/Ci.WingetPublication.psm1) (lines 278–456) already demonstrates the target organization pattern:

1. **Fold all external observations into one closed discriminated `[pscustomobject]@{ Kind = '...'; ... }` value before executing side effects** (`Kind` in `'Published' | 'Owned' | 'None' | 'Pending' | 'Conflict'`).
2. **Persist authoritative state transitions atomically** before returning from recovery paths so later readers (`publish.yml`, `coordinate.yml`) never observe half-recovered state.
3. **Verify irreversible preconditions before external publication mutations** (for example, checking existing Git tags before flipping a GitHub Release draft live).
4. **Pair every file-backed witness or lease with unconditional `finally` cleanup** and staged sibling temporary paths (`~<guid>` / `.tmp`) moved into place atomically.

Applying Pattern D uniformly across the remaining shared-engine modules resolves all three sub-defects of `ISM-26` while preserving 100% of workflow YAML inputs, job outputs, artifact names, and consumer adapter CLI contracts (`Invoke-ProjectCi.ps1`).

## 3. Source-verified defect ledger and state-machine inventory

### 3.1 Confirmed defects in `RedSalamanders/.github` (`ISM-26`)

| ID | Owning module & function | Current implicit behavior & reachable failure | Target explicit transition |
| --- | --- | --- | --- |
| `ISM-26a` | `Invoke-CiCoordinator` in [Ci.GitHub.psm1](../../../Tools/Modules/Ci.GitHub.psm1) (`L115`–`L136`) vs `Invoke-CiAdmission` (`L138`–`L186`) | When a prior `qualify.yml` run died abnormally while `refs/heads/ci-state` held `outcome = 'running'`, a subsequent prose-only push enters `Invoke-CiCoordinator`, synthesizes a failed outcome in memory (`L121`–`L126`), and exits early on the non-native decision **without calling `Write-CiState`** (unlike `Invoke-CiAdmission` at `L174`). Subsequent `Assert-CiPublicationCurrent` checks in [Ci.Publication.psm1](../../../Tools/Modules/Ci.Publication.psm1) keep seeing stale `outcome = 'running'` on `refs/heads/ci-state`. | Model `ci-state` recovery as an explicit `CiCoordinatorState` (`Idle`, `QuietPending`, `RunningLive`, `RunningAbandonedRecovered`, `Terminal`). Whenever `RunningAbandonedRecovered` is entered, persist the recovered terminal record via `Write-CiState` before evaluating the prose/native branch. |
| `ISM-26b` | `Publish-CiGitHubRelease` in [Ci.Publication.psm1](../../../Tools/Modules/Ci.Publication.psm1) (`L72`–`L125`) | On a resumed draft release, `Publish-CiGitHubRelease` `PATCH`es the GitHub Release from `draft = $true` to `draft = $false` (`L87`–`L109`) *before* verifying whether an existing `refs/tags/$tag` already points at a different commit SHA, allowing GitHub to publish the release against a mismatched pre-existing tag before the SHA assertion runs. | Compute a pure `ReleaseTagPrecheck` (`MissingWillCreate`, `MatchesTargetCommit`, `ConflictWrongCommit`) *before* `PATCH`ing `draft = $false`; throw immediately on `ConflictWrongCommit` while the release is still safely a draft. |
| `ISM-26c` | `Close-CiPinnedSdkInput` in [Ci.SdkConsumer.psm1](../../../Tools/Modules/Ci.SdkConsumer.psm1) (`L256`–`L272`) | `Open-CiPinnedSdkInput` writes a per-lease metadata file under `.build/sdk-leases/<guid>.json` alongside the open `FileShare::Read \| Delete` witness stream, and `Close-CiPinnedSdkInput` disposes `$InputBytes.Witness.Stream` (`L270`) without removing the lease metadata file on clean close, accumulating stale lease records across builds. | Track explicit lease phase (`Open` -> `Closed`) and remove the witness metadata `.json` file inside the `finally` block of `Close-CiPinnedSdkInput` immediately after `$InputBytes.Witness.Stream.Dispose()`. |

### 3.2 Complete 6-module state-machine inventory

| # | Module | Current encoding | Target Pattern D design |
| --- | --- | --- | --- |
| `7.1` | Quiet-window coordinator & dead-run recovery ([Ci.GitHub.psm1](../../../Tools/Modules/Ci.GitHub.psm1), [Invoke-Coordinator.ps1](../../../Tools/Invoke-Coordinator.ps1), [Invoke-Admission.ps1](../../../Tools/Invoke-Admission.ps1)) | `ci-state` JSON (`outcome`: `pending \| running \| passed \| failed`, `headSha`, `runId`, `quietSinceUtc`) with split recovery in coordinator vs admission (`ISM-26a`) | Shared `Resolve-CiPersistedState` helper returning `Kind` (`QuietWaiting`, `LiveRunActive`, `DeadRunRecovered`, `ReadyToAdmit`, `ProseNoOp`) and persisting `DeadRunRecovered` via `Write-CiState` once. |
| `7.2` | Integration candidate freeze & batch completion ([Ci.Candidate.psm1](../../../Tools/Modules/Ci.Candidate.psm1), [Complete-Batch.ps1](../../../Tools/Complete-Batch.ps1)) | Candidate SHA + stage pass booleans (`x64`, `ARM64` Release test gates before production/ZIP) | Explicit `CandidateBatchVerdict` (`Kind` in `'ReadyForProduction' \| 'BlockedFailedGate' \| 'SupersededByHead' \| 'Incomplete'`), checked exhaustively before starting production jobs. |
| `7.3` | GitHub Release draft, asset sync & publication ([Ci.Publication.psm1](../../../Tools/Modules/Ci.Publication.psm1)) | Procedural draft lookup + asset upload + `PATCH draft = $false` before tag verification (`ISM-26b`) | Explicit `GitHubReleaseState` (`Kind` in `'PublishedVerified' \| 'DraftResumable' \| 'Missing' \| 'TagConflict'`) verifying `refs/tags/$tag` target SHA before undrafting. |
| `7.4` | Winget manifest PR state machine ([Ci.WingetPublication.psm1](../../../Tools/Modules/Ci.WingetPublication.psm1)) | Closed `Kind` union (`'Published' \| 'Owned' \| 'None' \| 'Pending' \| 'Conflict'`) | Retain unchanged as the canonical Pattern D reference implementation. |
| `7.5` | Immutable SDK cache & producer promotion ([Ci.SdkCache.psm1](../../../Tools/Modules/Ci.SdkCache.psm1), [Ci.SdkProducer.psm1](../../../Tools/Modules/Ci.SdkProducer.psm1)) | Staged extraction directory -> SHA-256 manifest verification -> atomic directory move | Retain clean staged-promotion state flow; document invariants in [SDK_Cache.md](../../SDK_Cache.md) as the model for client `DxUi` restore scripts. |
| `7.6` | Pinned SDK consumer witness stream & lease ([Ci.SdkConsumer.psm1](../../../Tools/Modules/Ci.SdkConsumer.psm1)) | `$InputBytes.Closed` boolean + open witness stream + uncollected `.build/sdk-leases/<guid>.json` (`ISM-26c`) | Delete `$InputBytes.Witness.MetadataPath` (when present) inside `Close-CiPinnedSdkInput` `finally` after stream disposal; retain failed/abandoned markers only when integrity verification fails if required for diagnostics, or document exact cleanup rules in [SDK_Cache.md](../../SDK_Cache.md). |

### 3.3 Target PowerShell blueprint

```powershell
function Resolve-CiReleaseTagState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)][string] $Tag,
        [Parameter(Mandatory)][string] $ExpectedCommit
    )
    $ref = Invoke-CiApi -Method GET -Path "repos/$Repository/git/ref/tags/$Tag" -AllowNotFound
    if ($null -eq $ref) {
        return [pscustomobject]@{ Kind = 'Missing'; Tag = $Tag; ActualSha = $null }
    }
    $actualSha = [string]$ref.object.sha
    if ($ref.object.type -ceq 'tag') {
        $tagObj = Invoke-CiApi -Method GET -Path "repos/$Repository/git/tags/$actualSha"
        $actualSha = [string]$tagObj.object.sha
    }
    if ($actualSha -ceq $ExpectedCommit) {
        return [pscustomobject]@{ Kind = 'MatchesTargetCommit'; Tag = $Tag; ActualSha = $actualSha }
    }
    return [pscustomobject]@{ Kind = 'ConflictWrongCommit'; Tag = $Tag; ActualSha = $actualSha; ExpectedSha = $ExpectedCommit }
}
```

## 4. Ordered implementation slices

1. **Slice S0 — Reconcile drift and lock behavior fixtures (`Tests/Test-Engine.ps1`, `Tests/Test-SdkCache.ps1`)**:
   - Run the drift checks in Section 1 and inspect any overlap with active `I61` work in [TestingAndIntegrationAcceleration_2026-11-09.md](TestingAndIntegrationAcceleration_2026-11-09.md).
   - Add failing/characterization unit cases in `Tests/Test-Engine.ps1` and `Tests/Test-SdkCache.ps1` covering:
     1. Dead `qualify.yml` run followed by a prose-only push through `Invoke-CiCoordinator`, asserting `Write-CiState` persists the terminal recovery to `refs/heads/ci-state`.
     2. Resumed draft release in `Publish-CiGitHubRelease` when `refs/tags/<tag>` already points at a different commit SHA, asserting failure occurs *before* any `PATCH` sets `draft = $false`.
     3. Clean `Open-CiPinnedSdkInput` / `Close-CiPinnedSdkInput` round-trip, asserting zero leftover `.build/sdk-leases/*.json` files after close while active leases remain protected against eviction.
2. **Slice S1 — Coordinator dead-run recovery persistence & candidate batch verdict (`ISM-26a`, `7.1`, `7.2`)**:
   - Refactor dead-run recovery in [Ci.GitHub.psm1](../../../Tools/Modules/Ci.GitHub.psm1) into one shared transition helper called by both `Invoke-CiCoordinator` and `Invoke-CiAdmission` so `Write-CiState` persists dead-run recovery before prose short-circuiting.
   - Introduce explicit `CandidateBatchVerdict` in [Ci.Candidate.psm1](../../../Tools/Modules/Ci.Candidate.psm1) and [Complete-Batch.ps1](../../../Tools/Complete-Batch.ps1), updating [CI.md](../../CI.md) and [Integration_Candidates.md](../../Integration_Candidates.md).
3. **Slice S2 — Release tag-before-undraft verification (`ISM-26b`, `7.3`)**:
   - Introduce `Resolve-CiReleaseTagState` / `GitHubReleaseState` in [Ci.Publication.psm1](../../../Tools/Modules/Ci.Publication.psm1) and verify tag SHA prior to `PATCH draft = $false`. Update [CI.md](../../CI.md) publication invariants.
4. **Slice S3 — SDK consumer lease metadata cleanup (`ISM-26c`, `7.6`)**:
   - Update `Close-CiPinnedSdkInput` in [Ci.SdkConsumer.psm1](../../../Tools/Modules/Ci.SdkConsumer.psm1) to remove the lease metadata `.json` inside `finally` after disposing the witness stream, and document the witness lifecycle in [SDK_Cache.md](../../SDK_Cache.md).
5. **Slice S4 — Cross-repository Pattern D alignment & opt-in consumer pin bumps**:
   - Coordinate shared Pattern D rules (`prContractClosure` + open-PR `headRefOid` verification, non-zero exit on mid-run file mutation, `Global\` mutexes with `ERROR_SHARING_VIOLATION` retry, staged atomic `.tmp` moves) with the six sibling `ExplicitStateMachines_2026-11-10.md` plans.
   - Only after `RedSalamanders/.github` `main` checks pass, update `.ci/project.json` + `.github/workflows/*.yml` engine pins in each consumer via `Tools/Update-ProjectPin.ps1` in dedicated, explicitly authorized PRs.

## 5. Validation commands and expected outcomes

Run every check below locally (and verify on both `windows-latest` and `ubuntu-24.04` in hosted PR CI) before merging any implementation slice:

```powershell
pwsh -NoProfile -File ./Tools/Test-Workflows.ps1 -Root .
pwsh -NoProfile -File ./Tests/Test-Engine.ps1 -TestRoot (Join-Path ([IO.Path]::GetTempPath()) 'rsci-i62-tests')
pwsh -NoProfile -File ./Tests/Test-DependencyStatus.ps1
pwsh -NoProfile -File ./Tests/Test-SdkCache.ps1 -TestRoot (Join-Path ([IO.Path]::GetTempPath()) 'rsci-i62-sdk')
```

- **Static / syntax gate**: `Test-Workflows.ps1` exits `0` with zero YAML/action/permission mismatches.
- **Behavioral engine gate**: `Test-Engine.ps1`, `Test-DependencyStatus.ps1`, and `Test-SdkCache.ps1` exit `0` on Windows and Linux without touching live GitHub repositories or drive-root folders.
- **Hosted PR gate**: `Shared CI engine` (`dependency-review`, `engine behavior (ubuntu-24.04)`, `engine behavior (windows-latest)`, `hosted winget`) passes green.

## 6. Out-of-scope boundaries, rollback and stop conditions

- **Out of scope**:
  - Changing reusable workflow input/output names in `Templates/*.yml` or breaking older pinned consumers.
  - Modifying consumer `.ci/project.json` pins inside this repository.
  - Altering `I61` candidate-gate admission policy or cache retention thresholds.
  - Creating directories at any drive root.
- **Stop conditions**:
  - Stop immediately if a change to `Ci.GitHub.psm1` or `Ci.Publication.psm1` would alter the wire schema of `refs/heads/ci-state` in a way that older consumer pins cannot read; keep `ci-state` JSON backward-compatible.
  - Stop if `Test-Engine.ps1` or `Test-SdkCache.ps1` exhibits platform-specific file-sharing differences between Linux (`ubuntu-24.04`) and Windows (`windows-latest`) until both platforms pass deterministically.
- **Rollback**: Each slice `S1`–`S3` is an independent pure-PowerShell commit; revert the slice commit if hosted `engine behavior` regresses; consumers remain unaffected while pinned to prior engine SHAs.

## 7. Done criteria and closeout

1. Slices `S0`–`S3` implemented with passing local and hosted Windows + Ubuntu behavioral suites (`Test-Workflows.ps1`, `Test-Engine.ps1`, `Test-DependencyStatus.ps1`, `Test-SdkCache.ps1`).
2. Durable state-transition invariants merged into [CI.md](../../CI.md), [Integration_Candidates.md](../../Integration_Candidates.md), and [SDK_Cache.md](../../SDK_Cache.md).
3. Move this file from `Specs/Plans/WIP/ExplicitStateMachines_2026-11-10.md` to `Specs/Plans/Done/ExplicitStateMachines_2026-11-10.md`, remove its `I62` row from `Specs/Plans/WIP/README.md`, and add its completed record to [Done/README.md](../Done/README.md).
