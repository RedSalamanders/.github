<#
.SYNOPSIS
Verifies actual regression execution for a frozen batch before production starts.
.PARAMETER Descriptor
Exact admitted batch JSON.
.PARAMETER Receipt
Architecture's source-bound regression receipt.
.PARAMETER Platform
x64 or ARM64.
.OUTPUTS
Validation diagnostics; missing, stale, empty, failed or assertion-free evidence exits nonzero.
.NOTES
Requires PowerShell 7.4. Read-only; does not build or rerun any suite.
.EXAMPLE
./Tools/Test-RegressionGate.ps1 -Descriptor .build/ci/batch.json -Receipt .build/ci/regression.json -Platform x64
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Descriptor, [Parameter(Mandatory)][string]$Receipt,
    [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Policy.psm1') -ErrorAction Stop
$batch = Get-Content -LiteralPath $Descriptor -Raw | ConvertFrom-Json -AsHashtable
$proof = Get-Content -LiteralPath $Receipt -Raw | ConvertFrom-Json -AsHashtable
$null = Test-CiRegressionReceipt $proof $batch $Platform
Write-Host "Verified executed regression entries on $Platform for $($batch.commit)."
