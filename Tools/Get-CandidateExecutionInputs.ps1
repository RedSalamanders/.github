<#
.SYNOPSIS Freezes manual shadow-execution inputs on an exact isolated trusted-controller branch.
.PARAMETER Root Clean default-branch controller checkout, never the candidate worktree.
.PARAMETER PullRequest Same-repository open non-draft main-targeting PR.
.PARAMETER ExpectedIdentity Independently frozen IntegrationCandidateInputs identity.
.PARAMETER IsolationNonce Unique 32-lowercase-hex isolation branch suffix.
.OUTPUTS CandidateExecutionInputs JSON on stdout, including the exact native batch inputs.
.NOTES Requires PowerShell 7.4, Git, read-only GH_TOKEN and the exact hosted manual caller context.
Uses only GET API requests and the canonical candidate acquisition's retained diagnostic Git refs.
Never creates a remote branch, output file, check, CI state or native build/test. Imports no product code.
Rechecks main, isolated ref, PR/merge inputs and independent workflow blob before returning data.
No test, merge, local-delegation or main-adoption authority follows from this input record.
.EXAMPLE ./Tools/Get-CandidateExecutionInputs.ps1 -Root . -PullRequest 43 -ExpectedIdentity ('a'*64) -IsolationNonce ('b'*32)
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedIdentity,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$IsolationNonce)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.CandidateExecution.psm1')
Get-CiCandidateExecutionInputs @PSBoundParameters|ConvertTo-Json -Depth 20
