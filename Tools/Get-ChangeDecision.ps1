<#
.SYNOPSIS
Classifies a complete Git comparison without building or provisioning native tools.
.DESCRIPTION
Validates the target commit's project manifest, includes both rename paths and deleted inputs,
and reports explicit input/exclusion reasons. Unknown paths are meaningful; unreadable input fails.
.PARAMETER Root
Existing project Git checkout.
.PARAMETER Base
Comparison base commit or local ref.
.PARAMETER Head
Candidate commit or local ref; defaults to HEAD.
.OUTPUTS
JSON describing the changed paths and main-batch native obligation.
.NOTES
Requires PowerShell 7.4 and Git. Read-only; no compiler, network access, source writes or tests.
Errors exit nonzero. Consumers are PR checks, main coordination and project policy fixtures.
.EXAMPLE
./Tools/Get-ChangeDecision.ps1 -Root ../RedMonitor -Base origin/main
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Base, [string]$Head = 'HEAD')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Policy.psm1') -ErrorAction Stop
Get-CiChangeDecision -Root $Root -Base $Base -Head $Head | ConvertTo-Json -Depth 12
