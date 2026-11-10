<#
.SYNOPSIS Independently verifies an isolated candidate's actual native jobs, original receipts, tested profile and canonical evidence bytes.
.PARAMETER Root Existing project checkout with the exact reviewed GitHub origin.
.PARAMETER PullRequest Current open, non-draft main-targeting candidate.
.PARAMETER ExpectedIdentity Independently acquired current canonical candidate identity.
.PARAMETER RunId Original isolated producer workflow run.
.PARAMETER Attempt Original producer attempt, which must still be current.
.PARAMETER IsolationNonce Original unique admission nonce.
.PARAMETER OutputRoot Existing owned evidence directory: hosted RUNNER_TEMP, local project .build or marked RedSalamander.Perf. Local RedSalamander uses the marked sandbox only.
.OUTPUTS JSON native verification record and retained original ZIPs in a new unique evidence directory.
.NOTES Uses repository-read GH_TOKEN, GET requests and diagnostic candidate Git fetches only. Does not extract or execute downloaded code, restore caches, write checks or state, merge, delegate local coverage, adopt results or authorize production.
Original archive sizes/digests, input binding, both native receipts, complete tested profile and canonical evidence hashes must agree. Reacquisition after transfer refuses stale candidates, attempts and catalog changes. Failures retain original evidence and never write verified-result.json.
.EXAMPLE ./Tools/Get-CandidateNativeResult.ps1 -Root ../RedMonitor -PullRequest 49 -ExpectedIdentity ('a'*64) -RunId 123 -Attempt 1 -IsolationNonce ('b'*32) -OutputRoot Z:/RedSalamander.Perf/evidence
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedIdentity,
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
    [Parameter(Mandatory)][ValidateRange(1,100000)][int]$Attempt,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$IsolationNonce,
    [Parameter(Mandatory)][string]$OutputRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.CandidateVerification.psm1')
Get-CiCandidateNativeResult @PSBoundParameters|ConvertTo-Json -Depth 30
