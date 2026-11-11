<#
.SYNOPSIS Verifies the still-live local pinned SDK reader owner before MSBuild compilation.
.PARAMETER ProjectRoot Application repository owning the build operation and .build lease witness.
.PARAMETER LeasePath Exact witness created by the application's active SDK reader operation.
.PARAMETER SdkRoot Exact immutable payload imported by this build.
.PARAMETER Platform x64 or ARM64 target.
.PARAMETER Configuration Release; unsupported profiles use source builds.
.PARAMETER SdkContract QualifiedAbiV2 for pinned actual-tool binding, or LocalUnpinnedAbiV1 for a separate local compiler lease.
.PARAMETER ToolPropertyFile Bounded actual MSBuild tool and search-path properties below project .build for v2.
.PARAMETER PreflightLocalOutputs Verify the live local lease and both output directories before MSBuild creates directories or metadata files. Does not replace subsequent actual-tool verification.
.PARAMETER OutputDirectory Actual evaluated OutDir for local preflight.
.PARAMETER IntermediateDirectory Actual evaluated IntDir for local preflight.
.OUTPUTS No mutation or verdict. Nonzero on a missing, stale, closed or incompatible lease.
.NOTES Requires PowerShell 7.4. Reads owned files and process identity only; never launches or stops a product.
.EXAMPLE ./Tools/Test-SdkConsumerLease.ps1 -ProjectRoot ../RedMonitor -LeasePath ../RedMonitor/.build/sdk-leases/lease.json -SdkRoot ../RedMonitor/.build/sdk-cache/payload -Platform x64 -Configuration Release
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$LeasePath,
    [Parameter(Mandatory)][string]$SdkRoot,[Parameter(Mandatory)][string]$Platform,[Parameter(Mandatory)][string]$Configuration,
    [string]$SdkContract='',[string]$ToolPropertyFile='',
    [switch]$PreflightLocalOutputs,[string]$OutputDirectory='',[string]$IntermediateDirectory='')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.SdkConsumer.psm1')
if($PreflightLocalOutputs){
    if($SdkContract -cne 'LocalUnpinnedAbiV1' -or $ToolPropertyFile){throw 'Local output preflight requires its explicit local contract and no metadata file.'}
    Assert-CiLocalSdkOutputLease -ProjectRoot $ProjectRoot -LeasePath $LeasePath -SdkRoot $SdkRoot -Platform $Platform -Configuration $Configuration -OutputDirectory $OutputDirectory -IntermediateDirectory $IntermediateDirectory
}else{
    if($OutputDirectory -or $IntermediateDirectory){throw 'Output arguments require explicit local preflight.'}
    Assert-CiSdkConsumerLease -ProjectRoot $ProjectRoot -LeasePath $LeasePath -SdkRoot $SdkRoot -Platform $Platform -Configuration $Configuration -SdkContract $SdkContract -ToolPropertyFile $ToolPropertyFile
}
