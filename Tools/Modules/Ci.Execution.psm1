# Execution metadata binding only. This module authenticates no producer or result.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function Get-CiNativeExecutionBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Descriptor,
        [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
        [Parameter(Mandatory)][ValidateRange(1,100000)][int]$RunAttempt)
    foreach($name in @('engine','version','buildNumber','runId')){
        if(-not $Descriptor.Contains($name)){throw "Frozen execution input is missing: $name"}
    }
    $engine=$Descriptor.engine
    if($engine -isnot [Collections.IDictionary] -or $engine.Count -ne 2 -or
        -not $engine.Contains('repository') -or -not $engine.Contains('ref') -or
        $engine.repository -isnot [string] -or $engine.ref -isnot [string] -or
        $engine.repository -cne 'RedSalamanders/.github' -or $engine.ref -cnotmatch '^(?!0{40}$)[a-f0-9]{40}$'){
        throw 'Frozen execution engine identity is malformed.'
    }
    $versionMatch=[regex]::Match([string]$Descriptor.version,'^[0-9]+\.[0-9]+\.([0-9]+)$')
    if(($Descriptor.buildNumber -isnot [int] -and $Descriptor.buildNumber -isnot [long]) -or
        $Descriptor.buildNumber -lt 0 -or $Descriptor.buildNumber -gt 65535 -or
        $Descriptor.version -isnot [string] -or -not $versionMatch.Success){
        throw 'Frozen execution version identity is malformed.'
    }
    if([long]$versionMatch.Groups[1].Value -ne $Descriptor.buildNumber -or $Descriptor.runId -isnot [string] -or $Descriptor.runId -cne $RunId){
        throw 'Frozen execution version or producer run disagrees.'
    }
    return [ordered]@{executionBindingVersion=1;engine=[ordered]@{repository=$engine.repository;ref=$engine.ref};
        version=$Descriptor.version;buildNumber=$Descriptor.buildNumber;runId=$RunId;runAttempt=$RunAttempt}
}

function Test-CiRegressionExecutionBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Receipt,
        [Parameter(Mandatory)][Collections.IDictionary]$Descriptor,
        [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,
        [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
        [Parameter(Mandatory)][ValidateRange(1,100000)][int]$RunAttempt)
    # The independently authenticated workflow supplies Descriptor/RunId/Attempt.
    # A self-declared JSON digest or this data check alone supplies no trust.
    $expected=Get-CiNativeExecutionBinding -Descriptor $Descriptor -RunId $RunId -RunAttempt $RunAttempt
    $null=Test-CiRegressionReceipt -Receipt $Receipt -Descriptor $Descriptor -Platform $Platform
    foreach($name in @('executionBindingVersion','engine','version','buildNumber','runAttempt','canonicalEvidence')){
        if(-not $Receipt.Contains($name)){throw "Regression execution binding is missing: $name"}
    }
    if(($Receipt.executionBindingVersion -isnot [int] -and $Receipt.executionBindingVersion -isnot [long]) -or $Receipt.executionBindingVersion -ne 1 -or
        ($Receipt.runAttempt -isnot [int] -and $Receipt.runAttempt -isnot [long]) -or $Receipt.runAttempt -ne $RunAttempt -or
        ($Receipt.buildNumber -isnot [int] -and $Receipt.buildNumber -isnot [long]) -or $Receipt.buildNumber -ne $expected.buildNumber -or
        $Receipt.version -isnot [string] -or $Receipt.version -cne $expected.version){throw 'Regression execution version or attempt changed.'}
    $engine=$Receipt.engine
    if($engine -isnot [Collections.IDictionary] -or $engine.Count -ne 2 -or
        -not $engine.Contains('repository') -or -not $engine.Contains('ref') -or
        $engine.repository -isnot [string] -or $engine.ref -isnot [string] -or
        $engine.repository -cne $expected.engine.repository -or $engine.ref -cne $expected.engine.ref){throw 'Regression execution used another engine.'}
    if($Receipt.artifacts -isnot [array] -or $Receipt.canonicalEvidence -isnot [array]){throw 'Regression artifacts and evidence must retain explicit arrays.'}
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $prefix=".build/$Platform/Release/"
    foreach($artifact in @($Receipt.artifacts)){
        if($artifact -isnot [Collections.IDictionary] -or -not $artifact.Contains('path') -or -not $artifact.Contains('sha256') -or
            $artifact.path -isnot [string] -or $artifact.sha256 -isnot [string]){throw 'Regression artifact references must retain typed paths and hashes.'}
        $path=[string]$artifact.path
        if(-not $path.StartsWith($prefix,[StringComparison]::Ordinal) -or $path -match '[\\:\x00-\x1f]' -or
            $path -match '(^|/)\.{1,2}(/|$)|//' -or [IO.Path]::GetExtension($path) -notin @('.exe','.dll','.lib') -or
            -not $paths.Add($path)){throw 'Regression artifact paths are duplicated or outside the native profile.'}
    }
    $evidence=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if(@($Receipt.canonicalEvidence).Count -eq 0){throw 'Regression execution needs original canonical evidence.'}
    foreach($record in @($Receipt.canonicalEvidence)){
        if($record -isnot [Collections.IDictionary] -or -not $record.Contains('path') -or -not $record.Contains('sha256') -or
            $record.path -isnot [string] -or $record.sha256 -isnot [string] -or
            [string]::IsNullOrWhiteSpace([string]$record.path) -or [string]$record.path -match '[\x00-\x1f]|(^|[\\/])\.{1,2}([\\/]|$)' -or
            [string]$record.sha256 -cnotmatch '^[a-f0-9]{64}$' -or -not $evidence.Add(([string]$record.path).Replace('\','/'))){
            throw 'Regression canonical evidence references are missing, duplicated or malformed.'
        }
    }
    return $true
}

Export-ModuleMember -Function Get-CiNativeExecutionBinding,Test-CiRegressionExecutionBinding
