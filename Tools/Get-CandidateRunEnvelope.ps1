<#
.SYNOPSIS Authenticates an exact completed isolated producer's GitHub metadata without accepting its native result.
.PARAMETER Root Existing project checkout with the exact reviewed GitHub origin.
.PARAMETER PullRequest Current open, non-draft main-targeting candidate.
.PARAMETER ExpectedIdentity Independently acquired current canonical candidate identity.
.PARAMETER RunId Exact isolated producer workflow run.
.PARAMETER Attempt Original attempt, which must still be the current attempt.
.PARAMETER IsolationNonce Original unique admission nonce.
.OUTPUTS JSON envelope with original server artifact digests and independently reconstructed expected inputs.
.NOTES Requires PowerShell 7.4, Git and repository-read GH_TOKEN. Uses only GET requests and canonical candidate fetches.
Retains diagnostic Git refs; does not execute product code, download/extract artifacts, write checks or alter obligations.
Artifact bytes, canonical native evidence, required merge enforcement and adoption remain separately unverified.
.EXAMPLE ./Tools/Get-CandidateRunEnvelope.ps1 -Root ../RedMonitor -PullRequest 49 -ExpectedIdentity ('a'*64) -RunId 123 -Attempt 1 -IsolationNonce ('b'*32)
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedIdentity,
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
    [Parameter(Mandatory)][ValidateRange(1,100000)][int]$Attempt,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$IsolationNonce)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.CandidateResults.psm1')
Get-CiCandidateRunEnvelope @PSBoundParameters|ConvertTo-Json -Depth 25
