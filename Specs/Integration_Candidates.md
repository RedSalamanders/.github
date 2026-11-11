# Frozen integration candidate inputs

Status: input acquisition, manual native shadow execution and independent native-result
verification are implemented. Hosted shadow/verifier acceptance, a required merge gate,
delegation and main-result adoption remain open.
Current compiler-free PR and native main obligations remain.

## Independent producer metadata acquisition

`Tools/Get-CandidateRunEnvelope.ps1` reacquires the current canonical candidate and
requires the independently supplied candidate identity, original isolated nonce, run
and attempt. It authenticates both the original attempt and the current run through
separate GitHub GET requests. Both must retain the exact successful manual event,
trusted-main commit, isolated branch, repository/head repository, caller and reviewed
reusable engine. Caller bytes agree with the independently fetched Git object.

The complete job catalog must contain the successful freeze plus both declared
GitHub-hosted native architecture jobs. Their original build, regression/assertion
probe and profile-retention steps must have succeeded. The complete artifact catalog
must retain exactly one original attempt-qualified inputs, regression, profile and
workspace-evidence artifact per declared role. Optional sandbox-evidence artifacts
retain their own root. Expired, duplicate, foreign, truncated, stale or digest-less
metadata refuses. Original server archive digests and sizes are retained.

Expected input JSON is reconstructed from the independently acquired candidate and
producer context. Reacquisition at the end refuses a changed candidate/main or a new
producer attempt. The command performs no remote writes and executes no product
code. `CandidateRunArtifactEnvelope` explicitly leaves artifact bytes and native
results unverified and supplies no verdict. Downloaded input/receipt JSON, tested
profile bytes and canonical evidence still need independent bounded archive/hash
verification. Metadata authentication alone must never enable a required merge check,
local delegation, qualification-state update, production or main adoption.

## Original artifact and native-result verification

`Tools/Get-CandidateNativeResult.ps1` acquires the metadata envelope above, downloads
the original attempt-qualified artifact ZIPs and retains them in a new unique evidence
directory. API credentials go only to GitHub; the signed storage URL uses a separate
client without those headers. Streaming transport refuses excess/truncated bytes and
requires the original server SHA-256 and size. The same transport primitive is reused
by existing SDK downloads, whose source/ABI/import contracts remain separate.

Candidate archives are held read-only, bounded by catalog count, compressed/expanded
size and per-entry streaming limits. Unsafe/duplicate/case-colliding paths, links,
special files, ambiguous Windows names and duplicate JSON properties refuse before
data is accepted. The verifier never extracts files, runs candidate code, imports
downloaded scripts or restores candidate caches. Native profile and diagnostic archive
reading is deliberately separate from dependency-store initialization and SDK import.

Both original input JSON files must equal independently reconstructed producer inputs.
Each architecture retains exactly one bound regression receipt, successful Release
execution and assertion probe, the complete matching exe/dll/lib profile, and every
original canonical evidence reference with matching bytes. Hosted workspace paths map
only from the declared project's Windows runner workspace; Root sandbox references map
only from the governed RedSalamander.Perf/evidence root into its separate archive.
Missing, extra, changed, cross-profile or unbound inputs refuse. Original receipts are
never rewritten for another run, commit or version.

After transfer, the verifier reacquires current candidate/main, latest producer attempt
and complete server catalog. A changed value refuses before `verified-result.json`
publication. Partial downloads, original envelopes and failed diagnostics remain for
investigation. Local Root evidence uses the existing marked sandbox; sibling local
projects may use their own .build; hosted output remains beneath real RUNNER_TEMP.
`AuthenticatedCandidateNativeResult` records the independently verified original
execution and bytes. It explicitly authorizes no merge, local delegation, main adoption
or production. A later controller must perform its own live verification; reading a
self-declared saved JSON record never recreates authentication. Actual hosted positive
and negative acceptance plus the required-check reporter/enforcement remain open.

`Tools/Get-IntegrationCandidate.ps1 -Root <project checkout> -PullRequest <number>` acquires one exact
open, non-draft, mergeable main-targeting PR. It uses the existing repository-read `GH_TOKEN`, GET requests,
and the checkout's exact reviewed GitHub origin. It imports no product code and runs no build or test.
Unknown mergeability, malformed metadata, another repository/base and stale API or Git identities refuse.

The controller must be committed and clean, including non-ignored untracked files. It reads current PR and
main identities, fetches main/head/synthetic-merge into a unique `refs/ci/candidates/<PR>/<guid>/` namespace,
and verifies each fetched commit against the independent API snapshot. The current REST PR payload has no
merge commit field; acquisition reads `git/ref/pull/<number>/merge` independently before and after the fetch.
GitHub's pull merge ref is the source
of the synthetic integration. Its actual ordered parents must be exactly current main then PR head; its
complete tree, meaningful native input digest, adapter/engine policy and Git-count version are frozen.
Local working/index bytes cannot replace the committed integration. Input discovery uses the existing
complete Git-tree contract, including unknown paths, deletions, runtime exceptions and policy/engine bytes.

The API and main ref are read again after acquisition. Rechecking a stored descriptor reconstructs all
data and compares it with the supplied descriptor. The expected controller commit is supplied independently,
never taken from the descriptor under verification. Altering a field and recomputing its self-declared digest
does not authenticate that field. Commit, tree, native-input and controller identities have distinct roles.

`Schemas/integration-candidate-inputs.schema.json` defines the strict `IntegrationCandidateInputs` role.
It has no execution, pass, qualification, publication or adoption fields. `nativeRequired=false` means only
that this proposed integration introduces no new meaningful native inputs; it supplies no baseline success
and cannot hide a retained failed/running/missing outcome. The version is a proposed input, not a reservation
or evidence that any binary was stamped with it.

The command prints JSON and retains its unique fetched refs, including failed acquisitions, for diagnosis.
It does not alter working files, the index, user branches, CI state, merge settings or credentials. Callers
choose an owned output location when retaining stdout. Ref cleanup requires its own ownership/preservation
review; this command never deletes historical refs or evidence.

## Merge queue input acquisition

`Tools/Get-MergeGroupInputs.ps1 -Root <checkout> -EventPath <event.json>` freezes a
`merge_group` / `checks_requested` event targeting main. The event is untrusted data;
it must agree with independently read current-main and exact queue-ref API identities,
then separately fetched Git objects, before and after acquisition. The controller must
remain clean at the same committed revision throughout. A stale/deleted/replaced queue
ref, advanced main, unrelated Git history or mismatched manifest refuses.

The complete queue integration must descend from current main. Its exact commit/tree,
meaningful inputs, engine and proposed Git-count version are recorded under strict
`Schemas/merge-group-inputs.schema.json`, role `MergeGroupInputs`. Batched synthetic
integrations are supported; no single-PR parent topology is assumed. The queue-ref suffix
is opaque: this role makes no PR-membership, workflow-authentication or execution claim.
Prose-only identity equality grants no baseline success or adopted verdict.

Acquisition imports no product code, performs only GET requests and retains its unique
`refs/ci/merge-groups/<guid>/` diagnostic refs without changing user branches or worktrees.
This command neither installs a merge queue nor enables native execution or delegation.
The future authoritative workflow must additionally authenticate its event/workflow,
enforce queue/branch policy and coverage, and authenticate result/artifact provenance.
GitHub's documented [merge queue event](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#merge_group)
is distinct from per-PR feedback; required checks must also run on that event before queue enforcement.

## Required continuation before changing obligations

`Ci.Execution.psm1` defines the additional native execution input binding. New
regression/production writers retain the frozen engine, version/build number and
actual run attempt. `Test-CiRegressionExecutionBinding` requires an independently
frozen descriptor and expected producer run/attempt, completed ordinary Release
execution and failure probe, unique profile artifacts and nonempty original evidence
references. Missing, mistyped, stale, duplicated and out-of-profile data refuse.
Historical receipt reading remains available, with no upgrade into this stronger
contract. The module does not acquire/authenticate workflows, verify downloaded
artifact/evidence bytes or make a merge/adoption decision; those remain controller
and transport obligations before candidate activation.

The manual shared `integration-capabilities.yml` is a compiler-free diagnostic for the
server-issued read-only cache mode. It saves only a unique synthetic fixture, deliberately
forges the local mode environment, checks the repository cache catalog independently,
and retains the original save-step log/report. A reported read mode and missing entry
alone do not distinguish permission denial from a service/network failure: inspect the
raw save-step result before accepting the boundary. It creates no native or merge verdict.
Mode observation writes a partial non-confirming report before refusal, including when
the mode is missing. A skipped save cannot confirm the boundary. Evidence retention
must still run for these early failures.
The pinned older workflow linter admits only literal block-mapping `cache-mode: read`
or `none` at workflow/job scope through the shared validator; write, dynamic, inline,
duplicate and misplaced forms refuse. Only its two exact obsolete unknown-key messages
are suppressed; ordinary syntax checks remain active.

GitHub documents [token-enforced cache modes](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#controlling-cache-access-with-cache-mode).
Candidate execution must verify this capability before any default-branch dispatch
executes candidate code. Omitting cache-save steps alone does not establish isolation.
Read-only execution tokens and a separately privileged trusted reporter remain required.
GitHub also documents that [manual workflow-job checks do not satisfy PR-required checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks#checks-from-some-workflow-jobs-are-not-evaluated).
The deployed reporter and branch/ruleset enforcement therefore need actual positive and
stale-base/failed/missing/cancelled negative acceptance before relocating local coverage.

This foundation does not admit native PR work. A future deployment must define one authoritative event
path, reviewed coverage/version inputs, a bounded capacity policy, stale-base enforcement and authenticated
workflow/result provenance. PR code must retain a read-only PR-scoped execution/cache trust domain; checking
out PR code in a privileged main context is not an acceptable shortcut. Native results and distributable
bytes require separate strict evidence, with main independently verifying equivalence before adoption.
Until those gates are implemented and accepted, preserve every applicable local, main and production obligation.

Source/version/engine/profile/dependency/coverage/byte changes invalidate their affected proofs. Never rewrite
an original candidate receipt to pretend it ran on a later landed commit. Hosting capability gaps keep the
existing obligations active. The organization WIP plan owns unfinished implementation and acceptance.

## Isolated manual execution input reacquisition

Get-CandidateExecutionInputs.ps1 is an input-only seam for the future trusted manual
integration-execution caller. It requires the exact hosted workflow_dispatch context,
same repository, actual run/attempt and ci-native/pr<PR>/<candidate identity>/<nonce>
branch at the frozen trusted main commit. A clean default-branch controller reacquires
the complete candidate using the canonical public acquisition twice, independently
checks its isolated ref before/after, verifies the caller blob through both API and
Git objects and refuses advanced main or changed candidate data. Fork/foreign heads,
candidate engine changes and a mismatched native batch/version are inadmissible.

CandidateExecutionInputs carries the original canonical candidate plus native batch
inputs bound to the actual producer run. It explicitly records nativeExecutions zero
and suppliesNativeVerdict false. It writes no remote branch, output file, check or
qualification state, imports no product code and executes no native work. The supplied
JSON identity and this input acquisition do not authenticate a test result. Manual
native execution and independent verification use the separate commands above;
hosted acceptance, exact-head reporting, required-check/stale-base enforcement and
main adoption remain separate requirements.

Its native batch retains a `CandidateExecutionBinding`: the original canonical
candidate, complete controller context, caller blob and isolation nonce. Native project
contexts rederive this batch against the live hosted repository, event, branch, controller
commit, workflow ref, run and attempt. Missing, extra, mistyped or changed fields refuse.
The binding admits only `ReleaseTestBuild` and `ReleaseTest`; isolated production and
extended qualification roles refuse. SDK preparation can read pinned inputs for the
bound isolated test-build role, using its real isolated ref. It never emulates main,
permits isolated production or supplies a native verdict. Existing hosted main SDK
preparation retains its own guards. These adapter prerequisites do not deploy a native
workflow, grant check-writing authority or change any validation obligation.

The isolated-branch cache prerequisite passed its original positive branch restore
and independent main miss on Linux, Windows x64 and Windows ARM64, attempts 42886607587
and 42887031360. The authenticated pair is retained in TestRuns/I61_2026-11-09.
This establishes that observed service-scope boundary only. Native execution must keep
its read-only credentials and unique ref; its trusted reporter must never execute
candidate content or restore candidate caches.

## Manual native shadow workflow

The generated `integration-execution.yml` caller accepts only manual dispatch inputs
`pull_request`, canonical `identity` and unique `nonce`. An operator must first create
`ci-native/pr<PR>/<identity>/<nonce>` at the exact trusted current main commit. This
workflow does not create or move that ref. Dispatch through main or a branch pointing
at candidate content refuses before native setup. Reacquisition independently verifies
the main/PR/merge/ref/caller/controller identities under the input contract above.

A read-only Linux job checks out the controller and retains original attempt-qualified
candidate and batch JSON. Native x64 and ARM64 jobs then check out the frozen synthetic
merge, use the reviewed exact engine and execute the existing ReleaseTestBuild and
ReleaseTest adapters. Different profile, platform and role obligations remain distinct.
Prose-only input acquisition starts no native job and grants no baseline success.
Jobs retain read-only repository/Actions credentials, no publication credentials,
isolated branch cache scope, no cache saves and a read-only vcpkg binary-cache source.
Omitting save steps is not the isolation proof: the independently observed branch
service boundary and exact controller context remain prerequisites.

Successful jobs retain their original receipts and tested exe/dll/lib profile bytes;
canonical sandbox evidence and workspace diagnostics retain separate roots, including
on failure. Artifact names include the actual run attempt. No production/package,
required-check writer, main qualification-state update, merge or adoption runs here.
The source-adapter binding still independently rejects any isolated production role.
The caller never cancels an active execution. Original evidence from superseded inputs
remains diagnostic and must not authorize another candidate.

This remains shadow execution until the independent verifier passes actual hosted
acceptance and exact-head reporting plus required-check/stale-base enforcement are
implemented and qualified. Existing local and main coverage remains active. Project
caller rollout is implemented in four projects; Root and Xe plus actual hosted shadow
acceptance remain open. Successful script/structural controls do not establish them.

`Tools/Start-CandidateShadow.ps1` provides operator admission for a clean exact current
main checkout and its exact clean reviewed engine. Supply an independently acquired
candidate identity. Conformance and independent Git/API caller bytes are checked before
any remote write. The command reacquires the complete candidate and main before creating
one unique isolated branch at main, then reacquires candidate/main/ref again before
requesting dispatch. It never updates an existing branch, executes product code, creates
a check, updates qualification state, merges or cancels a run. Prose-only input returns
`NoNativeRequired` without a remote write and without granting baseline success.

The append-only `.build/ci/candidate-requests/<nonce>/` journal separately records frozen
inputs, confirmed ref creation and confirmed dispatch requests. A failed request retains
its original journal/ref; there is no destructive rollback or retry over an old request.
`DispatchRequested` means only that GitHub accepted a request, not that a run began or
passed. Authenticate the actual original run/attempt/jobs/artifacts separately. `-WhatIf`
performs normal read/fetch reacquisition (retaining diagnostic local Git refs) but creates
no journal, remote ref or dispatch. Operator credentials remain in the trusted command;
the candidate workflow still receives only its own read-only token.

Native admission additionally requires the exact head's successful `checks / ci-gate`,
`security / codeql` and `security / dependency-review` checks from GitHub Actions app
15368. RedSalamander retains its existing `Entire Gates` review prerequisite from
Entire app 2626939. These IDs were independently inspected on the actual check
catalog; a same-name check from another app does not substitute. Missing, duplicated,
truncated, pending, failed, cancelled, neutral, skipped or wrong-head prerequisites
refuse. A pending native integration check is a separate obligation and must not
deadlock the admission needed to run it.

The trusted controller reads the complete original check catalog before journaling,
rechecks readiness immediately before ref creation and rechecks again before dispatch.
The frozen journal retains the original successful check IDs/apps/head. Readiness
moving back to pending prevents the next remote write while preserving any earlier
ref/journal. Prose-only acquisition still supplies no baseline success. These cheap
prerequisites avoid starting an expensive native campaign for an unready head; they
provide no native pass, required native gate, capacity lease or merge authority.

Workflow freeze also reads these readiness prerequisites before publishing frozen
inputs, so directly dispatching the manual workflow cannot bypass operator readiness.
Native jobs wait in the shared repository/platform lane described in CI.md. Once a
lane opens, `Assert-CiCandidateNativeStart` validates the original live execution batch
and exact clean synthetic merge, then twice reacquires the complete canonical candidate,
isolated ref and original required check catalog. These reads occur before native setup
or any dependency cache restore. Changed inputs or readiness fail visibly without
executing native code. The return value is input-only and authorizes no merge or reuse.

## Optional trusted manual native reporter

`integration-report.yml` is a separate manual trusted-main metadata job. Its narrow
checks-write token never reaches candidate execution. `Publish-CandidateCheck.ps1`
requires exact clean current main/engine, independently checks the actual reporter
run/attempt/repository/caller/reusable-engine reference, and reacquires the current
native candidate plus exact-head prerequisites. Branch, PR-event, dirty or stale
controllers refuse before check writes. Prose-only input supplies no baseline pass.

The reporter owns `native / candidate-integration` on that exact head, sets it pending
before verification, and directly invokes the original byte verifier. A saved result
file is never an input. It rechecks candidate, prerequisites, current original producer
and artifact catalog before success publication. Missing/failed/cancelled evidence,
changed attempts, catalog or source produce failure. An existing successful owned
report is cleared before another verification; unrelated or ambiguous same-name checks
refuse. Ownership is rechecked before completion so an older report cannot overwrite
a newer owner. Original artifacts remain data and are never extracted or executed.

This manual report is optional and is not installed as a required branch check.
It does not automatically invalidate reports when a producer rerun starts, enforce
strict stale-base merge rules, delegate local tests, adopt main results or authorize
production. Actual hosted positive/failure acceptance, automatic admission/report
invalidation and branch-policy enforcement remain required before any coverage moves.
