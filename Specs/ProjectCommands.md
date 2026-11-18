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
- It fails closed with one message that names the pin and the commands that fix it, when `.ci-engine` is missing,
  predates the binding module, is not a Git checkout of its own, is at another commit than `engine.ref`, or has
  changes to tracked files. This is the rule the project adapter already applies to the static CI phase.
- A parameter whose default names the product (such as `-Root`, the repository containing the command) is resolved
  by the shim and passed explicitly; every other bound parameter, including `-WhatIf`, is passed unchanged. The engine
  command makes such a parameter mandatory, so it can also be run directly: `./.ci-engine/Tools/<name> -Root .`.
- A product sees a new engine command, or a change to one, only through its pin (`Tools/Update-ProjectPin.ps1`),
  and then in one pull request that replaces its copy with the shim. The engine never reaches into a product checkout
  other than the one a caller names.

## Commands

| Product command | Engine implementation | Tests |
| --- | --- | --- |
| `Tools/Test-Changelog.ps1` | `Tools/Test-Changelog.ps1`, `Tools/Modules/Ci.Changelog.psm1` | `Tools/Test-ChangelogWorkflow.ps1` |
| `Tools/Fold-Changelog.ps1` | `Tools/Fold-Changelog.ps1` | same |
| `Tools/Submit-ChangelogFold.ps1` | `Tools/Submit-ChangelogFold.ps1` | same |
| `Tools/Test-ChangelogWorkflow.ps1` | `Tools/Test-ChangelogWorkflow.ps1` | engine CI, and each product's tooling tests through its shim |

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
  its entry, and any change outside the Unreleased entries are refused; line endings never count. `-RequireFolded`
  also rejects any pending fragment.
- `Fold-Changelog.ps1` validates everything before writing, inserts entries under Unreleased newest file name first,
  keeps the changelog's byte order mark and line endings, publishes a flushed staged file atomically, then removes only
  the folded fragments. A checkout-local lease serializes folds; a rerun after an interrupted cleanup finishes it
  without duplicating entries. `-WhatIf` previews; `-Check` is the read-only check of a finished fold.
- `Submit-ChangelogFold.ps1` fetches the default branch, folds it with this engine's commands in a temporary worktree
  outside the caller's checkout (under `-WorktreeParent`), verifies the exact fold, commits with the repository's own
  identity, signing and hooks, pushes `changelog/fold-<commit>` and opens its pull request with `gh` (`-PushOnly`
  leaves that to the caller). It removes only the worktree it created, reuses a fold branch already pushed for the same
  commit, and reports an open fold pull request instead of opening a second one. `-WhatIf` never pushes or writes to
  GitHub. Hosted workflows never fold.
- None of them builds native code, takes desktop focus, or stages, commits or pushes outside the submission.

Products run `Test-Changelog.ps1` while editing, with `-Base origin/main` in PrePush, and with `-Base` in the static
CI phase (`HEAD^1` for a pull request's merge commit). The three product variants that existed before the move are
being reconciled into this one implementation; until then `RedSalamander` and `DxUi` keep their own copies (see
[the tooling plan](Plans/WIP/SharedProjectTooling_2026-11-18.md)).

## Tests

`./Tools/Test-ChangelogWorkflow.ps1 -ScratchRoot <existing folder>` runs local Git fixtures with a fixed identity and
none of the person's hooks or signing, a local bare remote and a stand-in `gh`, inside its scratch root; Windows-only
controls report SKIP elsewhere. It also covers the shims of `Templates/Project/Tools` against fixture products with a
`.ci-engine` built from this engine, including every refusal above. A product's shim passes `-ProjectRoot`, which adds
two product cases: the product's shims equal this engine's templates, and its PrePush runner validates the changelog
against `origin/main` before anything else. Engine CI runs the suite on Windows and Linux.
