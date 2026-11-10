# Frozen integration candidate inputs

Status: input acquisition implemented; native candidate execution, a required merge gate, delegation and
main-result adoption are not enabled by this contract. Current compiler-free PR and native main policy remains.

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

This foundation does not admit native PR work. A future deployment must define one authoritative event
path, reviewed coverage/version inputs, a bounded capacity policy, stale-base enforcement and authenticated
workflow/result provenance. PR code must retain a read-only PR-scoped execution/cache trust domain; checking
out PR code in a privileged main context is not an acceptable shortcut. Native results and distributable
bytes require separate strict evidence, with main independently verifying equivalence before adoption.
Until those gates are implemented and accepted, preserve every applicable local, main and production obligation.

Source/version/engine/profile/dependency/coverage/byte changes invalidate their affected proofs. Never rewrite
an original candidate receipt to pretend it ran on a later landed commit. Hosting capability gaps keep the
existing obligations active. The organization WIP plan owns unfinished implementation and acceptance.
