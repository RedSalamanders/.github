# Unified CI contract

Policy version: 1. Status: implementation in progress.

## Source and input identity

Every project uses the same strict manifest schema. Explicit runtime/build/test input exceptions precede reviewed prose/folder exclusions. Unknown paths are meaningful. Complete Git comparisons include both rename paths and deleted inputs. Full native input identity hashes the ordered meaningful Git tree entries, manifest and engine pin. It is cumulative; a later documentation commit cannot consume an earlier code obligation.

PR checks never compile, including compiler-dependent tooling fixtures. Classification errors fail the static gate. Formatting drift retains a patch and fails the check. An explicitly dispatched trusted formatter may commit a narrow change to the verified same-repository PR head, then explicitly dispatch fresh compiler-free checks for that exact new head. Because token pushes suppress ordinary workflow events, that dispatch also runs CodeQL with the exact pull-head ref/SHA and dependency review with the verified base/head SHAs. A trusted reporter completes each of the three separately required checks on that source; skipped, failed or cancelled security work cannot pass.

The manual writer accepts only main-targeting PRs, stages literal NUL-delimited paths, and uses a normal fast-forward push. It tolerates bounded lag from the old PR metadata head to its own new commit; another head, closed PR or changed target refuses confirmation. The artifact and publication commands expose each workflow output as a separate key/value line so upload/promotion cannot silently lose its archive path or version.

## Admission and persistent state

The cheap main coordinator waits for five continuous quiet minutes. Superseded coordinators may be cancelled. A separate repository/main concurrency lane uses GitHub's bounded queue with cancellation disabled. Stale queued candidates exit admission before any expensive setup; an active native pipeline is never cancelled by newer pushes. Admission rechecks the current head and the trusted main dispatch identity.

Persistent state lives on the project's `ci-state` branch, outside product source. Atomic fast-forward ref updates retain the admitted input identity, commit, engine/policy, run and actual outcome. Concurrent sibling updates fail rather than overwrite. Identical admitted inputs retain their original success, running state or failure; documentation cannot trigger an automatic retry or hide a failure. A retry is explicit. Missing state is conservative and never fabricates qualification.

## Qualification and artifacts

Admission freezes source, dependency inputs, engine policy, product version and build number. Native x64 and ARM64 Release test builds execute the project's declared normal regression suites against their exact built binaries. Required compiler-dependent tooling is a batch prerequisite. Empty discovery, disabled assertions, stale binaries, timeout, cancellation and unexpected skips fail the gate. Named negative controls must prove active Release failure detection.

Both architecture branches and required prerequisites must pass before either production Release job starts. Production outputs have clean test-disabled identity. Test snapshots remain immutable. Dependency cache reuse requires compatible compiler, SDK, CRT, architecture and dependency inputs; test object reuse cannot contaminate production.

Native production/package smoke is required on both architectures. Application ZIPs and DxUi SDK ZIPs retain source, profile, version, evidence and SHA-256 manifests. The SDK includes public headers, Release libraries, supported integration, redistributable dependencies and licenses, and must build/run an extracted-SDK consumer without the producer checkout.

## Manual operations and security

Manual extended qualification retains existing Debug/ASan, stress and paired-performance obligations; removing timers does not waive them. The common action offers Normal and Full scope; a project whose normal suite is already Full uses that same canonical suite. RedSalamander's automatic normal suite is CI and its explicit Full remains separate. Paired-performance diagnostic A/A is not qualification. Product release and winget publication require an explicit default-branch action. Publication verifies a successful qualified batch and promotes the exact existing ZIPs without rebuilding or restamping. Missing or expired evidence refuses publication. Retries cannot overwrite an existing asset or create duplicate winget changes.

ZIP publication covers all six products. Winget covers the five applications and requires anonymous installer URLs and a suitable publication credential. Private visibility, account billing and licensed security availability are external acceptance prerequisites, never empty green checks.

Dependency monitoring covers Actions and engine pins, vcpkg baselines/floors and source locks without automatic consumer adoption. Scheduled CodeQL uses explicit C/C++ build mode none. Default and advanced setup must not create duplicate scans. Supported dependency alerts, secret scanning and push protection are enabled consistently; unsupported capabilities stay visibly open.
