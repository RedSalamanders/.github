<#
.SYNOPSIS Verifies the still-live local pinned SDK reader owner before MSBuild compilation.
.PARAMETER ProjectRoot Application repository owning the build operation and .build lease witness.
.PARAMETER LeasePath Exact witness created by the application's active SDK reader operation.
.PARAMETER SdkRoot Exact immutable payload imported by this build.
.PARAMETER Platform x64 or ARM64 target.
.PARAMETER Configuration Release; unsupported profiles use source builds.
.PARAMETER SdkContract QualifiedAbiV2 when the held reader requires actual tool binding.
.PARAMETER ToolPropertyFile Bounded actual MSBuild tool and search-path properties below project .build for v2.
.OUTPUTS No mutation or verdict. Nonzero on a missing, stale, closed or incompatible lease.
.NOTES Requires PowerShell 7.4. Reads owned files and process identity only; never launches or stops a product.
.EXAMPLE ./Tools/Test-SdkConsumerLease.ps1 -ProjectRoot ../RedMonitor -LeasePath ../RedMonitor/.build/sdk-leases/lease.json -SdkRoot ../RedMonitor/.build/sdk-cache/payload -Platform x64 -Configuration Release
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$LeasePath,
    [Parameter(Mandatory)][string]$SdkRoot,[Parameter(Mandatory)][string]$Platform,[Parameter(Mandatory)][string]$Configuration,
    [string]$SdkContract='',[string]$ToolPropertyFile='')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.SdkConsumer.psm1')
Assert-CiSdkConsumerLease @PSBoundParameters
