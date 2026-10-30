<#
.SYNOPSIS
Submits an exact-version winget PR after both native install gates pass.
.PARAMETER Root
Trusted current main checkout.
.PARAMETER Directory
Immutable prepared publication artifact directory.
.PARAMETER InstallEvidence
Directory holding both native winget install receipts.
.OUTPUTS
Existing exact publication or automation-owned upstream PR URL.
.NOTES
Explicit main dispatch only; requires WINGET_TOKEN. Refuses stale evidence, conflicting PRs and modified manifests.
.EXAMPLE
./Tools/Submit-Winget.ps1 -Root . -Directory prepared -InstallEvidence install-evidence
#>
[CmdletBinding()]
param([string]$Root='.',[Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$InstallEvidence)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Publication.psm1')
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Winget.psm1')
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.WingetPublication.psm1')
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.WingetInstall.psm1')
if($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/main'){throw 'winget submission requires an explicit trusted-main dispatch.'}
$plan=Read-CiPublicationPlan $Directory
Assert-CiPublicationCurrent $Root $plan
$identity=New-RSWingetPublicationIdentity -PackageIdentifier $plan.project.winget.identifier -Version $plan.batch.version -ManifestRoot (Join-Path $Directory 'winget') -PullRequestTitle "Update: $($plan.project.winget.identifier) version $($plan.batch.version)"
foreach($platform in @('x64','ARM64')){
    $files=@(Get-ChildItem $InstallEvidence -Recurse -Filter "winget-$platform.json" -File)
    if($files.Count -ne 1){throw 'Both native winget installation receipts are required.'}
    $receipt=Get-Content $files[0].FullName -Raw|ConvertFrom-Json -AsHashtable
    $null=Test-CiWingetInstallReceipt -Receipt $receipt -Plan $plan -Platform $platform -RunId $env:GITHUB_RUN_ID -ManifestDigest $identity.PublicationId
}
$result=Submit-CiWinget -Plan $plan -ManifestDirectory (Join-Path $Directory 'winget')
Write-Host "winget publication: $($result.Url)"

