<#
.SYNOPSIS
Promotes an already prepared qualification into an immutable ZIP-only GitHub release.
.PARAMETER Root
Trusted current main checkout, used to recheck current qualification eligibility.
.PARAMETER Directory
Prepared artifact directory with exact batch, receipts, ZIPs and preflight.
.OUTPUTS
GitHub release URL. No build, regeneration, post-qualification signing or asset overwrite.
.NOTES
Explicit trusted main publication action only. Repository write belongs only to this engine-only step.
.EXAMPLE
./Tools/Publish-Release.ps1 -Root . -Directory .build/prepared
#>
[CmdletBinding()]
param([string]$Root='.',[Parameter(Mandatory)][string]$Directory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Publication.psm1')
if($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/main'){throw 'Release publication requires an explicit trusted-main action.'}
$plan=Read-CiPublicationPlan $Directory
if($plan.project.repository -cne $env:GITHUB_REPOSITORY){throw 'Publication repository identity differs.'}
Assert-CiPublicationCurrent -Root $Root -Plan $plan
$release=Publish-CiGitHubRelease -Plan $plan -EligibilityRoot $Root
Write-Host "Published exact qualified ZIPs: $($release.html_url)"

