<#
.SYNOPSIS
Creates formatting feedback or applies it through an explicit trusted manual action.
.PARAMETER Root
Project checkout.
.PARAMETER Base
Complete comparison base for read-only PR feedback.
.PARAMETER CommitFormatting
Explicit manual mode; verifies the same-repository PR and performs a narrow formatting commit.
.PARAMETER PullRequest
Open PR number for manual mode.
.OUTPUTS
Formatting patch at .build/ci/format.patch; manual mode can push a narrow commit and dispatch new checks.
.NOTES
Uses a checksum-pinned native clang-format without Python. Feedback exits nonzero on drift.
Manual mode requires default-branch workflow_dispatch and contents/actions write; never executes PR scripts.
.EXAMPLE
./Tools/Invoke-Formatting.ps1 -Root . -Base origin/main
#>
[CmdletBinding(DefaultParameterSetName = 'Feedback')]
param([Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory, ParameterSetName = 'Feedback')][string]$Base,
    [Parameter(Mandatory, ParameterSetName = 'Commit')][switch]$CommitFormatting,
    [Parameter(Mandatory, ParameterSetName = 'Commit')][int]$PullRequest)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Format.psm1') -ErrorAction Stop
if ($CommitFormatting) {
    Invoke-CiFormatCommit -Root $Root -Repository $env:GITHUB_REPOSITORY -PullRequest $PullRequest
} else {
    $result = Invoke-CiFormatting -Root $Root -Base $Base
    $result | ConvertTo-Json -Depth 8
    if ($result.drift) { throw 'Formatting differs; review the retained patch or explicitly run the manual formatting action.' }
}
