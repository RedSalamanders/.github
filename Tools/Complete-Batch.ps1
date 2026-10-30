<#
.SYNOPSIS
Records the actual final outcome of the admitted native pipeline.
.PARAMETER Descriptor
Retained exact admission descriptor.
.PARAMETER Outcome
Succeeded, failed or cancelled after the global native test and production jobs settle.
.PARAMETER Root
Exact source checkout, used to propagate the outcome to a prose-only main head.
.OUTPUTS
Persistent CI-state revision and main-qualification status.
.NOTES
Requires PowerShell 7.4 and GH_TOKEN with contents/status write. Refuses another run's state.
No builds, publication or artifact regeneration. The workflow calls this only after verifying phase results.
.EXAMPLE
./Tools/Complete-Batch.ps1 -Descriptor .build/ci/batch.json -Outcome failed
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Descriptor,
    [Parameter(Mandatory)][ValidateSet('succeeded','failed','cancelled')][string]$Outcome,
    [string]$Root = '.')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.GitHub.psm1') -ErrorAction Stop
$batch = Get-Content -LiteralPath $Descriptor -Raw | ConvertFrom-Json -AsHashtable
if ($env:GITHUB_REPOSITORY -cne $batch.repository -or $env:GITHUB_RUN_ID -cne $batch.runId) { throw 'Completion identity does not match the current GitHub run.' }
Complete-CiBatch -Descriptor $batch -Outcome $Outcome -Root $Root
