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
  shim under `Tools/`); a copy in a nested fixture never binds to an outer product. The shim imports
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
  below; line endings never count. Only a base without `CHANGELOG.md` (before adoption) skips the comparison; any other
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
existed before the move (see [the tooling plan](Plans/WIP/SharedProjectTooling_2026-11-18.md), stage 2). One
difference is still the owner's choice (R5 there): this implementation refuses a merged, unfolded fragment removed
without its entry, as five products did, while `DxUi`'s own copy accepted it as a withdrawal.

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

## Tests

`./Tests/Test-AgentGuidance.ps1 -TestRoot <marked root>` runs the cases ported from the RedXe, RedTilde and RedPrism
skill suites, a case for each rule above, the command, and the shim against a fixture product whose `.ci-engine` is built
from this engine. Junction and file-lock controls report SKIP off Windows, and symbolic-link controls where the host
cannot create one. Engine CI runs it on Windows and Linux.

`./Tools/Test-ChangelogWorkflow.ps1 -ScratchRoot <existing folder>` runs local Git fixtures with a fixed identity and
none of the person's hooks or signing, a local bare remote and a stand-in `gh`, inside its scratch root; Windows-only
controls report SKIP elsewhere. It also covers the shims of `Templates/Project/Tools` against fixture products with a
`.ci-engine` built from this engine, including every refusal above. A product's shim passes `-ProjectRoot`, which adds
two product cases: the product's shims equal this engine's templates, and its PrePush runner validates the changelog
against `origin/main` before anything else. Engine CI runs the suite on Windows and Linux.
