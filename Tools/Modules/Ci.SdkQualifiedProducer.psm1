# A producer-side byte reference. Only a separately authenticated hosted envelope
# can establish its origin; this JSON never authenticates itself or a product test.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkProducer.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkAbi.psm1')

function Assert-CiQualifiedSdkAbiReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Reference)
    $json=$Reference|ConvertTo-Json -Depth 12 -Compress
    if($json.Length -gt 64MB -or -not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/qualified-sdk-abi-reference.schema.json'))){throw 'Invalid qualified SDK ABI reference schema.'}
    Assert-CiSdkAbiReference $Reference.toolchainReference
    if($Reference.platform -cne $Reference.toolchainReference.compiler.platform){throw 'Qualified SDK reference has another toolchain architecture.'}
}

function Write-CiQualifiedSdkAbiReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$ToolingRoot,
        [Parameter(Mandatory)][string]$StorageEngineRoot,[Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][ValidatePattern('^0\.1\.[1-9][0-9]{0,19}$')][string]$Version,
        [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,
        [Parameter(Mandatory)][string]$MSBuildPath,[Parameter(Mandatory)][string]$OutputFile)
    if(-not $IsWindows -or $env:CI_NATIVE_BUILDS_DISABLED -eq 'true'){throw 'Qualified SDK references require explicit Windows native producer tooling.'}
    $hostArchitecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $expectedHost=if($Platform -ceq 'x64'){'X64'}else{'Arm64'}
    if($hostArchitecture -cne $expectedHost -or [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString() -cne $expectedHost){throw 'Qualified SDK references require matching native host and process architectures.'}
    $producer=Read-CiSdkProducerPolicy
    $sourceCommit=Resolve-CiCommit $SourceRoot HEAD
    $sources=@($producer.sources|Where-Object commit -CEQ $sourceCommit)
    if($sources.Count -ne 1){throw 'Qualified SDK source must remain an exact reviewed producer pin.'}
    $source=$sources[0]
    $request=@{sourceCommit=$sourceCommit;apiRevision=$source.apiRevision;sourceContentIdentity=$source.contentIdentity;
        toolingRef=$producer.toolingRef;toolingContentIdentity=$producer.toolingContentIdentity;
        storageEngineRef=$producer.storageEngineRef;storageEngineContentIdentity=$producer.storageEngineContentIdentity}
    Assert-CiSdkProducerCheckouts -Request $request -ToolingRoot $ToolingRoot -SourceRoot $SourceRoot -StorageEngineRoot $StorageEngineRoot
    $output=Assert-CiContainedPath (Join-Path $ToolingRoot '.build') $OutputFile
    if(Test-Path -LiteralPath $output){throw 'A qualified SDK ABI reference output already exists and cannot be replaced.'}
    $store=[IO.Path]::GetFullPath($StoreRoot).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if($output.StartsWith($store,[StringComparison]::OrdinalIgnoreCase)){throw 'Keep the ABI reference outside the immutable SDK store.'}
    $receiptPath=Assert-CiContainedPath $SourceRoot (Join-Path $SourceRoot ".build/sdk/DxUi-SDK-$Version-$Platform.zip.receipt.json")
    if(-not [IO.File]::Exists($receiptPath) -or (Get-Item -LiteralPath $receiptPath).Length -gt 64KB){throw 'Missing bounded native SDK qualification receipt.'}
    $receiptStream=[IO.File]::Open($receiptPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $entry=$null;$cache=$null;$primary=$null
    try{
        $reader=[IO.StreamReader]::new($receiptStream,[Text.UTF8Encoding]::new($false,$true),$false,4096,$true)
        try{$receipt=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable}finally{$reader.Dispose()}
        if($receipt.schemaVersion -ne 1 -or $receipt.kind -cne 'sdk' -or $receipt.version -cne $Version -or $receipt.source -cne $sourceCommit -or
            $receipt.apiRevision -ne $source.apiRevision -or $receipt.platform -cne $Platform -or $receipt.configuration -cne 'Release' -or
            $receipt.runtime -cne 'MD' -or $receipt.testsIncluded -isnot [bool] -or $receipt.testsIncluded){throw 'Qualified SDK reference needs exact pinned Release production SDK qualification.'}
        foreach($gate in @('smokePassed','producerPdbIsolationPassed','missingPackagedPdbControlPassed','licenseClosurePassed','firstPartyWarningControlPassed','headerClosurePassed')){
            if($receipt[$gate] -isnot [bool] -or -not $receipt[$gate]){throw "Native SDK qualification gate did not pass: $gate."}
        }
        # Preserve the full v1 producer recipe. This producer-only recheck binds the
        # portable reference to the inputs actually used by the already qualified SDK.
        $inputs=Import-Module (Join-Path $ToolingRoot 'Tools/SdkCacheInputs.psm1') -PassThru
        $timer=[Diagnostics.Stopwatch]::StartNew()
        Write-Host '[SDK_ABI_REFERENCE] phase=ProducerRecipeBefore state=begin'
        $identity=& $inputs {param($r,$p) Get-DxUiSdkCacheInputIdentity -Root $r -Platform $p} $SourceRoot $Platform
        Write-Host "[SDK_ABI_REFERENCE] phase=ProducerRecipeBefore state=end elapsedMs=$($timer.ElapsedMilliseconds)"
        $cache=Import-Module (Join-Path $StorageEngineRoot 'Tools/Modules/Ci.SdkCache.psm1') -PassThru
        $key=& $cache {param($i) Get-CiSdkCacheKey $i} $identity
        if($key -cne $receipt.sdkStoreInputKey -or $identity.sourceBytes -cne $source.contentIdentity){throw 'Current full producer inputs differ from the qualified SDK.'}
        $entry=& $cache {param($s,$i,$h) Open-CiSdkCacheEntry -StoreRoot $s -Identity $i -ManifestSha256 $h} $StoreRoot $identity $receipt.sdkStoreManifestSha256
        if($null -eq $entry){throw 'The qualified SDK input version is unavailable.'}
        $timer.Restart();Write-Host '[SDK_ABI_REFERENCE] phase=PortableToolchain state=begin'
        $reference=Get-CiSdkAbiReference -ToolingRoot $ToolingRoot -MSBuildPath $MSBuildPath -ProjectPath (Join-Path $SourceRoot 'src/DxUi.vcxproj') -Platform $Platform
        Write-Host "[SDK_ABI_REFERENCE] phase=PortableToolchain state=end elapsedMs=$($timer.ElapsedMilliseconds)"
        if($reference.compiler.preferredToolArchitecture -cne $expectedHost.ToLowerInvariant()){throw 'Qualified SDK references require the same native compiler-host selection used by the producer.'}
        $timer.Restart();Write-Host '[SDK_ABI_REFERENCE] phase=ProducerRecipeAfter state=begin'
        $after=& $inputs {param($r,$p) Get-DxUiSdkCacheInputIdentity -Root $r -Platform $p} $SourceRoot $Platform
        Write-Host "[SDK_ABI_REFERENCE] phase=ProducerRecipeAfter state=end elapsedMs=$($timer.ElapsedMilliseconds)"
        if((& $cache {param($i) Get-CiSdkCacheKey $i} $after) -cne $key){throw 'Producer inputs changed while acquiring the portable ABI reference.'}
        Assert-CiSdkProducerCheckouts -Request $request -ToolingRoot $ToolingRoot -SourceRoot $SourceRoot -StorageEngineRoot $StorageEngineRoot
        $receiptStream.Position=0
        $record=[ordered]@{schemaVersion=2;role='QualifiedSdkAbiReference';sourceCommit=$sourceCommit;sourceBytes=$source.contentIdentity;
            apiRevision=$source.apiRevision;platform=$Platform;inputKey=$key;manifestSha256=$entry.ManifestSha256;
            producerTooling=[ordered]@{commit=$producer.toolingRef;contentIdentity=$producer.toolingContentIdentity};
            producerStorageEngine=[ordered]@{commit=$producer.storageEngineRef;contentIdentity=$producer.storageEngineContentIdentity};
            sdkReceiptSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($receiptStream)).ToLowerInvariant();toolchainReference=$reference}
        Assert-CiQualifiedSdkAbiReference $record
    }catch{$primary=$_;throw}
    finally{
        try{
            if($null -ne $entry){
                try{& $cache {param($e) Close-CiSdkCacheEntry $e} $entry}
                catch{if($null -eq $primary){throw}else{Write-Warning ('SDK integrity close also failed: '+$_.Exception.Message)}}
            }
        }
        finally{$receiptStream.Dispose()}
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output))
    $stream=[IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Depth 12));$stream.Write($bytes);$stream.Flush($true)}finally{$stream.Dispose()}
    return $output
}

Export-ModuleMember -Function Write-CiQualifiedSdkAbiReference,Assert-CiQualifiedSdkAbiReference
