<#
.SYNOPSIS Freezes exact PR head/base/synthetic-merge inputs without native execution or a qualification verdict.
.PARAMETER Root Existing project checkout with the exact reviewed GitHub origin.
.PARAMETER PullRequest Open non-draft, mergeable main-targeting PR number.
.OUTPUTS Strict JSON input descriptor on stdout; never a test, merge or publication result.
.NOTES Requires PowerShell 7.4, Git and GH_TOKEN with repository read access. Uses GET requests only.
Fetches three GitHub refs into a unique refs/ci/candidates namespace and retains them, including on failure.
Does not alter the worktree, index, branches or CI state; never imports product code or builds/tests it.
Unknown/stale API/ref/parent identities refuse. Does not change local/PR/main obligations.
.EXAMPLE ./Tools/Get-IntegrationCandidate.ps1 -Root ../RedMonitor -PullRequest 43
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Candidate.psm1')
Get-CiIntegrationCandidate @PSBoundParameters|ConvertTo-Json -Depth 15
