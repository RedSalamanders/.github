<#
.SYNOPSIS
Verifies both native architectures before production or publication is allowed.
.PARAMETER Directory
Downloaded regression/production artifact directory.
.PARAMETER Descriptor
Exact frozen batch descriptor; defaults to batch.json inside Directory.
.PARAMETER Phase
Regression verifies the global test gate; Complete also verifies production ZIP bytes.
.OUTPUTS
Verification result. Never changes an archive or compiles code.
.NOTES
Requires PowerShell 7.4. Rejects missing, duplicate, stale, mixed, empty or changed evidence.
.EXAMPLE
./Tools/Test-Qualification.ps1 -Directory evidence -Phase Regression
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Directory, [string]$Descriptor = '',
    [ValidateSet('Regression','Complete')][string]$Phase = 'Complete')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Artifacts.psm1') -ErrorAction Stop
if (-not $Descriptor) { $Descriptor = Join-Path $Directory 'batch.json' }
$batch = Get-Content -LiteralPath $Descriptor -Raw | ConvertFrom-Json -AsHashtable
$null = Test-CiQualification -Directory $Directory -Descriptor $batch -Phase $Phase

