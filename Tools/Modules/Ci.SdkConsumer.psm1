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
    $value=$json|ConvertFrom-Json -AsHashtable
    $schema=if($value.role -ceq 'HostedQualifiedDependencyInput'){'sdk-consumer-qualified.schema.json'}else{'sdk-consumer-local.schema.json'}
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot ('../../Schemas/'+$schema)))){throw 'Invalid local SDK descriptor.'}
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
    param([string]$ProjectRoot,[string]$SdkRoot,[string]$Platform,[Collections.IDictionary]$ToolBinding=$null)
    $directory=Assert-CiContainedPath $ProjectRoot (Join-Path $ProjectRoot '.build/sdk-leases')
    [void][IO.Directory]::CreateDirectory($directory)
    $path=Assert-CiContainedPath $ProjectRoot (Join-Path $directory ([guid]::NewGuid().ToString('N')+'.json'))
    $record=[ordered]@{schemaVersion=1;ownerPid=$PID;ownerIdentity=(Get-CiSdkReaderProcessIdentity $PID);
        projectRoot=[IO.Path]::GetFullPath($ProjectRoot);sdkRoot=[IO.Path]::GetFullPath($SdkRoot);platform=$Platform;configuration='Release'}
    if($null -ne $ToolBinding){$record.schemaVersion=2;$record.contract='QualifiedAbiV2';$record.toolBinding=$ToolBinding}
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
    try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Compress));$stream.Write($bytes);$stream.Flush($true)}catch{$stream.Dispose();throw}
    return @{Path=$path;Stream=$stream}
}

function Assert-CiSdkConsumerLease {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$LeasePath,
        [Parameter(Mandatory)][string]$SdkRoot,[Parameter(Mandatory)][string]$Platform,[Parameter(Mandatory)][string]$Configuration,
        [string]$SdkContract='',[string]$ToolPropertyFile='')
    $directory=Assert-CiContainedPath $ProjectRoot (Join-Path $ProjectRoot '.build/sdk-leases')
    $path=Assert-CiContainedPath $directory $LeasePath
    if($Configuration -cne 'Release' -or -not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item $path).Length -gt 16KB){throw 'SDK compilation requires an active Release reader owner.'}
    $witness=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if($witness.schemaVersion -notin @(1,2) -or $witness.projectRoot -cne [IO.Path]::GetFullPath($ProjectRoot) -or
        $witness.sdkRoot -cne [IO.Path]::GetFullPath($SdkRoot) -or $witness.platform -cne $Platform -or $witness.configuration -cne $Configuration){throw 'SDK reader witness has another project, payload or profile.'}
    if((Get-CiSdkReaderProcessIdentity $witness.ownerPid) -cne $witness.ownerIdentity){throw 'SDK reader owner is stale.'}
    # A surviving JSON file and a recycled/live PID are insufficient: the parent must still hold its handle.
    $exclusive=$null
    $held=$false
    try{$exclusive=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{$held=$true}
    finally{if($null -ne $exclusive){$exclusive.Dispose()}}
    if(-not $held){throw 'SDK reader lease is closed; direct/stale MSBuild use is refused.'}
    if($witness.schemaVersion -eq 2){
        if($witness.contract -cne 'QualifiedAbiV2' -or $SdkContract -cne 'QualifiedAbiV2'){throw 'Qualified SDK compilation requires its actual v2 contract.'}
        $abi=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkAbi.psm1') -PassThru
        $propertyPath=Assert-CiContainedPath (Join-Path $ProjectRoot '.build') $ToolPropertyFile
        if(-not [IO.File]::Exists($propertyPath) -or (Get-Item -LiteralPath $propertyPath).Length -gt 16KB){throw 'Qualified SDK compilation requires bounded actual tool properties.'}
        $actual=@{}
        foreach($line in [IO.File]::ReadAllLines($propertyPath,[Text.UTF8Encoding]::new($false,$true))){
            $parts=$line.Split('=',2)
            if($parts.Count -ne 2 -or $parts[0] -cnotmatch '^[A-Za-z][A-Za-z0-9]*$' -or $actual.ContainsKey($parts[0])){throw 'Invalid or duplicate SDK tool property.'}
            $actual[$parts[0]]=$parts[1]
        }
        $expected=@{};foreach($property in $witness.toolBinding.PSObject.Properties){$expected[$property.Name]=[string]$property.Value}
        Assert-CiSdkToolBinding $expected $actual
        & $abi {param($p) Assert-CiSdkAbiCompilerEnvironment -MSBuildSearchPaths $p} $expected
    }elseif($witness.schemaVersion -ne 1 -or $SdkContract){throw 'Unsupported SDK reader contract.'}
}

function Assert-CiSdkToolBinding {
    param([Collections.IDictionary]$Expected,[Collections.IDictionary]$Actual)
    foreach($name in @('IncludePath','LibraryPath','ReferencePath')){
        if(-not $Expected.Contains($name) -or -not $Actual.Contains($name) -or
            $Expected[$name] -match '[|%\r\n]' -or $Actual[$name] -cne ([string]$Expected[$name]).Replace(';','|')){
            throw "Qualified SDK actual compiler search property differs: $name."
        }
    }
    foreach($name in @('PlatformToolset','VCToolsVersion','WindowsTargetPlatformVersion','PreferredToolArchitecture','VCToolArchitecture','WindowsSDKToolArchitecture')){
        if(-not $Actual.Contains($name) -or $Actual[$name] -cne $Expected[$name]){throw "Qualified SDK actual compiler selection differs: $name."}
    }
    foreach($name in @('VCToolsInstallDir','WindowsSdkDir','VCTargetsPath','MSBuildBinPath')){
        if(-not $Actual.Contains($name) -or -not [IO.Path]::IsPathFullyQualified([string]$Actual[$name]) -or
            -not [IO.Path]::GetFullPath([string]$Actual[$name]).TrimEnd('\','/').Equals([IO.Path]::GetFullPath([string]$Expected[$name]).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)){
            throw "Qualified SDK actual tool root differs: $name."
        }
    }
    foreach($prefix in @('CL','Link','Lib')){
        foreach($suffix in @('ToolPath','ToolExe','ToolArchitecture')){
            $name=$prefix+$suffix
            if(-not $Actual.Contains($name)){throw "Qualified SDK actual tool properties omit $name."}
            $value=[string]$Actual[$name]
            if(-not $value){continue}
            $wanted=switch($suffix){ToolPath{[IO.Path]::GetDirectoryName($Expected[$prefix])};ToolExe{[IO.Path]::GetFileName($Expected[$prefix])};ToolArchitecture{$Expected.VCToolArchitecture}}
            $same=if($suffix -ceq 'ToolPath'){
                [IO.Path]::IsPathFullyQualified($value) -and [IO.Path]::GetFullPath($value).TrimEnd('\','/').Equals([IO.Path]::GetFullPath($wanted).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)
            }else{$value.Equals($wanted,[StringComparison]::OrdinalIgnoreCase)}
            if(-not $same){throw "Qualified SDK actual tool override differs: $name."}
        }
    }
    foreach($name in @('FXCToolPath','FxCompileToolExe','FxCompileToolArchitecture','MultiProcFXC')){if(-not $Actual.Contains($name)){throw "Qualified SDK actual tool properties omit $name."}}
    if($Actual.FxCompileToolExe -or $Actual.MultiProcFXC -ceq 'true' -or
        ($Actual.FxCompileToolArchitecture -and $Actual.FxCompileToolArchitecture -cne $Expected.WindowsSDKToolArchitecture)){throw 'Qualified SDK actual shader tool policy differs.'}
    if($Actual.FXCToolPath -and (-not [IO.Path]::IsPathFullyQualified($Actual.FXCToolPath) -or
        -not [IO.Path]::GetFullPath($Actual.FXCToolPath).TrimEnd('\','/').Equals([IO.Path]::GetDirectoryName($Expected.FXC).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase))){throw 'Qualified SDK actual shader tool root differs.'}
}

function Read-CiApplicationSdkLock {
    param([string]$ProjectRoot,[string]$ControllerRoot)
    $project=Read-CiProject $ProjectRoot
    if($project.kind -cne 'application' -or (Resolve-CiCommit $ControllerRoot HEAD) -cne $project.engine.ref -or
        (Invoke-CiGit $ControllerRoot @('status','--porcelain','--untracked-files=all')).stdout.Trim()){
        throw 'Application SDK use requires its exact clean pinned shared engine.'
    }
    $path=Assert-CiContainedPath $ProjectRoot (Join-Path $ProjectRoot 'Dependencies/DxUi.lock.json')
    $lock=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if($lock.repository -cne 'https://github.com/RedSalamanders/DxUi' -or $lock.commit -isnot [string] -or
        $lock.commit -cnotmatch '^[a-f0-9]{40}$' -or ($lock.apiRevision -isnot [long] -and $lock.apiRevision -isnot [int]) -or
        $lock.apiRevision -lt 1 -or $lock.apiRevision -gt 65535 -or @($lock.targets).Count -ne 1 -or $lock.targets[0] -cne 'DxUi'){
        throw 'Application SDK use requires its unchanged exact DxUi source/API/target lock.'
    }
    return $lock
}

function Open-CiApplicationSdkInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$Descriptor,
        [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,[Parameter(Mandatory)][string]$Configuration,[string]$MSBuildPath='')
    $controller=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $lock=Read-CiApplicationSdkLock $ProjectRoot $controller
    return Open-CiPinnedSdkInput -ProjectRoot $ProjectRoot -Descriptor $Descriptor -ExpectedSourceCommit $lock.commit `
        -ExpectedApiRevision $lock.apiRevision -Platform $Platform -Configuration $Configuration -MSBuildPath $MSBuildPath
}

function Open-CiPinnedSdkInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$Descriptor,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedSourceCommit,
        [Parameter(Mandatory)][int]$ExpectedApiRevision,[Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,
        [Parameter(Mandatory)][string]$Configuration,[string]$MSBuildPath='')
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
    if($d.role -ceq 'HostedQualifiedDependencyInput'){
        return Open-CiQualifiedPinnedSdkInput -ProjectRoot $ProjectRoot -DescriptorState $descriptorState -Request $request -Policy $policy -MSBuildPath $MSBuildPath
    }
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

function Open-CiQualifiedPinnedSdkInput {
    param([string]$ProjectRoot,[Collections.IDictionary]$DescriptorState,[Collections.IDictionary]$Request,
        [Collections.IDictionary]$Policy,[string]$MSBuildPath)
    $d=$DescriptorState.Value
    if(-not [IO.Path]::IsPathFullyQualified($MSBuildPath) -or -not [IO.File]::Exists($MSBuildPath)){throw 'Qualified SDK use requires the application-selected MSBuild executable.'}
    if(-not [IO.Path]::IsPathFullyQualified($d.archivePath)){throw 'Qualified SDK archives require an explicit absolute owned path.'}
    $archive=Assert-CiContainedPath (Join-Path $ProjectRoot '.build') $d.archivePath
    $qualified=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkQualifiedTransport.psm1') -PassThru
    $abi=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkAbi.psm1') -PassThru
    $envelope=& $qualified {param($d) Resolve-CiQualifiedSdkArtifactEnvelope $d.producerRun $d.attempt $d.sourceCommit $d.platform} $d
    $binding=& $qualified {param($a,$e,$d) Read-CiQualifiedSdkArchiveBinding $a $e $d.entryPath $d.referencePath $d.receiptPath $d.sourceCommit $d.apiRevision $d.platform} $archive $envelope $d
    if($binding.ManifestSha256 -cne $d.manifestSha256){throw 'Qualified SDK descriptor changed its original authenticated manifest.'}
    # Applications select their native compiler host by default. Older pinned
    # producer projects have a different default; evaluate the actual requested
    # host explicitly, then require every real project to match its live binding.
    $toolHost=[Environment]::GetEnvironmentVariable('PreferredToolArchitecture','Process')
    if(-not $toolHost){$toolHost=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()}
    $state=Get-CiSdkAbiReference -ToolingRoot $d.toolingRoot -MSBuildPath $MSBuildPath -ProjectPath (Join-Path $d.sourceRoot 'src/DxUi.vcxproj') -Platform $d.platform -PassThruBinding -PreferredToolArchitecture $toolHost
    if($state.Reference.digest -cne $binding.Reference.toolchainReference.digest){
        Write-Host 'Qualified SDK tool/header/library bytes differ from the actual consumer toolchain; retaining source fallback.'
        return $null
    }
    $cache=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkCache.psm1') -PassThru
    $entry=& $cache {param($s,$i,$h) Open-CiSdkCacheEntry -StoreRoot $s -Identity $i -ManifestSha256 $h} $d.storeRoot $binding.Identity $binding.ManifestSha256
    if($null -eq $entry){return $null}
    $witness=$null
    try{
        $payload=Import-Module (Join-Path $d.toolingRoot 'Tools/SdkInputStore.psm1') -PassThru
        & $payload {param($p,$i,$e) Assert-DxUiSdkInputPayload $p $i $e} $entry.Payload $binding.Identity $cache
        $toolBinding=[ordered]@{}
        foreach($name in @('PlatformToolset','VCToolsInstallDir','VCToolsVersion','WindowsSdkDir','WindowsTargetPlatformVersion','PreferredToolArchitecture','VCTargetsPath','VCToolArchitecture','WindowsSDKToolArchitecture','IncludePath','LibraryPath','ReferencePath')){$toolBinding[$name]=[string]$state.Properties[$name]}
        $toolBinding.MSBuildBinPath=[IO.Path]::GetDirectoryName($MSBuildPath)
        foreach($name in @('CL','Link','Lib','FXC')){$toolBinding[$name]=[string]$state.SelectedTools[$name]}
        $witness=New-CiSdkConsumerWitness $ProjectRoot $entry.Payload $d.platform $toolBinding
        $controller=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $controllerBytes=Get-CiSdkCheckoutContentIdentity $controller
        $reader=[pscustomobject]@{Entry=$entry;Cache=$cache;Qualified=$qualified;Abi=$abi;Envelope=$envelope;Binding=$binding;Request=$Request;
            MSBuildPath=$MSBuildPath;PreferredToolArchitecture=$toolHost;Reference=$state.Reference;SourceRoots=$d;Closed=$false}
        return [pscustomobject]@{Reader=$reader;Witness=$witness;Descriptor=$DescriptorState;Closed=$false;SdkRoot=$entry.Payload;LeasePath=$witness.Path;
            StorageEngineRoot=$controller;StorageEngineIdentity=$controllerBytes;
            Evidence=[ordered]@{recipe='PinnedQualifiedReleaseSdkV2';inputKey=$entry.Key;manifestSha256=$entry.ManifestSha256;identity=$binding.Identity;
                toolchainReference=$state.Reference.digest;producerRun=$d.producerRun;attempt=$d.attempt;archiveSha256=$envelope.archiveSha256;
                publicHeadersGitTree=$binding.Reference.publicHeadersGitTree;storageEngineRef=(Resolve-CiCommit $controller HEAD);storageEngineBytes=$controllerBytes}}
    }catch{
        $primary=$_
        if($null -ne $witness){$witness.Stream.Dispose()}
        try{& $cache {param($e) Close-CiSdkCacheEntry $e} $entry}catch{Write-Warning ('Qualified SDK close also failed: '+$_.Exception.Message)}
        throw $primary
    }
}

function Close-CiQualifiedPinnedSdkReader {
    param($Reader)
    $failure=$null
    try{
        $d=$Reader.SourceRoots
        $envelope=& $Reader.Qualified {param($d) Resolve-CiQualifiedSdkArtifactEnvelope $d.producerRun $d.attempt $d.sourceCommit $d.platform} $d
        if(($envelope|ConvertTo-Json -Compress) -cne ($Reader.Envelope|ConvertTo-Json -Compress)){throw 'Qualified SDK producer provenance changed during use.'}
        $binding=& $Reader.Qualified {param($a,$e,$d) Read-CiQualifiedSdkArchiveBinding $a $e $d.entryPath $d.referencePath $d.receiptPath $d.sourceCommit $d.apiRevision $d.platform} $d.archivePath $envelope $d
        if($binding.ManifestSha256 -cne $Reader.Binding.ManifestSha256 -or $binding.ReferenceSha256 -cne $Reader.Binding.ReferenceSha256){throw 'Qualified SDK original archive binding changed during use.'}
        $reference=& $Reader.Abi {param($d,$m,$h) Get-CiSdkAbiReference -ToolingRoot $d.toolingRoot -MSBuildPath $m -ProjectPath (Join-Path $d.sourceRoot 'src/DxUi.vcxproj') -Platform $d.platform -PreferredToolArchitecture $h} $d $Reader.MSBuildPath $Reader.PreferredToolArchitecture
        if($reference.digest -cne $Reader.Reference.digest){throw 'Qualified SDK consumer tool/header/library bytes changed during use.'}
        Assert-CiSdkProducerCheckouts -Request $Reader.Request -ToolingRoot $d.toolingRoot -SourceRoot $d.sourceRoot -StorageEngineRoot $d.storageEngineRoot
    }catch{$failure=$_}
    finally{
        try{& $Reader.Cache {param($e) Close-CiSdkCacheEntry $e} $Reader.Entry}
        catch{if($null -eq $failure){$failure=$_}else{Write-Warning ('Qualified SDK integrity close also failed: '+$_.Exception.Message)}}
        finally{$Reader.Closed=$true}
    }
    if($null -ne $failure){throw $failure}
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
    try{
        if($InputBytes.Evidence.recipe -ceq 'PinnedQualifiedReleaseSdkV2'){Close-CiQualifiedPinnedSdkReader $InputBytes.Reader}
        else{& $InputBytes.Module {param($r) Close-DxUiSdkInputBytes $r} $InputBytes.Reader}
    }
    catch{if($null -eq $primary){$primary=$_}else{Write-Warning ('SDK integrity close also failed: '+$_.Exception.Message)}}
    finally{$InputBytes.Witness.Stream.Dispose();$InputBytes.Closed=$true}
    if($null -ne $primary){throw $primary}
}

Export-ModuleMember -Function Open-CiApplicationSdkInput,Open-CiPinnedSdkInput,Close-CiPinnedSdkInput,Assert-CiSdkConsumerLease
