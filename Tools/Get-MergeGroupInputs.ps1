<#
.SYNOPSIS Freezes the exact current main/merge-queue integration without executing product code.
.PARAMETER Root Existing reviewed project checkout; the working tree is not changed.
.PARAMETER EventPath GitHub merge_group checks_requested event JSON file, treated as untrusted data.
.OUTPUTS Strict MergeGroupInputs JSON on stdout; no execution, qualification or PR membership verdict.
.NOTES Requires PowerShell 7.4, Git and repository-read GH_TOKEN. Uses GET requests and retains unique
refs/ci/merge-groups refs, including failures. Never edits branches, CI state, merge rules or credentials.
Independent current-main/queue-ref API and fetched Git identities must agree before and after acquisition.
An event file or self-declared digest supplies no workflow provenance, merge authority or native acceptance.
.EXAMPLE ./Tools/Get-MergeGroupInputs.ps1 -Root ../RedMonitor -EventPath $env:GITHUB_EVENT_PATH
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$EventPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$eventFile=Get-Item -LiteralPath $EventPath
if($eventFile.PSIsContainer -or $eventFile.Length -gt 25MB){throw 'Merge group event must be a bounded JSON file.'}
$eventData=[IO.File]::ReadAllText($eventFile.FullName,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json -Depth 30 -AsHashtable
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.MergeGroup.psm1')
Get-CiMergeGroupInputs -Root $Root -Event $eventData|ConvertTo-Json -Depth 15
