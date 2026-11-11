<#
.SYNOPSIS Independently verifies original native candidate evidence and reports it on the exact PR head.
.PARAMETER Root Exact clean current-main project checkout with its reviewed engine.
.PARAMETER PullRequest Current open, ready native candidate.
.PARAMETER ExpectedIdentity Independently acquired current canonical candidate identity.
.PARAMETER RunId Original isolated native producer workflow run.
.PARAMETER Attempt Original producer attempt, which must still be current.
.PARAMETER IsolationNonce Original admission nonce.
.PARAMETER OutputRoot Existing owned hosted evidence directory under RUNNER_TEMP.
.OUTPUTS JSON report binding and a GitHub native / candidate-integration check on the exact head.
.NOTES Only the actual hosted trusted-main manual integration-report workflow can write. Requires repository/Actions/pull-request/check read and checks write. The original verifier downloads bounded artifacts without extracting or executing code. Retains failed evidence and completes an owned pending check as failure on refusal. Never accepts saved verification JSON, modifies source/branch policy, merges, cancels jobs, delegates local coverage, adopts main results or authorizes production. A report alone does not establish required-check or stale-base enforcement.
.EXAMPLE ./Tools/Publish-CandidateCheck.ps1 -Root . -PullRequest 49 -ExpectedIdentity ('a'*64) -RunId 123 -Attempt 1 -IsolationNonce ('b'*32) -OutputRoot $env:RUNNER_TEMP/reports
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
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.CandidateReporting.psm1')
Publish-CiCandidateCheck @PSBoundParameters|ConvertTo-Json -Depth 20
