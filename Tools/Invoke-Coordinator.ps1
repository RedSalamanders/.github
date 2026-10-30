<#
.SYNOPSIS
Coalesces main activity into a native admission after five quiet minutes.
.PARAMETER Root
Exact current main checkout.
.PARAMETER RunId
GitHub push coordinator run identifier.
.OUTPUTS
Coordination diagnostics and main-qualification status.
.NOTES
Requires PowerShell 7.4, Git and a GitHub token with contents read, actions write and statuses write.
Reads durable CI state, reports its real outcome, waits without native provisioning and dispatches qualify.yml.
Does not build, publish products, consume pending inputs or cancel an admitted pipeline.
.EXAMPLE
./Tools/Invoke-Coordinator.ps1 -Root . -RunId $env:GITHUB_RUN_ID
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RunId)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.GitHub.psm1') -ErrorAction Stop
Invoke-CiCoordinator -Root $Root -RunId $RunId
