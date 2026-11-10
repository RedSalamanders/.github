# Authenticated dependency bytes and their producer ABI reference only.
# Consumer compatibility, native tests and product acceptance are separate.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkProducer.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkQualifiedProducer.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkCache.psm1')
$script:sdkTransport=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkTransport.psm1') -PassThru

function Resolve-CiQualifiedSdkArtifactEnvelope {
    param([string]$RunId,[int]$Attempt,[string]$SourceCommit,[string]$Platform)
    Resolve-CiHostedSdkArtifact -RunId $RunId -Attempt $Attempt -SourceCommit $SourceCommit -Platform $Platform -Contract QualifiedAbiV2
}

function Assert-CiQualifiedSdkBinding {
    param([Collections.IDictionary]$Entry,[Collections.IDictionary]$Reference,[string]$ManifestSha256,
        [string]$SourceCommit,[int]$ApiRevision,[string]$Platform)
    Assert-CiQualifiedSdkAbiReference $Reference
    $policy=Read-CiSdkProducerPolicy
    $sources=@($policy.sources|Where-Object {$_.commit -ceq $SourceCommit -and $_.apiRevision -eq $ApiRevision})
    if($sources.Count -ne 1){throw 'Qualified SDK source/API is outside the reviewed producer policy.'}
    $source=$sources[0]
    $key=Get-CiSdkCacheKey $Entry.identity
    if($Entry.key -cne $key -or $Reference.inputKey -cne $key -or $Reference.manifestSha256 -cne $ManifestSha256){throw 'Qualified SDK reference does not bind the original entry key and manifest.'}
    foreach($data in @($Entry.identity,$Reference)){
        if($data.sourceCommit -cne $SourceCommit -or $data.sourceBytes -cne $source.contentIdentity -or
            $data.apiRevision -ne $ApiRevision -or $data.platform -cne $Platform){throw 'Qualified SDK source/API/architecture bytes do not match the requested pin.'}
    }
    if($Reference.producerTooling.commit -cne $policy.toolingRef -or $Reference.producerTooling.contentIdentity -cne $policy.toolingContentIdentity -or
        $Reference.producerStorageEngine.commit -cne $policy.storageEngineRef -or $Reference.producerStorageEngine.contentIdentity -cne $policy.storageEngineContentIdentity){throw 'Qualified SDK used another producer tooling or storage policy.'}
    $tooling=[ordered]@{repository='RedSalamanders/DxUi';commit=$policy.toolingRef;contentIdentity=$policy.toolingContentIdentity}
    $integration=Get-CiSha256 ('dxui-sdk-input-policy-v1'+"`n"+($tooling|ConvertTo-Json -Compress))
    $identity=$Entry.identity
    if($identity.sourceRepository -cne 'RedSalamanders/DxUi' -or $identity.configuration -cne 'Release' -or $identity.runtimeFamily -cne 'MD' -or
        $identity.annotationPolicy -cne 'enabled' -or $identity.languageStandard -cne 'stdcpplatest' -or $identity.optimizationPolicy -cne 'GL-LTCG-full' -or
        $identity.integrationPolicyIdentity -cne $integration){throw 'Qualified SDK changed its supported original ABI or integration policy.'}
}

function Read-CiQualifiedSdkArchiveBinding {
    param([string]$Archive,[Collections.IDictionary]$Envelope,[string]$EntryPath,[string]$ReferencePath,[string]$ReceiptPath,
        [string]$SourceCommit,[int]$ApiRevision,[string]$Platform)
    # The caller independently resolves this envelope through the reviewed policy;
    # a local descriptor's JSON is never an envelope authority.
    if($Envelope.schemaVersion -ne 2 -or $Envelope.role -cne 'HostedQualifiedSdkEnvelope' -or $Envelope.contract -cne 'QualifiedAbiV2' -or
        $Envelope.sourceCommit -cne $SourceCommit -or $Envelope.platform -cne $Platform){throw 'Qualified SDK archive requires its independently authenticated v2 envelope.'}
    $records=@(& $script:sdkTransport {param($a,$e,$p) Read-CiSdkArchiveJson $a $e $p} $Archive $Envelope @($EntryPath,$ReferencePath,$ReceiptPath))
    if($records.Count -ne 3){throw 'Qualified SDK archive must retain one exact entry, ABI reference and native SDK receipt.'}
    $entryRecord=@($records|Where-Object path -CEQ $EntryPath)
    $abiRecord=@($records|Where-Object path -CEQ $ReferencePath)
    $receiptRecord=@($records|Where-Object path -CEQ $ReceiptPath)
    if($entryRecord.Count -ne 1 -or $abiRecord.Count -ne 1 -or $receiptRecord.Count -ne 1){throw 'Qualified SDK archive references are ambiguous.'}
    if(-not(Test-Json -Json $entryRecord[0].json -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/sdk-cache-entry.schema.json'))){throw 'Invalid qualified SDK entry manifest.'}
    $entry=$entryRecord[0].json|ConvertFrom-Json -AsHashtable
    $reference=$abiRecord[0].json|ConvertFrom-Json -AsHashtable
    Assert-CiQualifiedSdkBinding $entry $reference $entryRecord[0].sha256 $SourceCommit $ApiRevision $Platform
    $receipt=$receiptRecord[0].json|ConvertFrom-Json -AsHashtable
    Assert-CiQualifiedSdkReceipt $receipt $SourceCommit $ApiRevision $Platform ('0.1.'+$Envelope.runId)
    if($receiptRecord[0].sha256 -cne $reference.sdkReceiptSha256 -or $receipt.sdkStoreInputKey -cne $entry.key -or
        $receipt.sdkStoreManifestSha256 -cne $entryRecord[0].sha256){throw 'Qualified SDK native receipt does not bind its original key, manifest and ABI reference.'}
    return [pscustomobject]@{Identity=$entry.identity;Entry=$entry;ManifestSha256=$entryRecord[0].sha256;Reference=$reference;
        ReferenceSha256=$abiRecord[0].sha256;ReceiptSha256=$receiptRecord[0].sha256}
}

function Import-CiQualifiedHostedSdkArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$DownloadRoot,[Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$SourceCommit,
        [Parameter(Mandatory)][ValidateRange(1,65535)][int]$ApiRevision,[Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,
        [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
        [Parameter(Mandatory)][ValidateRange(1,100000)][int]$Attempt)
    $envelope=Resolve-CiQualifiedSdkArtifactEnvelope $RunId $Attempt $SourceCommit $Platform
    $owned=Assert-CiContainedPath (Join-Path $RepositoryRoot '.build') $DownloadRoot
    $directory=Assert-CiContainedPath $owned (Join-Path $owned ([guid]::NewGuid().ToString('N')))
    [void][IO.Directory]::CreateDirectory($directory)
    [IO.File]::WriteAllText((Join-Path $directory 'authenticated-envelope.json'),($envelope|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $archive=Join-Path $directory 'artifact.zip'
    & $script:sdkTransport {param($e,$p) Receive-CiSdkArchive $e $p} $envelope $archive
    $expanded=Join-Path $directory 'expanded';[void][IO.Directory]::CreateDirectory($expanded)
    $catalog=@(& $script:sdkTransport {param($a,$d,$e) Expand-CiSdkArchive $a $d $e} $archive $expanded $envelope)
    $entries=@(Get-ChildItem -LiteralPath $expanded -Filter entry.json -Recurse -File)
    $references=@(Get-ChildItem -LiteralPath $expanded -Filter abi-reference.json -Recurse -File)
    $receipts=@(Get-ChildItem -LiteralPath $expanded -Filter 'DxUi-SDK-*.zip.receipt.json' -Recurse -File)
    if($entries.Count -ne 1 -or $references.Count -ne 1 -or $receipts.Count -ne 1){throw 'Qualified SDK artifact requires exactly one immutable entry, ABI reference and native SDK receipt.'}
    $entry=$entries[0];$reference=$references[0]
    $entryPath=[IO.Path]::GetRelativePath($expanded,$entry.FullName).Replace('\','/')
    $referencePath=[IO.Path]::GetRelativePath($expanded,$reference.FullName).Replace('\','/')
    $receiptPath=[IO.Path]::GetRelativePath($expanded,$receipts[0].FullName).Replace('\','/')
    $binding=Read-CiQualifiedSdkArchiveBinding $archive $envelope $entryPath $referencePath $receiptPath $SourceCommit $ApiRevision $Platform
    if($catalog.Count -ne 1 -or $catalog[0].path -cne $entryPath -or $catalog[0].sha256 -cne $binding.ManifestSha256 -or
        (Get-FileHash -LiteralPath $entry.FullName).Hash.ToLowerInvariant() -cne $binding.ManifestSha256 -or
        (Get-FileHash -LiteralPath $reference.FullName).Hash.ToLowerInvariant() -cne $binding.ReferenceSha256 -or
        (Get-FileHash -LiteralPath $receipts[0].FullName).Hash.ToLowerInvariant() -cne $binding.ReceiptSha256){throw 'Extracted qualified SDK binding changed after authenticated acquisition.'}
    $key=Get-CiSdkCacheKey $binding.Identity
    $marker=Join-Path (Split-Path -Parent $entry.DirectoryName) 'input-key.txt'
    if(-not [IO.File]::Exists($marker) -or [IO.File]::ReadAllText($marker) -cne $key -or
        (Split-Path -Leaf $entry.DirectoryName) -cne $binding.ManifestSha256.Substring(0,16) -or
        (Split-Path -Leaf (Split-Path -Parent $entry.DirectoryName)) -cne $key.Substring(0,16)){throw 'Qualified SDK locator does not bind its original key/manifest.'}
    $after=Resolve-CiQualifiedSdkArtifactEnvelope $RunId $Attempt $SourceCommit $Platform
    if(($after|ConvertTo-Json -Compress) -cne ($envelope|ConvertTo-Json -Compress)){throw 'Qualified SDK artifact provenance changed during transport.'}
    Initialize-CiSdkStore -RepositoryRoot $RepositoryRoot -StoreRoot $StoreRoot
    $result=Import-CiSdkCacheEntry -StoreRoot $StoreRoot -Identity $binding.Identity -EntryRoot $entry.DirectoryName -ManifestSha256 $binding.ManifestSha256
    [IO.File]::WriteAllText((Join-Path $directory 'import.json'),([ordered]@{role='QualifiedDependencyBytesImported';key=$result.Key;manifestSha256=$result.ManifestSha256;
        referenceSha256=$binding.ReferenceSha256;toolchainReference=$binding.Reference.toolchainReference.digest;envelope=$envelope}|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{Entry=$result;Reference=$binding.Reference;Envelope=$envelope;ArchivePath=$archive;EntryPath=$entryPath;ReferencePath=$referencePath;ReceiptPath=$receiptPath;Identity=$binding.Identity}
}

Export-ModuleMember -Function Import-CiQualifiedHostedSdkArtifact
