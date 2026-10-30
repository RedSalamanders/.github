<#
.SYNOPSIS
Describes the exact cumulative native inputs and frozen batch version of a Git commit.
.PARAMETER Root
Existing project Git checkout.
.PARAMETER Ref
Candidate commit or local ref; defaults to HEAD.
.OUTPUTS
JSON with commit, policy/engine identity, native digest, build number, version and input count.
.NOTES
Requires PowerShell 7.4 and Git. Read-only; never builds, launches tests or uses credentials.
Unreadable or invalid inputs exit nonzero. Used by main admission and artifact verification.
.EXAMPLE
./Tools/Get-InputDescriptor.ps1 -Root ../RedMonitor
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root, [string]$Ref = 'HEAD')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Policy.psm1') -ErrorAction Stop
New-CiInputDescriptor -Root $Root -Ref $Ref | ConvertTo-Json -Depth 12
