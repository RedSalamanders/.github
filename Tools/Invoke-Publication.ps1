<#
.SYNOPSIS
Prepares immutable qualified ZIP promotion, explicitly publishes its release, or prepares winget validation.
.PARAMETER Root
Trusted main project checkout. No project script is executed.
.PARAMETER RunId
Original successful qualify.yml run.
.PARAMETER EngineRef
Exact reviewed engine pin.
.PARAMETER Operation
Prepare is read-only remotely. Release publishes ZIPs; Winget requires the existing public release.
.OUTPUTS
Qualified ZIPs, publication.json and optional winget manifests beneath .build/publication.
.NOTES
Trusted main manual dispatch only. Never compiles, rebuilds, restamps or overwrites conflicting releases.
.EXAMPLE
./Tools/Invoke-Publication.ps1 -Root . -RunId 123 -EngineRef 0123456789012345678901234567890123456789 -Operation Prepare
#>
[CmdletBinding()]
param([string]$Root='.',[Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$EngineRef,
    [ValidateSet('Prepare','Release','Winget')][string]$Operation='Prepare')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Publication.psm1')
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.GitHub.psm1')
if($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/main'){throw 'Publication requires an explicit trusted-main action.'}
$directory=Join-Path ([IO.Path]::GetFullPath($Root)) ('.build/publication/'+$env:GITHUB_RUN_ID)
$plan=Get-CiPublicationPlan -Root $Root -RunId $RunId -EngineRef $EngineRef -Directory $directory
Test-CiProjectPublicationPreflight -Root ([IO.Path]::GetFullPath($Root)) -Plan $plan
if($Operation -eq 'Winget'){
    $metadata=Invoke-CiApi "repos/$($plan.project.repository)"
    if($metadata.private -or -not $plan.project.winget){throw 'winget requires a public application repository.'}
    $null=Publish-CiGitHubRelease $plan -RequireExisting -Anonymous
}
if($plan.project.winget -and $plan.project.winget.Contains('license') -and $plan.project.winget.license){
    $null=New-CiWingetManifest $plan (Join-Path $directory 'winget')
}elseif($Operation -eq 'Winget'){throw 'Explicit product licensing is still required before winget.'}
$plan|ConvertTo-Json -Depth 25|Set-Content -LiteralPath (Join-Path $directory 'publication.json') -Encoding utf8
if($env:GITHUB_OUTPUT){Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value @(('directory='+$directory),('version='+$plan.batch.version))}
Write-Host "Prepared exact ZIP promotion for $($plan.project.repository) $($plan.batch.version), operation $Operation."

