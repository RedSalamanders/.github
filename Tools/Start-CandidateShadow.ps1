<#
.SYNOPSIS
Freezes an exact candidate and requests isolated read-only native shadow execution.
.PARAMETER Root
Clean exact current main project checkout with the reviewed engine and generated callers.
.PARAMETER PullRequest
Open, ready, mergeable same-repository main-targeting PR. Imports no candidate code.
.PARAMETER ExpectedIdentity
Exact identity acquired independently with Get-IntegrationCandidate.ps1.
.OUTPUTS
CandidateShadowDispatchRequest JSON. DispatchRequested means an API request, not a run or pass.
.NOTES
Requires PowerShell 7.4, Git and an operator GH_TOKEN with repository contents/Actions write.
Creates one unique ci-native branch at trusted main, append-only .build/ci admission
journals and one workflow dispatch. Never moves existing refs, merges, writes checks,
cancels runs, publishes products or supplies a native/adoption verdict. Failures retain
original refs/journals; there is no destructive rollback. WhatIf performs canonical
GET/fetch reacquisition with diagnostic local refs, but creates no journal, remote ref or dispatch.
Project caller rollout and actual hosted shadow acceptance are separate prerequisites.
.EXAMPLE
./Tools/Start-CandidateShadow.ps1 -Root ../RedXe -PullRequest 85 -ExpectedIdentity ('a'*64) -WhatIf
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedIdentity)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.CandidateAdmission.psm1')
Start-CiCandidateShadow @PSBoundParameters|ConvertTo-Json -Depth 20
