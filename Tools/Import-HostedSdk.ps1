<#
.SYNOPSIS Imports immutable pinned SDK bytes from one authenticated successful native producer attempt.
.PARAMETER Root Existing application or integration repository; writes only below its .build directory.
.PARAMETER IdentityFile Independently evaluated complete SDK identity JSON below Root/.build, outside the store.
.PARAMETER RunId Exact reviewed DxUi SDK producer run, not a PR or product qualification run.
.PARAMETER Attempt Exact successful attempt; no implicit latest-attempt substitution.
.OUTPUTS JSON with the imported key, original manifest hash and payload location. No build/test verdict.
.NOTES Requires PowerShell 7.4, GH_TOKEN with repository-read access and network access.
Validates the reviewed producer caller/engine, native job, source, attempt and server archive digest;
rejects unsafe archive paths, verifies every payload byte and publishes atomically into an owned store.
Retains downloads, authenticated metadata and failures below .build/sdk-downloads. Does not change pins,
compile, launch products, publish releases, alter accounts or accept application/SDK compatibility.
.EXAMPLE ./Tools/Import-HostedSdk.ps1 -Root ../RedMonitor -IdentityFile ../RedMonitor/.build/expected-sdk.json -RunId 42695804476 -Attempt 1
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$IdentityFile,
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
    [Parameter(Mandatory)][ValidateRange(1,100000)][int]$Attempt)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.SdkTransport.psm1')
$rootPath=[IO.Path]::GetFullPath($Root)
$build=Join-Path $rootPath '.build'
$path=Assert-CiContainedPath $build $IdentityFile
$store=Join-Path $build 'sdk-input-store'
if($path.StartsWith($store+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
    -not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item $path).Length -gt 16KB){throw 'Keep the bounded independently evaluated SDK identity outside its store.'}
$identity=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable
$result=Import-CiHostedSdkArtifact -RepositoryRoot $rootPath -StoreRoot $store -DownloadRoot (Join-Path $build 'sdk-downloads') -Identity $identity -RunId $RunId -Attempt $Attempt
[ordered]@{role='DependencyBytesImported';key=$result.Key;manifestSha256=$result.ManifestSha256;payload=$result.Payload}|ConvertTo-Json
