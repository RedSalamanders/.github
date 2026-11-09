# Unified CI contract

Policy version: 1. Implementation and hosted acceptance are tracked separately in the organization rollout record.

Organization-owned implementation work is indexed in [Plans/WIP](Plans/WIP/README.md); completed work is indexed in [Plans/Done](Plans/Done/README.md). The canonical [plan lifecycle rule](../AGENTS.md#plan-lifecycle) governs implementation/validation closeout and migration of durable requirements into this contract or the other owning specifications. WIP proposals do not change active CI policy.

## Source and input identity

Every project uses the same strict manifest schema. Explicit runtime/build/test input exceptions precede reviewed prose/folder exclusions. Unknown paths are meaningful. Complete Git comparisons include both rename paths and deleted inputs. Full native input identity hashes the ordered meaningful Git tree entries, manifest and engine pin. It is cumulative; a later documentation commit cannot consume an earlier code obligation.

PR checks never compile, including compiler-dependent tooling fixtures. Classification errors fail the static gate. Formatting drift retains a patch and fails the check. An explicitly dispatched trusted formatter may commit a narrow change to the verified same-repository PR head, then explicitly dispatch fresh compiler-free checks for that exact new head. Because token pushes suppress ordinary workflow events, that dispatch also runs CodeQL with the exact pull-head ref/SHA and dependency review with the verified base/head SHAs. A trusted reporter completes each of the three separately required checks on that source; skipped, failed or cancelled security work cannot pass.

The manual writer accepts only main-targeting PRs, stages literal NUL-delimited paths, and uses a normal fast-forward push. It tolerates bounded lag from the old PR metadata head to its own new commit; another head, closed PR or changed target refuses confirmation. The artifact and publication commands expose each workflow output as a separate key/value line so upload/promotion cannot silently lose its archive path or version.

Native child commands always capture stdout/stderr, including on windowless Windows hosts. Requested console diagnostics forward both captured streams after completion with publication credentials masked; the actual exit code and raw evidence remain intact. Timeouts fail and terminate only the process tree launched by that invocation.

## Admission and persistent state

The cheap main coordinator waits for five continuous quiet minutes. Superseded coordinators may be cancelled. A separate repository/main concurrency lane uses GitHub's bounded queue with cancellation disabled. Stale queued candidates exit admission before any expensive setup; an active native pipeline is never cancelled by newer pushes. Admission rechecks the current head and the trusted main dispatch identity.

Persistent state lives on the project's `ci-state` branch, outside product source. Atomic fast-forward ref updates retain the admitted input identity, commit, engine/policy, run and actual outcome. Concurrent sibling updates fail rather than overwrite. Identical admitted inputs retain their original success, running state or failure; documentation cannot trigger an automatic retry or hide a failure. A retry is explicit. Missing state is conservative and never fabricates qualification.

## Qualification and artifacts

The [immutable dependency SDK storage contract](SDK_Cache.md) defines the new input-only cache foundation.
It does not yet replace any consumer source build or supply a native/test/production verdict.

Admission freezes source, dependency inputs, engine policy, product version and build number. Native x64 and ARM64 Release test builds execute the project's declared normal regression suites against their exact built binaries. Required compiler-dependent tooling is a batch prerequisite. Empty discovery, disabled assertions, stale binaries, timeout, cancellation and unexpected skips fail the gate. Named negative controls must prove active Release failure detection.

Both architecture branches and required prerequisites must pass before either production Release job starts. Production outputs have clean test-disabled identity. Test snapshots remain immutable. Dependency cache reuse requires compatible compiler, SDK, CRT, architecture and dependency inputs; test object reuse cannot contaminate production.

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
