<#
.SYNOPSIS
Validates the shared Changes workflow without writing files.
.DESCRIPTION
Reports fragment filename/content and changelog-heading problems; valid pending fragments are expected.
Base also compares the checkout with its merge base: fragments may be added, and CHANGELOG.md may
change only by folding fragments that base already holds (the fold on the default branch), or by the exact
generated release transition of Release-Changelog.ps1 after every fragment is folded.
RequireFolded rejects any pending fragment, for checking a finished fold.
.PARAMETER Root
Repository root of the product checkout to validate. Products run this through their Tools/Test-Changelog.ps1 shim,
which defaults Root to its own repository (Specs/ProjectCommands.md).
.PARAMETER Base
Ref whose merge base with HEAD the checkout is compared with: origin/main before a push; in the compiler-free PR
checks, the pull request's immutable base SHA, which the static adapter phase passes.
.PARAMETER RequireFolded
Also rejects pending fragments, even one. Equivalent to Fold-Changelog.ps1 -Check.
.OUTPUTS
Console summary; no persistent files. Invalid input raises a terminating error/nonzero process exit.
.NOTES
Requires PowerShell 7, and Git for Base. Read-only; no network, build or desktop access.
Primary consumers: repository validation, PrePush, CI, tooling tests and fold checks.
.EXAMPLE
./.ci-engine/Tools/Test-Changelog.ps1 -Root .
.EXAMPLE
./.ci-engine/Tools/Test-Changelog.ps1 -Root . -Base origin/main
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string] $Root, [string] $Base = '', [switch] $RequireFolded)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Changelog.psm1')
$Root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)
# Each returns one string array; @() would wrap it rather than collect its problems.
$problems = Get-ChangelogProblems $Root -RequireFolded:$RequireFolded
if ($Base) { $problems = [string[]]($problems + (Get-ChangelogFoldProblems $Root $Base)) }
if ($problems.Count) { throw "Changelog validation failed:`n$($problems -join "`n")" }
$fragments = Get-ChangelogFragments $Root
Write-Host "Changelog valid: $($fragments.Count) pending fragment(s)$(if ($Base) { "; CHANGELOG.md changes since $Base are exact folds" })."
