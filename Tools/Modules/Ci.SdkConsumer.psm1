# Local pinned dependency input only; hosted producer authentication is a separate admission contract.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkProducer.psm1')

function Read-CiLocalSdkDescriptor {
    param([string]$ProjectRoot,[string]$Descriptor)
    $path=Assert-CiContainedPath $ProjectRoot $Descriptor
    $build=[IO.Path]::GetFullPath((Join-Path $ProjectRoot '.build'))
    $null=Assert-CiContainedPath $build $path
    if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -gt 16KB){throw 'A bounded independently retained local SDK descriptor is required below project .build.'}
    $json=[IO.File]::ReadAllText($path)
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/sdk-consumer-local.schema.json'))){throw 'Invalid local SDK descriptor.'}
    $value=$json|ConvertFrom-Json -AsHashtable
    # A payload cannot authenticate itself by supplying its own mutable descriptor.
    $store=[IO.Path]::GetFullPath($value.storeRoot).TrimEnd('\','/')
    if($path.StartsWith($store+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Keep the independent SDK descriptor outside the mutable store.'}
    return @{Path=$path;Hash=(Get-FileHash -LiteralPath $path).Hash;Value=$value}
}

function Get-CiSdkReaderProcessIdentity {
    param([ValidateRange(1,2147483647)][int]$ProcessId)
    if($IsWindows){return 'windows:'+((Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().Ticks)}
    if($IsLinux){
        # .NET's Linux StartTime conversion can differ between processes. Bind the kernel's exact
        # start-clock token plus boot identity instead of adding a tolerance that could admit PID reuse.
        $stat=[IO.File]::ReadAllText("/proc/$ProcessId/stat")
        $end=$stat.LastIndexOf(')')
        if($end -lt 0){throw 'Cannot read SDK reader process creation identity.'}
        $fields=$stat.Substring($end+2).Split(' ',[StringSplitOptions]::RemoveEmptyEntries)
        if($fields.Length -lt 20 -or $fields[19] -cnotmatch '^[0-9]+$'){throw 'Invalid SDK reader kernel creation token.'}
        return 'linux:'+([IO.File]::ReadAllText('/proc/sys/kernel/random/boot_id').Trim())+':'+$fields[19]
    }
    throw 'SDK reader process identity is unsupported on this operating system.'
}

function New-CiSdkConsumerWitness {
    param([string]$ProjectRoot,[string]$SdkRoot,[string]$Platform)
    $directory=Assert-CiContainedPath $ProjectRoot (Join-Path $ProjectRoot '.build/sdk-leases')
    [void][IO.Directory]::CreateDirectory($directory)
    $path=Assert-CiContainedPath $ProjectRoot (Join-Path $directory ([guid]::NewGuid().ToString('N')+'.json'))
    $record=[ordered]@{schemaVersion=1;ownerPid=$PID;ownerIdentity=(Get-CiSdkReaderProcessIdentity $PID);
        projectRoot=[IO.Path]::GetFullPath($ProjectRoot);sdkRoot=[IO.Path]::GetFullPath($SdkRoot);platform=$Platform;configuration='Release'}
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
    try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Compress));$stream.Write($bytes);$stream.Flush($true)}catch{$stream.Dispose();throw}
    return @{Path=$path;Stream=$stream}
}

function Assert-CiSdkConsumerLease {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$LeasePath,
        [Parameter(Mandatory)][string]$SdkRoot,[Parameter(Mandatory)][string]$Platform,[Parameter(Mandatory)][string]$Configuration)
    $directory=Assert-CiContainedPath $ProjectRoot (Join-Path $ProjectRoot '.build/sdk-leases')
    $path=Assert-CiContainedPath $directory $LeasePath
    if($Configuration -cne 'Release' -or -not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item $path).Length -gt 4KB){throw 'SDK compilation requires an active Release reader owner.'}
    $witness=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if($witness.schemaVersion -ne 1 -or $witness.projectRoot -cne [IO.Path]::GetFullPath($ProjectRoot) -or
        $witness.sdkRoot -cne [IO.Path]::GetFullPath($SdkRoot) -or $witness.platform -cne $Platform -or $witness.configuration -cne $Configuration){throw 'SDK reader witness has another project, payload or profile.'}
    if((Get-CiSdkReaderProcessIdentity $witness.ownerPid) -cne $witness.ownerIdentity){throw 'SDK reader owner is stale.'}
    # A surviving JSON file and a recycled/live PID are insufficient: the parent must still hold its handle.
    $exclusive=$null
    try{$exclusive=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{return}
    finally{if($null -ne $exclusive){$exclusive.Dispose()}}
    throw 'SDK reader lease is closed; direct/stale MSBuild use is refused.'
}

function Open-CiPinnedSdkInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$Descriptor,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedSourceCommit,
        [Parameter(Mandatory)][int]$ExpectedApiRevision,[Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,
        [Parameter(Mandatory)][string]$Configuration)
    if($Configuration -cne 'Release'){throw 'Pinned SDK v1 supports Release only; use the existing source recipe for other profiles.'}
    $descriptorState=Read-CiLocalSdkDescriptor $ProjectRoot $Descriptor
    $d=$descriptorState.Value
    if($d.sourceCommit -cne $ExpectedSourceCommit -or $d.apiRevision -ne $ExpectedApiRevision -or $d.platform -cne $Platform){throw 'SDK descriptor cannot advance the application lock or change its selected profile.'}
    foreach($name in @('sourceRoot','toolingRoot','storageEngineRoot','storeRoot')){if(-not [IO.Path]::IsPathFullyQualified($d[$name])){throw 'SDK descriptor roots must be explicit absolute paths.'}}
    $policy=Read-CiSdkProducerPolicy
    $source=@($policy.sources|Where-Object{$_.commit -ceq $ExpectedSourceCommit -and $_.apiRevision -eq $ExpectedApiRevision})
    if($source.Count -ne 1){throw 'SDK source/API is outside the reviewed pinned producer policy.'}
    $request=@{sourceCommit=$ExpectedSourceCommit;apiRevision=$ExpectedApiRevision;sourceContentIdentity=$source[0].contentIdentity;
        toolingRef=$policy.toolingRef;toolingContentIdentity=$policy.toolingContentIdentity;storageEngineRef=$policy.storageEngineRef;storageEngineContentIdentity=$policy.storageEngineContentIdentity}
    Assert-CiSdkProducerCheckouts -Request $request -ToolingRoot $d.toolingRoot -SourceRoot $d.sourceRoot -StorageEngineRoot $d.storageEngineRoot
    $sdk=Import-Module (Join-Path $d.toolingRoot 'Tools/SdkInputStore.psm1') -PassThru
    $reader=& $sdk {param($r,$p,$s,$h,$e) Open-DxUiSdkInputBytes -Root $r -Platform $p -StoreRoot $s -ManifestSha256 $h -EngineRoot $e} $d.sourceRoot $Platform $d.storeRoot $d.manifestSha256 $d.storageEngineRoot
    if($null -eq $reader){return $null}
    try{
        $witness=New-CiSdkConsumerWitness $ProjectRoot $reader.SdkRoot $Platform
        return [pscustomobject]@{Reader=$reader;Module=$sdk;Witness=$witness;Descriptor=$descriptorState;Closed=$false;
            StorageEngineRoot=$d.storageEngineRoot;StorageEngineIdentity=$policy.storageEngineContentIdentity;
            SdkRoot=$reader.SdkRoot;LeasePath=$witness.Path;
            Evidence=[ordered]@{recipe='PinnedReleaseSdkV1';inputKey=$reader.Entry.Key;manifestSha256=$reader.Entry.ManifestSha256;identity=$reader.Identity;
                storageEngineRef=$policy.storageEngineRef;storageEngineBytes=$policy.storageEngineContentIdentity}}
    }catch{
        $primary=$_
        try{& $sdk {param($r) Close-DxUiSdkInputBytes $r} $reader}catch{Write-Warning ('SDK close also failed: '+$_.Exception.Message)}
        throw $primary
    }
}

function Close-CiPinnedSdkInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputBytes)
    if($InputBytes.Closed){throw 'SDK input was already closed.'}
    $primary=$null
    try{
        if((Get-FileHash -LiteralPath $InputBytes.Descriptor.Path).Hash -cne $InputBytes.Descriptor.Hash){throw 'Independent SDK descriptor changed during the build.'}
        if((Get-CiSdkCheckoutContentIdentity $InputBytes.StorageEngineRoot) -cne $InputBytes.StorageEngineIdentity){throw 'SDK storage engine changed during the build.'}
    }catch{$primary=$_}
    try{& $InputBytes.Module {param($r) Close-DxUiSdkInputBytes $r} $InputBytes.Reader}
    catch{if($null -eq $primary){$primary=$_}else{Write-Warning ('SDK integrity close also failed: '+$_.Exception.Message)}}
    finally{$InputBytes.Witness.Stream.Dispose();$InputBytes.Closed=$true}
    if($null -ne $primary){throw $primary}
}

Export-ModuleMember -Function Open-CiPinnedSdkInput,Close-CiPinnedSdkInput,Assert-CiSdkConsumerLease
