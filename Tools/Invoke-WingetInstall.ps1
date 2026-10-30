<#
.SYNOPSIS
Validates and installs a prepared portable winget manifest on its matching hosted architecture.
.PARAMETER Root
Trusted main checkout; owns scratch and the existing sandbox initializer.
.PARAMETER Directory
Prepared immutable publication artifact.
.PARAMETER Platform
Matching native x64 or ARM64 hosted runner.
.OUTPUTS
Source/version/manifest-bound native winget install receipt, retained logs and cleanup result.
.NOTES
Explicit publication only on disposable GitHub-hosted Windows. Native product builds are never invoked.
Installation is confined to a run-owned location and an initially absent exact package identity.
.EXAMPLE
./Tools/Invoke-WingetInstall.ps1 -Root . -Directory prepared -Platform x64
#>
[CmdletBinding()]
param([string]$Root='.',[Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Publication.psm1')
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.WingetPublication.psm1')
if($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/main' -or
    $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){throw 'Native winget install qualification is an explicit hosted publication action.'}
$native=if($Platform -eq 'ARM64'){'Arm64'}else{'X64'}
if([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -cne $native){throw 'winget install requires its matching native architecture.'}
$plan=Read-CiPublicationPlan $Directory
$manifest=Join-Path $Directory 'winget'
$package=$plan.project.winget.identifier
$identity=New-RSWingetPublicationIdentity -PackageIdentifier $package -Version $plan.batch.version -ManifestRoot $manifest -PullRequestTitle "Update: $package version $($plan.batch.version)"
if($plan.project.repository -ceq 'RedSalamanders/RedSalamander'){
    Import-Module (Join-Path $Root 'Tools/Modules/Testing/TestSandbox.psm1')
    $env:REDSALAMANDER_TEST_ROOT=Join-Path ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Root))) 'RedSalamander.Perf'
    $null=Initialize-RSTestSandboxRoot -TestRoot $env:REDSALAMANDER_TEST_ROOT -RepoRoot $Root -AllowExternalInitialization
    $scratch=New-RSTestSandboxScratchDirectory -RepoRoot $Root -Harness UnifiedCI -Case "Winget-$Platform"
}else{
    $scratch=Assert-CiContainedPath $Root (Join-Path $Root ('.build/winget-install/'+[guid]::NewGuid().ToString('N')))
    [void][IO.Directory]::CreateDirectory($scratch)
}
$winget=(Get-Command winget.exe -ErrorAction Stop).Source
$null=Invoke-CiProcess $winget @('settings','--enable','LocalManifestFiles') $scratch
$null=Invoke-CiProcess $winget @('validate','--manifest',[IO.Path]::GetFullPath($manifest)) $scratch -TimeoutSeconds 180
$noApplicationsFound=-1978335212
$before=Invoke-CiProcess $winget @('list','--exact','--id',$package,'--accept-source-agreements','--disable-interactivity') $scratch -AllowFailure
if($before.exitCode -ne $noApplicationsFound){throw 'The exact product must be absent before this owned install operation.'}
$owned=$false;$passed=$false
try{
    $owned=$true
    $install=Invoke-CiProcess $winget @('install','--manifest',[IO.Path]::GetFullPath($manifest),
        '--location',(Join-Path $scratch 'installed'),'--scope','user','--accept-package-agreements',
        '--accept-source-agreements','--disable-interactivity') $scratch -TimeoutSeconds 600
    [IO.File]::WriteAllText((Join-Path $scratch 'install.log'),$install.stdout+$install.stderr)
    $null=Invoke-CiProcess $winget @('list','--exact','--id',$package,'--accept-source-agreements','--disable-interactivity') $scratch
    $passed=$true
}finally{
    if($owned){
        $list=Invoke-CiProcess $winget @('list','--exact','--id',$package,'--accept-source-agreements','--disable-interactivity') $scratch -AllowFailure
        if($list.exitCode -eq 0){
            $null=Invoke-CiProcess $winget @('uninstall','--exact','--id',$package,'--silent','--purge','--accept-source-agreements','--disable-interactivity') $scratch -TimeoutSeconds 300
        }elseif($list.exitCode -ne $noApplicationsFound){throw 'Cannot verify owned installation cleanup; retained evidence requires review.'}
    }
}
if(-not $passed){throw 'Native winget install did not complete.'}
$path=Join-Path $scratch "winget-$Platform.json"
[ordered]@{schemaVersion=1;passed=$true;platform=$Platform;commit=$plan.batch.commit;nativeDigest=$plan.batch.nativeDigest;
    version=$plan.batch.version;manifestDigest=$identity.PublicationId;runId=$env:GITHUB_RUN_ID;
    wingetVersion=(Invoke-CiProcess $winget @('--version') $scratch).stdout.Trim();cleanedUp=$true}|
    ConvertTo-Json|Set-Content -LiteralPath $path -Encoding utf8
if($env:GITHUB_OUTPUT){Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value ('receipt_path='+$path)}
Write-Host "Validated, installed, enumerated and removed exact portable package on $Platform."

