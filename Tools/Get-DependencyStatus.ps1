<#
.SYNOPSIS
Writes the compiler-free dependency inventory/advisory report for all six projects.
.DESCRIPTION
Reads exact main trees and declared JSON pins through read-only reviewed GitHub routes.
Does not clone, restore, compile, adopt pins, create issues or send notifications.
.PARAMETER OutputDirectory
Report directory beneath an existing approved workspace; never a drive root.
.OUTPUTS
dependency-status.json and a compact console summary. Nonzero on incomplete repository coverage.
.NOTES
Requires PowerShell 7.4, network and a read-capable GH_TOKEN. The public central workflow
cannot read a private sibling repository; that limitation remains an explicit failure.
Side effects: creates only the report directory/file, without removing older evidence.
.EXAMPLE
./Tools/Get-DependencyStatus.ps1 -OutputDirectory Z:/RedSalamander.Perf/evidence/dependency-status
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Dependencies.psm1')
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if($OutputDirectory.TrimEnd('\','/') -eq [IO.Path]::GetPathRoot($OutputDirectory).TrimEnd('\','/')){throw 'A drive root cannot hold dependency report output.'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$path=Join-Path $OutputDirectory 'dependency-status.json'
if(Test-Path -LiteralPath $path){throw 'Dependency report output already exists; select a fresh report directory.'}
$report=Get-CiDependencyReport
$report|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Observed $(@($report.projects|Where-Object status -ceq 'observed').Count)/6 repositories; no native builds or source writes. Report: $path"
if(-not $report.coverageComplete){throw 'Dependency inventory coverage is incomplete; read the retained per-repository errors.'}
