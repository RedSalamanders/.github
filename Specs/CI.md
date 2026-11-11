# Unified CI contract

Policy version: 1. Implementation and hosted acceptance are tracked separately in the organization rollout record.

Candidate producer metadata is acquired by `Tools/Get-CandidateRunEnvelope.ps1` under
[the integration candidate contract](Integration_Candidates.md). It independently
checks the current candidate, original/latest run attempt, trusted caller/engine,
both hosted native jobs and original artifact catalog/digests. This metadata role
leaves downloaded bytes and native evidence unverified. `Get-CandidateNativeResult.ps1`
additionally downloads bounded original archives, verifies their independent server
digests and original input/receipt/profile/canonical-evidence bytes, then reacquires
current producer/candidate/catalog state before publishing a verification record.
Neither command writes a required check, delegates local coverage, adopts a main
result or authorizes production. Hosted acceptance and enforcement remain open.

Trusted shadow admission requires current-head successful cheap CI/security checks
and Root's existing Entire review gate, with original app identities. It rechecks
them before each remote stage and preserves partial journals/refs on refusal. Readiness
metadata supplies no native verdict; integration enforcement and capacity control
remain separate requirements under the candidate contract.

Organization-owned implementation work is indexed in [Plans/WIP](Plans/WIP/README.md); completed work is indexed in [Plans/Done](Plans/Done/README.md). The canonical [plan lifecycle rule](../AGENTS.md#plan-lifecycle) governs implementation/validation closeout and migration of durable requirements into this contract or the other owning specifications. WIP proposals do not change active CI policy.

## Source and input identity

Every project uses the same strict manifest schema. Explicit runtime/build/test input exceptions precede reviewed prose/folder exclusions. Unknown paths are meaningful. Complete Git comparisons include both rename paths and deleted inputs. Full native input identity hashes the ordered meaningful Git tree entries, manifest and engine pin. It is cumulative; a later documentation commit cannot consume an earlier code obligation.

Current adapter conformance refuses extension-wide Markdown exclusions (`**/*.md`, `*.md` and equivalent
unowned wildcard forms). Exclusions must identify owned prose locations or known guides; new implementation,
test data and notice files remain meaningful. Runtime includes still take precedence. Update-ProjectPin.ps1
migrates only the original exact `**/*.md` default to reviewed root guides, Specs Markdown, the test guide and
skill prose while updating the pin/callers. Other custom exclusions remain review-owned. Historical manifest
reads remain supported for original source/artifact verification; a new deployment must pass current conformance.
Pin maintenance requires the exact clean engine, including non-ignored untracked inputs. Only committed
top-level Templates YAML files may become callers; ignored untracked templates cannot add a workflow.

PR checks never compile, including compiler-dependent tooling fixtures. Classification errors fail the static gate. Formatting drift retains a patch and fails the check. An explicitly dispatched trusted formatter may commit a narrow change to the verified same-repository PR head, then explicitly dispatch fresh compiler-free checks for that exact new head. Because token pushes suppress ordinary workflow events, that dispatch also runs CodeQL with the exact pull-head ref/SHA and dependency review with the verified base/head SHAs. A trusted reporter completes each of the three separately required checks on that source; skipped, failed or cancelled security work cannot pass.

DxUi's reviewed compiler-free subset additionally admits Tools/tests/Test-ScopedTesting.ps1. Its Git,
recording-process and fixture-byte controls exercise planning before an expensive native build; they run
with CI_NATIVE_BUILDS_DISABLED and do not compile or establish native acceptance. Simulated local children
isolate their CI markers, while dedicated hosted controls require fresh execution and refuse local baselines.
This command is not admitted for another project's adapter. Compiler-dependent tooling remains in native qualification.

The manual writer accepts only main-targeting PRs, stages literal NUL-delimited paths, and uses a normal fast-forward push. It tolerates bounded lag from the old PR metadata head to its own new commit; another head, closed PR or changed target refuses confirmation. The artifact and publication commands expose each workflow output as a separate key/value line so upload/promotion cannot silently lose its archive path or version.

Native child commands always capture stdout/stderr, including on windowless Windows hosts. Requested console diagnostics forward both captured streams after completion with publication credentials masked; the actual exit code and raw evidence remain intact. Timeouts fail and terminate only the process tree launched by that invocation.

## Admission and persistent state

The manual `integration-branch-capability.yml` diagnostic tests a separate cache-scope
fallback when server-issued read-only cache mode is unavailable. An owner creates one
unique `ci-integration-probe/<32 lowercase hex>` branch at a frozen trusted main commit.
Its read-only-token writer saves synthetic bytes while forging the local default-branch
ref, then positively restores them. A separate dispatch of the same immutable workflow
on main must fail to restore that exact key/path while the independent cache catalog
still records exactly one entry under the isolated branch. Both original reports,
run/attempts, actual refs, source commits and workflow bytes must be authenticated.
Partial observations or missing/failed restores do not prove the pair. The diagnostic
executes no candidate/product code and grants no native, merge, delegation or adoption
authority. A qualified native implementation must separately freeze/recheck its isolated
ref and keep every writer credential and trusted main reporter outside candidate jobs.

The [integration candidate input contract](Integration_Candidates.md) freezes the exact PR/head/base/merge
tree through independent API/Git checks, with a separate strict role for current merge-queue integrations.
These data-only roles do not enable native PR execution or replace
any local/main obligation. Required candidate execution, enforcement and trusted adoption remain undeployed.

The manual integration cache capability diagnostic remains compiler-free. Its unique
synthetic cache-save attempt and retained server-mode/catalog/log evidence do not
supply candidate execution, merge enforcement or delegated coverage. The workflow
linter separately validates the supported literal read/none cache-mode subset before
suppressing only the older linter's exact unknown-key diagnostics; write access is not
introduced by that compatibility path. See the integration candidate contract.

The explicit DxUi-main dependency SDK producer is a separate input-only role governed by
[SDK_Cache.md](SDK_Cache.md#explicit-pinned-native-sdk-producer). It uses reviewed pinned source and
tooling snapshots on native selected architectures, retains every SDK gate and has read-only tokens.
It cannot update main qualification state, qualify a product, run from PR/schedules or publish a release.
Selected architecture retries do not imply omitted architecture coverage. Existing candidate/main gates
and local obligations remain unchanged.

Qualified SDK distribution is enabled only for the three reviewed unchanged source/API
pins and successful producer attempts recorded in the SDK policy. The exact caller and
controller plus all six source/architecture archives are authenticated independently.
Application clients still open the input under actual MSBuild/ABI checks and retain
native regression and production/package gates. An enabled dependency route does not
create a product acceptance result or waive Source fallback on compatibility mismatch.

The cheap main coordinator waits for five continuous quiet minutes. Superseded coordinators may be cancelled. A separate repository/main concurrency lane uses GitHub's bounded queue with cancellation disabled. Stale queued candidates exit admission before any expensive setup; an active native pipeline is never cancelled by newer pushes. Admission rechecks the current head and the trusted main dispatch identity.

Persistent state lives on the project's `ci-state` branch, outside product source. Atomic fast-forward ref updates retain the admitted input identity, commit, engine/policy, run and actual outcome. Concurrent sibling updates fail rather than overwrite. Identical admitted inputs retain their original success, running state or failure; documentation cannot trigger an automatic retry or hide a failure. A retry is explicit. Missing state is conservative and never fabricates qualification.

## Qualification and artifacts

The [immutable dependency SDK storage contract](SDK_Cache.md) defines the new input-only cache foundation.
It does not yet replace any consumer source build or supply a native/test/production verdict.

Admission freezes source, dependency inputs, engine policy, product version and build number. Native x64 and ARM64 Release test builds execute the project's declared normal regression suites against their exact built binaries. Required compiler-dependent tooling is a batch prerequisite. Empty discovery, disabled assertions, stale binaries, timeout, cancellation and unexpected skips fail the gate. Named negative controls must prove active Release failure detection.

New native regression and production receipts additionally retain execution binding
version 1, the frozen engine/product version/build number and the actual producer
run attempt. Publication refuses missing/mismatched frozen producer inputs before
writing a receipt. The strict regression binding reader checks these independently
supplied inputs, complete execution/probe counts, profile artifact references and
original canonical evidence references. Historical receipts retain the legacy reader;
they cannot satisfy the stronger execution binding by adding a self-declared digest.
This metadata contract authenticates no workflow or transported bytes by itself and
does not enable candidate integration, delegation or main adoption.

Both architecture branches and required prerequisites must pass before either production Release job starts. Production outputs have clean test-disabled identity. Test snapshots remain immutable. Dependency cache reuse requires compatible compiler, SDK, CRT, architecture and dependency inputs; test object reuse cannot contaminate production.

DxUi may hand off its Release static library and matching compiler PDB from successful regression to
production within the same workflow run and attempt. The library's compile profile is identical in these
two roles; test executables, objects and verdicts are never imported. Attempt-specific artifact names and
the current-run download preserve the producer boundary. The product adapter recomputes the complete
native v2 source, dependency, evaluated-profile and toolchain identity and verifies every transferred byte.
Missing artifacts or incompatible inputs require a fresh governed source build. Library-only imports revoke
Full/performance build receipts and cannot establish native test acceptance. Both regression architectures
and all extracted-SDK native smoke, symbol isolation, license and header-closure checks remain mandatory.
This same-run handoff does not enable cross-repository SDK consumption or change application production roles.

The normal and explicit diagnostic workflows retain vcpkg's ABI-indexed binary packages in the repository-scoped Actions cache. Exact engine/input keys remain the preferred lookup; a fallback may supply older package archives within the same runner OS, host architecture and target platform. The pinned vcpkg restore still computes each requested package's ABI and installs only the matching entry or builds it. This fallback never restores product objects, SDK build outputs, build receipts or test results, and never changes source/dependency pins. Successful diagnostic qualification may save a newly populated exact cache key; failed qualification does not save it. Cache availability and hits do not change any qualification or production gate. See [vcpkg binary caching](https://learn.microsoft.com/en-us/vcpkg/users/binarycaching).

Native production/package smoke is required on both architectures. Application ZIPs and DxUi SDK ZIPs retain source, profile, version, evidence and SHA-256 manifests. The SDK includes public headers, Release libraries, supported integration, redistributable dependencies and licenses, and must build/run an extracted-SDK consumer without the producer checkout.

Native and manual qualification upload the adapter's evidence directory separately from workspace build logs. An external sandbox and the workspace must never share a multi-path artifact input: their Windows drive-root common ancestor can become a drive-relative path and resolve to the workspace, rejecting sandbox files. Preserve the governed sandbox in place, use one explicit root per artifact, and upload workspace diagnostics even when the adapter fails before emitting an evidence directory. Missing evidence never changes a failed test result to success.

## Manual operations and security

`sdk-artifact-access.yml` is a manual compiler-free capability diagnostic, restricted to trusted main. It uses
only the caller repository's read-only GITHUB_TOKEN to inspect an existing successful DxUi main qualification
and request download authorization for one exact production SDK artifact. It never follows, persists or logs
the signed download URL, downloads SDK contents, creates credentials or grants cache/qualification acceptance.
It retains a credential-free capability record and fails visibly when access is unavailable. Source builds
remain the fallback until distribution and immutable SDK acceptance are implemented. A successful personal-token
lookup does not establish workflow-token access: [GITHUB_TOKEN is repository-scoped](https://docs.github.com/en/actions/concepts/security/github_token),
and [artifact download requires target Actions read access](https://docs.github.com/en/rest/actions/artifacts#download-an-artifact).

Manual extended qualification retains existing Debug/ASan, stress and paired-performance obligations; removing timers does not waive them. The common action offers Normal and Full scope; a project whose normal suite is already Full uses that same canonical suite. RedSalamander's automatic normal suite is CI and its explicit Full remains separate. Paired-performance diagnostic A/A is not qualification. Product release and winget publication require an explicit default-branch action. Publication verifies a successful qualified batch and promotes the exact existing ZIPs without rebuilding or restamping. Missing or expired evidence refuses publication. Retries cannot overwrite an existing asset or create duplicate winget changes.

Manual diagnostic qualification additionally selects All (the compatibility default), x64 or ARM64. A compiler-free
selection job validates that exact value and emits only the selected runner entries; invalid values fail before
checkout or native setup. Single-architecture diagnostic evidence establishes only its recorded scope and never
advances the two-architecture Release/production gate. Project delivery plans may explicitly select x64 runtime
tests and ARM64 compilation while keeping ARM64 runtime claims outside that delivery's acceptance.

ZIP publication and winget cover the five applications. DxUi has no hosted publication workflow, including gallery publication or Prepare; its qualified SDK ZIPs remain internal artifacts. Shared maintenance generates only the five non-publication callers for SDK projects and removes only an unchanged old generated publisher. Both workflow conformance and publication entrypoints refuse SDK publication. Local gallery generation remains available for reviewed documentation changes.

Application winget requires anonymous installer URLs and a suitable publication credential. The owner's 2026-10-31 policy selects the current public organization repositories except DxUi for organization WINGET_TOKEN access. Private applications remain excluded until their separate public transition; reconcile selected access after visibility or repository inventory changes. GitHub Free does not make organization secrets available to private repositories. The five applications retain publication support, while visibility/account restrictions remain acceptance gates.

Organization owners manage the shared secret through GitHub settings. The winget token needs public_repo, not organization-secret administration. Repository-level secrets override the organization secret and may be removed only with explicit owner authorization. RedSalamander's trusted-main promote-publication-credential.yml retains its historical filename but now performs manual read-only verification: authenticate the effective token with GET /user and inspect its declared classic public_repo or repo scope. It never exposes account/token data, writes a secret, checks out code or publishes. Secret-name availability, authentication, declared scope, exercised write permission and actual publication/native installation are distinct evidence states. An existing repository override prevents a check from proving the organization token was used.

Private visibility, account billing and licensed security availability are external acceptance prerequisites, never empty green checks. Closing implementation does not qualify failed or unavailable native runs; the separate hosted-acceptance plan retains those gates.

Dependency monitoring covers Actions and engine pins, vcpkg baselines/floors and source locks without automatic consumer adoption. Scheduled CodeQL uses explicit C/C++ build mode none. Default and advanced setup must not create duplicate scans. Supported dependency alerts, secret scanning and push protection are enabled consistently; unsupported capabilities stay visibly open.

Emergency PR merge eligibility is governed by [Specs/EmergencyMerge.md](EmergencyMerge.md): explicit organization-owner PR-only bypass with a recorded reason and exact-head match. Failed checks remain visible; native qualification and publication evidence gates remain required. This is an operator route and requires no deployed engine-pin change.

The central dependency-status.yml performs a weekly/manual metadata-only inventory of the six exact default-branch trees, engine tags, vcpkg baseline/tool/floor/override declarations and Dependencies source locks. It supplements the individual Actions/vcpkg feeds and the Ghostty observer. Reports retain missing/private coverage and native vulnerability-coverage limitations; an upstream main difference is advisory, never qualified upgrade evidence. No source writes, producer restores or native builds occur. This observer uses the central trusted default branch and does not alter deployed product engine pins.

Generated manifests start with the yaml-language-server schema header for their manifest type and version, because winget validate otherwise exits with a warning code. Windows 11 hosted images provision App Installer without registering it for the runner account, so a missing winget registers that inbox package by family name; nothing is downloaded, and the engine's own hosted check proves resolution on both publication runners. Native qualification records the hosted winget version and accepts only validate's succeeded-with-warnings code (0x8A150028) beside success; any other nonzero owned command fails. Every nonzero owned command prints its captured log, because a failed job uploads no scratch evidence. Native winget qualification reads the exact portable Apps & features identity/version/location directly, because an unpublished package may not correlate with winget list. It refuses pre-existing products/aliases, probes every installed command through its real alias, runs declared bounded product smokeTests, and uninstalls only the exact version in its operation-owned location through the same manifest. Actual cleanup is rechecked. Submission requires matching per-architecture source/run/manifest receipts with every alias/probe count; no list-only or cleanup-incomplete result qualifies. Provider fixtures do not establish a real product install pass.

The branch-cache capability diagnostic uses literal reviewed Linux, Windows x64 and
Windows ARM64 runners, independent platform-suffixed keys and separate original reports.
Qualify the positive isolated-branch and negative main pair on every intended native host;
a Linux-only observation is retained as that narrower scope. Never accept a user-supplied
runner label or let one architecture's cache version substitute for another's proof.

All six project main rulesets require checks / ci-gate, security / codeql and
security / dependency-review from GitHub Actions (integration 15368). The RedPrism
rollout repairs its missing required-status rule while preserving existing review,
merge-method, bypass, strict-update and create semantics. This static policy supplies
no native verdict and does not enable candidate delegation or cross-run adoption.

The accepted I61 scope decision on 2026-11-11 retains current local and main
qualification gates and compiler-free PR checks. Candidate-gate replacement,
automatic shadow admission/reporting, local delegation and candidate-to-main
cross-run adoption are deferred. Optional manual diagnostic tools do not add a
required pre-merge native campaign or authorize reduced coverage. Continue exact
SDK/build reuse, selection and scheduling under the existing acceptance contracts.

Isolated candidate batches retain their original canonical candidate and complete
live controller/run/attempt binding. Native contexts rederive every batch field and
admit only Release test-build/test roles. Pinned SDK preparation supports the bound
isolated test-build role without forging main or authorizing production. This data
binding is a prerequisite described in [Integration candidates](Integration_Candidates.md);
native workflow deployment, authenticated results, required gate enforcement and main
adoption remain unfinished and do not reduce existing local or main coverage.

The optional manual candidate shadow caller uses a precreated unique isolated branch
at exact trusted main, read-only freeze/native jobs and the existing Release test roles.
It retains attempt-bound inputs, original receipts, tested profile bytes and separate
diagnostics. It cannot run production, update qualification state, write a merge check,
save shared caches or cancel another execution. Project rollout and authenticated
hosted shadow acceptance remain open. See Integration_Candidates.md for the full
controller/cache boundary and the further gates required before delegation/adoption.

Operator shadow admission validates a clean exact main checkout, exact reviewed clean
engine, generated callers and independent Git/API workflow bytes, then reacquires the
candidate/main before branch creation and again before dispatch. It records completed
remote stages in append-only request journals. Preview and prose-only cases write no
remote branch/dispatch; an API dispatch acknowledgment is never a native verdict.

Actual native regression, production, manual qualification, SDK producer and installed
publication-smoke jobs share one repository-plus-platform concurrency group. Only the
job holding a native runner owns this lane; coordinators and reusable-workflow callers
must not hold it while waiting for child jobs. Each repository permits one x64 and one
ARM64 native job concurrently across these workflows, bounding the six-product total
to six jobs per architecture. Other GitHub/platform capacity limits still apply.
Lanes never cancel running jobs. They use GitHub's bounded `queue: max` rather than
replacing a previous pending execution. GitHub accepts up to 100 pending entries per
group and cancels further entries when full; this is not an unlimited queue or a
promise that jobs can never be cancelled by the service. See the
[official concurrency contract](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).

An isolated candidate reacquires readiness at workflow freeze, including direct manual
dispatch. After its lane opens and before native setup or cache restore, it revalidates
the original hosted run/attempt binding, clean synthetic merge, canonical current
candidate, isolated trusted-main ref and exact-head readiness twice. A moved head,
base, controller/engine or unsuccessful prerequisite fails before native execution.
Old diagnostic evidence remains; a later request needs fresh acquisition. This guard
supplies no native result, required merge check, local delegation or adoption authority.

The optional manual native reporter runs only trusted current-main engine code on a
compiler-free Linux runner with checks write. It directly authenticates both original
native artifacts and updates only its owned exact-head native check. Candidate jobs
keep read-only tokens. The manual check is not yet required; automatic invalidation,
strict stale-base enforcement and actual hosted reporter acceptance remain separate
gates before local delegation or main adoption. See Integration_Candidates.md.

Local evidence input acquisition uses `Ci.SourceInputs.psm1`'s
`Get-CiPinnedEngineInputsIdentity` before reuse: the selected project's own ordinary
`.ci-engine` must be an independent Git checkout at its exact clean manifest pin.
Its raw current source bytes, including ignored-from-product engine implementation,
enter the checkout-bound key. Missing/moved/dirty/wrong-pin engines refuse; timestamp
or equal-size/backdated edits cannot preserve a prior raw source key. Generated engine
`.build` outputs remain excluded. This supplies input identity, never a test verdict,
SDK acceptance, delegation or main-result adoption. Product adapters must include the
returned identity in each applicable local build/runtime/tooling closure.
Windows root/path casing aliases preserve that same checkout identity; distinct
physical checkout locations remain distinct inputs.
`Get-CiCheckoutContentIdentity` owns the shared ordinal raw path/SHA-256 projection
and fresh no-follow checks; the existing SDK bootstrap name remains a thin
compatibility route with byte-identical results. Keep this implementation centralized.

Owned Windows engine process launches use a fresh private _MSPDBSRV_ENDPOINT_
in their child environment. MSVC descendants inherit that operation's PDB RPC
namespace instead of sharing a user-wide metadata server with another operation.
Nested owned launchers obtain their own namespace. The parent environment and all
compiler/linker flags remain unchanged; no foreign server is stopped or searched
by name. Product contained launchers reuse Set-CiNativeProcessEnvironment at
their actual launch boundary when adopting this policy. This coordination value
is not an ABI/compiler input or reusable receipt identity; the launcher's reviewed
implementation remains in the normal behavioral dependency closure.
The boundary follows [Microsoft BuildXL's MSVC endpoint use](https://github.com/microsoft/BuildXL/blob/main/Public/Sdk/Experimental/Msvc/Native/Tools/Link/Link.dsc).
Environment controls alone do not qualify actual concurrent MSVC lifetimes; retain
separate native acceptance before claiming the observed C1090 failures repaired.

Direct native command callers use Invoke-CiNativeCommand when they need to preserve
live console output and ordinary native exit handling. Its small child bridge accepts
a bounded JSON array of literal string arguments, sets a private metadata endpoint
inside only that child and executes the native application without evaluating command
text. Parent environment/current directory stay unchanged, including concurrent
runspace callers. Native failures keep their exact exit code; compiler-free calls
refuse before launch. The bridge supports up to12000JSON characters and rejects
larger payloads visibly rather than truncating arguments. Existing contained-process
launchers instead apply Set-CiNativeProcessEnvironment to their own ProcessStartInfo.

## Shared local desktop admission

`Ci.DesktopLease.psm1` owns additive admission for operations already classified
`RequiresInteractiveDesktop` or explicitly invoked as interactive. Its
`Invoke-CiInteractiveDesktopOperation` passes noninteractive operations through
without a lock. Interactive admission requires Windows and takes the existing
session-local `Local\RedSalamander.InteractiveTestRun.v1` mutex before invoking the
operation. The unchanged native DxUi lease may then take
`Local\DxUi.InteractiveTestRun.v1`. This order is mandatory; never acquire these
in reverse or add the Root lock inside a child while its parent holds it.

The compatibility name permits current Root runners and updated consumer wrappers
to cooperate without editing a managed dependency pin. Before this bridge, Root
and DxUi-derived consumers used different names and could overlap. Tilde's retained
11 November failure records nine passed child checks but a vanished
`RedSalamander.FindFilesWindow` as its saved foreground/focus target. That failure
remains failed; naming compatibility is an admission repair, not a retroactive pass.

Admission has a finite three-hour failure bound, reports its wait, handles abandoned
ownership explicitly and releases after success or exception. It changes no desktop,
focus, pointer, clipboard or process itself. The original harness still requires its
consent/warning, owned targets, watchdog and verified restoration; no missing/gone
restoration becomes success. Hold this session lock only around the classified
entry, including its applicable repair attempt, never an unrelated build or batch.
Local session admission grants no hosted, native, performance or test verdict.

The engine behavior roster exercises public routing at a recording boundary and
real uniquely named fixture mutexes for separate-process contention, timeout without
entry, nesting, disjoint names, failure release and abandoned recovery. It never
takes a production desktop mutex or performs foreground input for these controls.
