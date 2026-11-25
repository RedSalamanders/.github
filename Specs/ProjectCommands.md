# Engine-implemented project commands

Policy version: 1. Status: normative for every command listed below.

Some product commands exist once, here, and every product runs the same implementation from its pinned engine. The
product keeps a file with the command's name and parameters (a shim) so that its scripts, documentation and habits do
not change; the shim only binds to the engine. This is how the RedSalamanders convergence plan removes the forked
copies of shared tooling (RedHome `Specs/Plans/WIP/Convergence_2026-11-17.md`, Phase 5).

## Shim contract

- The shim's text is [Templates/Project](../Templates/Project)`/<path>`, the same in every product apart from line
  endings. A product adopts a command by copying the template from its pinned engine; it never edits the copy.
- The shim's product root is its own folder when that holds `.ci/project.json`, otherwise the folder above it (a
  shim under `Tools/`); a root shim (such as `Test-Changes.ps1`) uses only its own folder. A copy in a nested fixture
  never binds to an outer product. The shim imports
  `Tools/Modules/Ci.EngineBinding.psm1` from that product's `.ci-engine`, and runs the path that
  `Resolve-CiPinnedEngineCommand` returns: `Tools/<shim file name>` of that engine.
- A module shim (a `.psm1` such as `Build/BuildConsole.psm1`) finds its product root in its own folder or up to three
  levels above it, never past a folder that holds `.git`, so a nested fixture copy still refuses. It imports the
  module that `Resolve-CiPinnedEngineModule` returns, `Tools/Modules/Ci.<shim file name>`, into its own scope and
  exports exactly that module's functions, so `Import-Module <product path>` gives callers the same commands as before.
- It fails closed with one message that names the pin and the commands that fix it, when `.ci-engine` is missing,
  predates the binding module, is not a Git checkout of its own, is at another commit than `engine.ref`, or has
  changes to tracked files. This is the rule the project adapter already applies to the static CI phase.
- A parameter whose default names the product (such as `-Root`, the repository containing the command) is resolved
  by the shim and passed explicitly; every other bound parameter, including `-WhatIf`, is passed unchanged. The engine
  command makes such a parameter mandatory, so it can also be run directly: `./.ci-engine/Tools/<name> -Root .`.
- A product sees a new engine command, or a change to one, only through its pin (`Tools/Update-ProjectPin.ps1`),
  and adopts a new shim in one pull request that replaces its copy. Every shim carries one marker line
  (`Get-CiProjectShimMarker`); the pin update rewrites each file that carries it to the new pin's template, so a
  template change reaches every product in its pin update, and never adds a shim or replaces a file without the
  marker. The static CI phase (`Test-CiProjectConfiguration`) refuses an adopted shim that differs from its pinned
  template, apart from line endings. The engine never reaches into a product checkout other than the one a caller
  names.

## Commands

| Product command | Engine implementation | Tests |
| --- | --- | --- |
| `Tools/Test-Changelog.ps1` | `Tools/Test-Changelog.ps1`, `Tools/Modules/Ci.Changelog.psm1` | `Tools/Test-ChangelogWorkflow.ps1` |
| `Tools/Fold-Changelog.ps1` | `Tools/Fold-Changelog.ps1` | same |
| `Tools/Submit-ChangelogFold.ps1` | `Tools/Submit-ChangelogFold.ps1` | same |
| `Tools/Release-Changelog.ps1` | `Tools/Release-Changelog.ps1` | same |
| `Tools/Test-ChangelogWorkflow.ps1` | `Tools/Test-ChangelogWorkflow.ps1` | engine CI, and each product's tooling tests through its shim |
| `Build/BuildConsole.psm1` (module shim) | `Tools/Modules/Ci.BuildConsole.psm1` | `Tests/Test-ProjectModules.ps1`, and each product's own build-console tests through its shim |
| `Tools/Test-AgentGuidance.ps1` | `Tools/Test-AgentGuidance.ps1`, `Tools/Modules/Ci.AgentGuidance.psm1` | `Tests/Test-AgentGuidance.ps1` |
| `Test-Changes.ps1` (root shim) | `Tools/Test-Changes.ps1` with `Tools/Invoke-ScopedScript.ps1`, data `Tests/test-scopes.json` ([schema](../Schemas/test-scopes.schema.json)) | `Tests/Test-ScopedTesting.ps1` |
| `Build/ScopedTesting.psm1` (module shim) | `Tools/Modules/Ci.ScopedTesting.psm1` | same |
| `Build/TestRunEvidence.psm1` (module shim) | `Tools/Modules/Ci.TestRunEvidence.psm1` | same (Windows) |

The build-console module rejects warning and error diagnostics, including structured native tool failures.
Build callers with an explicit MSBuild summary use `-RequireBuildSummary` for assertion and result output.
That mode requires the successful footer, both zero counts and the elapsed time at the end of the log.
`Get-NativeBuildDiagnostics -IncludeBuildSummary` exposes those observations and at most 16 bounded diagnostic lines.
Existing callers keep their diagnostic result fields and zero-warning behavior while they adopt the explicit logger summary.

## Managed formatting files

The engine publishes the common `.clang-format` and `.editorconfig` in
[Templates/ManagedProjectFiles](../Templates/ManagedProjectFiles). A pin update writes both at the
root of an application or SDK checkout when they are missing or differ. The compiler-free project
check requires both to match the engine pin, allowing the checkout's line endings. Identical files
keep their timestamps.

The same pin operation owns the marked common blocks in `.gitattributes` and `.gitignore`. A new file starts with its shared block. An existing file needs one ordered pair of common block markers.
A pin updates only the marked lines and retains the surrounding product-specific rules and checkout line endings.
Compiler-free conformance verifies the marked content. Git does not renormalize tracked inputs during a pin update.

## Shared native toolchain helpers

A product selects the MSBuild installation according to its build contract. The shared
`Ci.VisualStudio.psm1` provides prerelease-aware discovery with an optional version range,
the VS installation of an explicitly selected MSBuild and the native x64 or ARM64 MSBuild
path. A missing native host executable fails discovery. `Get-CiDefaultMsvcToolset` reads
the selected installation's MSVC default file and returns its full and major.minor versions.
The selected MSBuild installation and default toolset also supply the vcpkg overlay pins.

`Ci.VcpkgTriplet.psm1` appends the Visual Studio and toolset pins, preserving the source
triplet's text and line endings. The product supplies its existing generated comment so
that equivalent adoption preserves overlay bytes and vcpkg package identities. The
output belongs below the product's `.build/`. Stock and sanitizer inputs can name
companion files beside themselves. The writer validates and reads all referenced input
files first, copies the companion bytes, then publishes the overlay through a
same-directory replacement. An unchanged file retains its timestamp. When a product
uses restore leases, the lease covers triplet publication and installation for that profile.

Product `vcpkg-install.ps1` entry points keep their platform defaults, supported parameters
and tool and registry locks. `Ci.VcpkgInstall.psm1` constructs the manifest install
arguments with project-contained manifests and overlay, registry and output paths below
`.build/`. Products supply their existing target triplet, registry and cache policy.
The common checkout helper restores the declared full Git pin under `.build/`. It
stages new checkouts at a short path under the build root, publishes after verification,
refuses local changes and foreign origins,
and completes older shallow or partial clones under their existing checkout.
The Windows bootstrap helper verifies the tool commit, retains the product's plain
commit marker and reuses a matching executable. It invalidates the marker before
an actual bootstrap and writes it only after a successful operation produces the file.
A failed bootstrap leaves the next attempt eligible for repair. Product restore policy
owns architectures, sanitizer triplets, output roots and old consumer interfaces. The engine
already owns `Install-CiFormatter` in `Ci.Format.psm1` and its reviewed formatter pin.

## Changes workflow

Each change records one UTF-8 Markdown file `Changes/<yyyy-mm-dd>-<topic>.md` (a real calendar date, a topic in
lowercase letters, digits and hyphens) holding one top-level `- ` bullet whose other lines are indented. A change keeps
its fragment and never edits `CHANGELOG.md`; fragments are folded on the default branch after merge.

- `Test-Changelog.ps1` is read-only. It rejects invalid names, dates and bullets, unexpected entries under `Changes/`,
  reparse paths inside the repository, invalid UTF-8 (only a UTF-8 byte order mark is accepted), a missing
  `Changes/README.md`, and a missing or duplicate `## Unreleased` heading. With `-Base <ref>` it compares the checkout
  with its merge base with that ref: fragments may be added, edited or renamed, and `CHANGELOG.md` must equal the
  exact fold of the fragments that the merge base holds and the checkout no longer has. Hand edits, entries folded from
  fragments the same change adds, edited, removed, reordered or duplicated entries, a merged fragment removed without
  its entry, and any change outside the Unreleased entries are refused, except the exact generated release transition
  below and one header change: everything before `## Unreleased` may become the shared header (`# Changelog`, a blank
  line, `Entries are generated from [Changes](Changes/README.md). Existing release notes remain in their original
  locations.`, a blank line), never move away from it; line endings never count. Only a base without `CHANGELOG.md` (before adoption) skips the comparison; any other
  Git failure, such as a missing object, is refused. `-RequireFolded` also rejects any pending fragment.
- `Fold-Changelog.ps1` validates everything before writing, inserts entries under Unreleased newest file name first,
  keeps the changelog's byte order mark and line endings, publishes a flushed staged file atomically, then removes only
  the folded fragments. A checkout-local lease serializes folds; a rerun after an interrupted cleanup finishes it
  without duplicating entries and names each fragment it skips in a warning. Two pending fragments with the same new
  text are refused before anything is written, since one entry would stand for two changes. `-WhatIf` previews;
  `-Check` is the read-only check of a finished fold.
- `Submit-ChangelogFold.ps1` fetches the default branch, folds it with this engine's commands in a temporary worktree
  outside the caller's checkout (under `-WorktreeParent`), verifies the exact fold, commits with the repository's own
  identity, signing and hooks, pushes `changelog/fold-<commit>` and opens its pull request with `gh` (`-PushOnly`
  leaves that to the caller). It removes only the worktrees it created. A fold branch already pushed for the same
  commit is reused only when it is one commit on that default branch changing nothing but `CHANGELOG.md` and
  `Changes/*.md`, passes the exact-fold check, and equals a fresh fold. An open fold pull request of this repository (a
  fork's is ignored) is reported instead of opening a second one. `-WhatIf` never pushes or writes to GitHub. Hosted
  workflows never fold.
- `Release-Changelog.ps1 -Version <semver> -Date <yyyy-mm-dd>` is a separate release-only change after every fragment
  is folded on the base. It atomically moves all Unreleased entries under one new `## <version> - <date>` heading,
  leaves an empty Unreleased section and keeps the history; it refuses an invalid version or date, an existing
  version, pending fragments and an empty Unreleased section. `-WhatIf` is read-only.
- None of them builds native code, takes desktop focus, or stages, commits or pushes outside the submission.

Products run `Test-Changelog.ps1` while editing, with `-Base origin/main` in PrePush, and in the compiler-free PR
checks, where `pr.yml` passes the pull request's immutable base SHA to the adapter's static phase, which runs it with
`-Base <base SHA>`. Main pushes go through the quiet-window coordinator and run no separate changelog comparison. This one implementation joins the three product variants that
existed before the move (see [the tooling plan](Plans/WIP/SharedProjectTooling_2026-11-18.md), stage 2). R5 requires a revert to keep the original pending fragment and add a new one. Removing a merged, unfolded fragment without
publishing its entry is refused.

## Agent guidance

`Test-AgentGuidance.ps1 -Root <repository> [-Kind Product|Documentation] [-CheckSiblings]` is read-only and runs no
referenced script. It reports every problem at once, one `<path>[:<line>]: <problem> (<rule>)` per line after
`Agent guidance validation failed:`, and otherwise prints `Agent guidance valid: <n> skills, <m> references.` Products run
it from `validate-skills.ps1`; RedHome runs it with `-Kind Documentation`. `Ci.AgentGuidance.psm1` also exports
`Get-CiSkillProblem -FolderName -Text` (the problems of one `SKILL.md` text as one string, or `$null`) and
`Get-CiAgentGuidanceProblems` (every problem as a string array; never throws for a content problem). The rules, whose
origins the [tooling plan](Plans/WIP/SharedProjectTooling_2026-11-18.md) (T5) records:

- G1 Front matter: `SKILL.md` starts at byte 0 with `---` front matter of the keys `name`, `description`, `license`,
  `allowed-tools` and one-level `metadata`, with quoted, literal and folded scalars. YAML 1.1 typed plain values
  (booleans, null, numbers, dates, timestamps) are not strings; tags, anchors, aliases, flow collections and deeper
  mappings are refused. `name` equals its folder, has at most 64 characters and is lowercase hyphen-separated words;
  `description` has at most 1024 code points, no `<` or `>`, and does not start with `[TODO:`. The instructions are not
  empty and hold no `[TODO: ...]` line outside fenced code.
- G2 Reading: every file read is strict UTF-8 without NUL bytes or a UTF-16/32 byte order mark, and `SKILL.md` also has
  no UTF-8 byte order mark. A file that cannot be read is one problem that names it; everything else is still checked.
  A scanned Markdown file is not empty.
- G3 Fences: an unclosed fence in a scanned Markdown file or plan index is reported with its line. It hides only its own
  line, so the text after it is still checked.
- G4 "Use when": `description` contains the case-sensitive words `Use when`.
- G5 Skill roots: each skill is a folder `.agents/skills/<name>` holding its `SKILL.md`. A missing or empty
  `.agents/skills`, and a `SKILL.md` anywhere else, are refused.
- G6 References: the scanned Markdown is every `.md` under `.agents/skills`, every `AGENTS.md`, `CLAUDE.md` and
  `.github/copilot-instructions.md`. Its inline links and reference definitions (balanced parentheses, escapes, titles;
  not footnotes) outside fenced code and code spans are local unless they are fragment-only, query-only,
  protocol-relative or another scheme than `file:`. A fragment and then a query end the path, which is percent-decoded.
  The target exists, stays inside the repository and matches the letter case on disk, component by component.
- G7 Reparse points: a linked root is refused before anything is read. Below it, a reparse point under `.agents`, one
  named `AGENTS.md` or `SKILL.md`, and one on the path to any file read or target checked are refused; a junction above
  the root is accepted. The walk that finds `AGENTS.md` and `SKILL.md` files does not enter `.git`, `.build`, a nested
  checkout (a folder holding `.git`) or a reparse point.
- G8 Harness files: `.agents/skills/<name>/agents/openai.yaml` is refused.
- G9 Scoped guidance: `.agents/guidance.json` is `{"schemaVersion":1,"files":[...]}` and lists, once each, exactly the
  repository's `AGENTS.md` files, the root one included, as repository-relative paths with forward slashes.
- G10 Index and pointers: the root `AGENTS.md` links each skill as `(.agents/skills/<name>/SKILL.md)` and nothing else
  under `.agents/skills`. `CLAUDE.md` and `.github/copilot-instructions.md` exist, have at most six non-empty lines and
  link the root `AGENTS.md`.
- G11 PowerShell examples: in a `powershell` fence of a skill package, a line that starts with `./<script>.ps1` names a
  script of the repository, resolved from its root, that parses and accepts each parameter the line passes: its declared
  names and aliases and, for an advanced script, the common parameters, with `WhatIf` and `Confirm` under
  `SupportsShouldProcess`.
- G12 Plan indexes: `Specs/Plans/WIP/README.md`, required when that folder exists, links each Markdown plan directly in
  the folder exactly once and no plan that does not exist; so does `Specs/Plans/Done/README.md` when present. A link
  with a fragment or a query points into a plan and is not its entry.
- G13 Documentation project: with `-Kind Documentation`, a reference may leave the repository for a sibling in the
  folder that holds it, and is checked for existence and letter case only with `-CheckSiblings`; a reference beyond
  that folder is refused. A PowerShell example may name a product command the repository lacks; one it has is still
  checked. Every other rule applies unchanged.

### Agent guidance tests

`./Tests/Test-AgentGuidance.ps1 -TestRoot <marked root>` runs the cases ported from the RedXe, RedTilde and RedPrism
skill suites, a case for each rule above, the command, and the shim against a fixture product whose `.ci-engine` is built
from this engine. Junction and file-lock controls report SKIP off Windows, and symbolic-link controls where the host
cannot create one. Engine CI runs it on Windows and Linux.

## Scoped testing

`Test-Changes.ps1` plans and runs the tests that a change affects. A repository's facts are its
`Tests/test-scopes.json`, version 2, which [Schemas/test-scopes.schema.json](../Schemas/test-scopes.schema.json)
defines; everything else below is engine behavior, the same in every product (the T4 design of
[the tooling plan](Plans/WIP/SharedProjectTooling_2026-11-18.md), accepted on 2026-11-19). The engine holds no
repository name and no PR delegation.

The data: `defaultBranch`; `buildNumber` (`none`, or `mergeBaseCount`: `-BuildNumber` is the commit count of HEAD's
merge base with the base, of HEAD when that base does not resolve); `scopes[]` (`name`; `native`, a suite of
`test.ps1`, or not, then its `commands`, each a product `.ps1` with literal `arguments`; `reuse`; optional
`configurations`; `build` and `iteration` cannot name a native scope); `rules[]` (`pattern`, a glob where `**` is any
folders and `*` and `?` stay within one name, case-insensitive; `scopes`, `*` for every scope; `reason`; optional
`exclusive`, one exact path, or `additive`); `prose` and `unscoped` globs; `projectBindings` (native projects whose
compiled items and transitive local includes become exact-path rules, with per-pattern `overrides`, `includeRoots`
and `exclude`); `nativeInventory` (required with a native scope: its file, `exclude` and `testFolders`);
`runtimeFiles`; `interactiveObligations`; `watchedProcesses`; `prePushProfiles` (`buildOnly` for a profile the
host does not run); `instrumentationVariables`; `systemFiles`. A version 1 file converts mechanically: the dead keys
`project`, `repository`, `toolingCommands`, `prCoverage` and `prWorkflowDigest` go, and each literal of its planner
becomes one of these keys.

Each changed path is classified once, in this order: a matching `exclusive` rule gives only its scopes; a `prose`
path gives every non-native scope plus those of matching rules whose pattern names Markdown (`*.md`); otherwise the
matching rules give theirs, and a path that only `additive` rules match counts as unmatched; an unmatched `unscoped`
path gives none; anything else gives every scope. A scope whose `configurations` exclude the profile is dropped, and
named explicitly it is refused. Identities follow the same classification: an unscoped path is in none, and prose
that gives no native scope is not a native input.

| # | Behavior |
| --- | --- |
| B1 | The base is `-BaseRef`, by default `origin/<defaultBranch>`. Nothing is fetched. |
| B2 | A base that does not resolve or shares no history with HEAD is refused, also under `-Explain`, naming the remedy: fetch it, pass `-BaseRef`, or `-Mode Full`. |
| B3 | Every run except `-Explain` first runs this engine's `Tools/Test-Changelog.ps1 -Root`; PrePush first refuses an uncommitted `CHANGELOG.md` or `Changes/`, then passes `-Base <base>`. |
| B4 | The iteration baseline, `iteration.json` of the profile, is written only by a successful ordinary Affected run (no `-Scopes`, explicit base, `CI` or `GITHUB_ACTIONS`, instrumentation or capability skip). It replaces the merge base for 24 hours while root, profile, environment and Git identity and options match, and never with `-Force`. Every run that executes revokes it first; build outputs changed since it select every scope. |
| B5 | A scope is reused only with `reuse`, without `-Force` or instrumentation, and with a receipt of exactly its identity; a native scope also needs `.build/reports/<suite>-<platform>-<configuration>.json` with `exitCode` 0 and no `skips`. Before `test.ps1`, prior reports for the invoked suites move to a unique archive under the profile receipts. Each invoked suite must then create a current report (the `.instrumented.json` form while instrumented); one with skips is `PASSED_WITH_CAPABILITY_SKIPS` and never reusable. |
| B6 | Source, index, build outputs or environment that change during the build, a scope or the run refuse it, and nothing is published. |
| B7 | Evidence lives in `.build/reports/scoped-tests/<platform>-<configuration without spaces>/` (native receipts, `build.json`, `iteration.json`) and `.build/reports/scoped-tests/independent/` (receipts of non-native scopes, shared by profiles). |
| B8 | A fail-fast lease per checkout output folder and profile (`Enter-ScopedProfileLease`), never taken by `-Explain`, is re-entered on its thread and by the owner's child processes, which inherit `CI_SCOPED_TESTING_LEASE` and verify the owning ancestor PID and its exact process creation identity. |
| B9 | `interactiveObligations` matching the branch's changes (all of them in Full and PrePush) print `INTERACTIVE_NOT_RUN: <suite> - <reason> [<pattern>]` and never run. |
| B10 | Runtime tests need a host of exactly the profile's architecture; a cross build stays a build (`build.ps1`, or a `buildOnly` profile). |
| B11 | Each selected non-native scope runs its `commands` in order, each as `pwsh -NoProfile -NonInteractive -File <path> <arguments>`; formatting (`format.ps1 -Check`) is such a scope in every product. |
| B12 | With a native scope selected, the whole profile is built by `build.ps1 -Platform -Configuration`, then tested by `test.ps1 -Platform -Configuration -Suites <scopes> -SkipBuild -SkipTooling [-ParallelSuites <n> above 1]`. Each executes in a child pwsh through `Tools/Invoke-ScopedScript.ps1`. When the product declares the `EnableTests` switch, the scoped runner passes it for its build profiles and binds it into the build identity. The `mergeBaseCount` policy passes the same `-BuildNumber` to both scripts. `-SkipBuild` instead requires the profile's matching `build.json` and passes its build number to the test. |
| B13 | An unmapped path selects every scope. |
| B14 | The last line is `NOTHING_SELECTED`, `PROSE_CHECKS_PASSED` (only prose or unscoped paths and no native scope), `SELECTED_PASSED` or `FULL_PASSED` (every scope applicable to each profile), followed by `; repository NOT_EVALUATED`. Scopes print `REUSED`, `PASSED` or `PASSED_WITH_CAPABILITY_SKIPS`; `-Explain` prints no token. |
| O1 | PrePush runs every `prePushProfiles` entry, in order, in one call; `-Platform` and `-Configuration` are refused with it. |
| O2 | `-Scopes` takes names or comma-separated strings. |
| O3 | A planner of three outcomes (none, prose, native) is data: `prose` patterns, no rules, a native scope. |

A product's `build.ps1` writes `.build/<platform>/<configuration>`; its `test.ps1` takes the parameters of B12 and
writes the reports of B5. `Build/TestRunEvidence.psm1` serves `test.ps1` on Windows: `Start-TestRunEvidence
-CaptureNativeArtifacts` refuses while a `watchedProcesses` executable runs from the checkout's `.build`, and never
stops it. The Windows run handle starts in `Active` state. Verified completion sets `Completed` for a pass
and `Failed` for a failed test. Verification that throws after ownership admission closes the handle in
`Interrupted` state. Ownership or path refusal leaves the handle active so its owner can finish it.
A closed handle refuses further publication and completion. Retained `started.json` and `completed.json`
are the durable evidence.
The evidence root must be a fully qualified local directory below its drive root. Run IDs use the UTC Gregorian
calendar. Payload paths and alternate data stream names are compared in ordinal order. Inventories and receipt
arrays retain their shape with zero or one entry. Win32 failures include the operating system's reason and path.

Products whose test suites write `.build/<platform>/<configuration>/FailureEvidence` declare `profileFailureImages`
in the scope manifest. A capture with that profile moves prior and current failure output into its run. Prior output
keeps its original bytes. Current output binds the declared executables and their linked PDBs through a verified ZIP
and per-file hashes. Windows paths, directory identities and active writers are checked before moving the output.
`Complete-TestRunEvidenceAfterFailure` preserves an existing test failure when finalization also fails.
The `Build/` and `Tools/` layouts bind the same `ScopedTesting.psm1` and `TestRunEvidence.psm1` templates.

### Scoped testing tests

`./Tests/Test-ScopedTesting.ps1 -TestRoot <marked root>` runs fixture products whose stub `build.ps1`, `test.ps1`,
`validate.ps1` and `format.ps1` record their calls, through the engine runner and through the shims, for every row
above and every shim refusal; engine CI runs it on Windows and Linux.

## Tests

`./Tools/Test-ChangelogWorkflow.ps1 -ScratchRoot <existing folder>` runs local Git fixtures with a fixed identity and
none of the person's hooks or signing, a local bare remote and a stand-in `gh`, inside its scratch root; Windows-only
controls report SKIP elsewhere. It also covers the shims of `Templates/Project/Tools` against fixture products with a
`.ci-engine` built from this engine, including every refusal above. A product's shim passes `-ProjectRoot`, which adds
two product cases: the product's shims equal this engine's templates, and its PrePush runner validates the changelog
against `origin/main` before anything else. Engine CI runs the suite on Windows and Linux.
