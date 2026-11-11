# Explicit local dependency admission. No build, test or qualification result is produced.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SourceInputs.psm1')
$script:descriptors=Import-Module (Join-Path $PSScriptRoot 'Ci.LocalSdkDescriptor.psm1') -PassThru
$script:consumer=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkConsumer.psm1') -PassThru
$script:abi=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkAbi.psm1') -PassThru

function Assert-CiLocalConsumerProducer {
    param($Descriptor)
    $record=$Descriptor.Record
    foreach($relative in @('include/DxUi/DxUi.h','DxUi.Sdk.props','build/NativeBuildPolicy.targets')){
        if(-not [IO.File]::Exists((Join-Path $Descriptor.Snapshot.Payload $relative))){throw 'Local SDK consumer payload is missing its canonical public interface or integration policy.'}
    }
    # The descriptor reader authenticates the complete toolkit before this import.
    $libraryModule=Import-Module (Join-Path $record.toolingBootstrap.root 'Tools/SdkLibraryInputs.psm1') -PassThru
    $current=& $libraryModule {param($r,$p) Assert-DxUiSdkLibraryBuild -Root $r -Platform $p} $record.identity.producerRoot $record.identity.inputs.platform
    $path=Join-Path $Descriptor.Snapshot.Payload 'provenance/library-inputs.json'
    if(-not [IO.File]::Exists($path) -or (Get-Item -LiteralPath $path).Length -gt 8MB){throw 'Local SDK consumer requires bounded original library build provenance.'}
    $captured=[IO.File]::ReadAllText($path)|ConvertFrom-Json -AsHashtable
    if(($current|ConvertTo-Json -Depth 14 -Compress) -cne ($captured|ConvertTo-Json -Depth 14 -Compress)){
        throw 'Local SDK producer build provenance changed after capture.'
    }
    foreach($name in @('DxUi.lib','DxUi.pdb')){
        $files=@($captured.files|Where-Object path -ceq $name)
        $payload=Join-Path $Descriptor.Snapshot.Payload ("lib/$($record.identity.inputs.platform)/Release/"+$name)
        if($files.Count -ne 1 -or -not [IO.File]::Exists($payload) -or
            (Get-FileHash -LiteralPath $payload).Hash.ToLowerInvariant() -cne $files[0].sha256){
            throw 'Local SDK library or compiler symbols differ from original build provenance.'
        }
    }
}

function Get-CiLocalConsumerAbi {
    param($Descriptor,[string]$MSBuildPath)
    $record=$Descriptor.Record
    $path=Join-Path $Descriptor.Snapshot.Payload 'provenance/toolchain-reference.json'
    if(-not [IO.File]::Exists($path) -or (Get-Item -LiteralPath $path).Length -gt 64MB){throw 'Local SDK consumer requires bounded original ABI provenance.'}
    $reference=[IO.File]::ReadAllText($path)|ConvertFrom-Json -AsHashtable
    & $script:abi {param($r) Assert-CiSdkAbiReference $r} $reference
    $hostTool=[Environment]::GetEnvironmentVariable('PreferredToolArchitecture','Process')
    if(-not $hostTool){$hostTool=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()}
    $actual=& $script:abi {param($t,$m,$p,$a,$h)
        Get-CiSdkAbiReference -ToolingRoot $t -MSBuildPath $m -ProjectPath $p -Platform $a -PreferredToolArchitecture $h -PassThruBinding
    } $record.toolingBootstrap.root $MSBuildPath (Join-Path $record.identity.producerRoot 'src/DxUi.vcxproj') $record.identity.inputs.platform $hostTool
    if($actual.Reference.digest -cne $reference.digest){throw 'Local SDK ABI differs from the actual selected consumer toolchain.'}
    return $actual
}

function Open-CiLocalSdkConsumerInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$Descriptor,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedDescriptorSha256,
        [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,
        [Parameter(Mandatory)][string]$Configuration,[Parameter(Mandatory)][string]$MSBuildPath)
    if($env:GITHUB_ACTIONS -ceq 'true'){throw 'Local unpinned SDK consumer inputs are unavailable to hosted qualification and publication.'}
    if($env:CI_NATIVE_BUILDS_DISABLED -ceq 'true'){throw 'Local SDK ABI admission is forbidden in compiler-free execution.'}
    if($Configuration -cne 'Release'){throw 'Local unpinned SDK consumer inputs require Release; other profiles retain source.'}
    if(-not [IO.Path]::IsPathFullyQualified($MSBuildPath) -or -not [IO.File]::Exists($MSBuildPath)){throw 'Select an actual local MSBuild executable before SDK admission.'}
    $root=[IO.Path]::GetFullPath($ProjectRoot)
    $controller=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $lock=& $script:consumer {param($r,$c) Read-CiApplicationSdkLock $r $c} $root $controller
    $engineIdentity=Get-CiPinnedEngineInputsIdentity -Root $root -EngineRoot $controller
    $source=Get-CiCheckoutContentIdentity $root
    $handle=& $script:descriptors {param($d,$h) Open-CiLocalSdkSnapshotDescriptor $d $h} $Descriptor $ExpectedDescriptorSha256
    if($null -eq $handle){throw 'The exact immutable local SDK snapshot is unavailable.'}
    try{
        $inputs=$handle.Record.identity.inputs
        if($inputs.apiRevision -ne $lock.apiRevision -or $inputs.platform -cne $Platform -or
            $inputs.configuration -cne 'Release' -or $inputs.runtimeFamily -cne 'MD' -or $inputs.annotationPolicy -cne 'enabled'){
            throw 'Local SDK cannot change the application API or selected supported ABI profile.'
        }
        Assert-CiLocalConsumerProducer $handle
        $abi=Get-CiLocalConsumerAbi $handle $MSBuildPath
        if((Get-CiCheckoutContentIdentity $root) -cne $source -or
            (Get-CiPinnedEngineInputsIdentity -Root $root -EngineRoot $controller) -cne $engineIdentity){throw 'Application or actual engine inputs changed during local SDK admission.'}
        $inputRecord=[pscustomobject]@{Role='LocalUnpinnedSdkConsumerInput';ProjectRoot=$root;SourceBytes=$source;EngineInputs=$engineIdentity;
            Descriptor=$handle;SdkRoot=$handle.Snapshot.Payload;MSBuildPath=$MSBuildPath;Abi=$abi;Closed=$false;CompilerLease=$null;
            Evidence=[ordered]@{recipe='LocalUnpinnedReleaseSdk';inputKey=$handle.Record.key;manifestSha256=$handle.Record.manifestSha256;
                descriptorSha256=$ExpectedDescriptorSha256;sourceCommit=$inputs.sourceCommit;apiRevision=$inputs.apiRevision;
                platform=$Platform;configuration='Release';toolchainReference=$abi.Reference.digest}}
        Assert-CiLocalSdkConsumerSourcesCurrent $inputRecord
        Assert-CiLocalConsumerProducer $handle
        return $inputRecord
    }catch{
        $primary=$_
        try{& $script:descriptors {param($h) Close-CiLocalSdkSnapshotDescriptor $h} $handle}catch{Write-Warning ('Local SDK close also failed: '+$_.Exception.Message)}
        throw $primary
    }
}

function Assert-CiLocalSdkConsumerSourcesCurrent {
    param([Parameter(Mandatory)][object]$SdkInput)
    if($SdkInput.Role -cne 'LocalUnpinnedSdkConsumerInput' -or $SdkInput.Closed -or $SdkInput.Descriptor.Closed){throw 'An active local SDK dependency reader is required.'}
    if((Get-CiCheckoutContentIdentity $SdkInput.ProjectRoot) -cne $SdkInput.SourceBytes -or
        (Get-CiPinnedEngineInputsIdentity -Root $SdkInput.ProjectRoot -EngineRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')))) -cne $SdkInput.EngineInputs){throw 'Application or actual engine inputs changed during local SDK use.'}
    $null=& $script:descriptors {param($h) Read-CiLocalSdkSnapshotDescriptor $h.Path $h.Sha256} $SdkInput.Descriptor
    $identity=$SdkInput.Descriptor.Record.identity
    if((Resolve-CiCommit $identity.producerRoot HEAD) -cne $identity.inputs.sourceCommit -or
        (Get-CiCheckoutContentIdentity $identity.producerRoot) -cne $identity.inputs.sourceBytes){throw 'Local SDK producer source changed during consumer admission.'}
}

function Assert-CiLocalSdkConsumerInputCurrent {
    param([Parameter(Mandatory)][object]$SdkInput)
    Assert-CiLocalSdkConsumerSourcesCurrent $SdkInput
    Assert-CiLocalConsumerProducer $SdkInput.Descriptor
    $state=Get-CiLocalConsumerAbi $SdkInput.Descriptor $SdkInput.MSBuildPath
    Assert-CiLocalSdkConsumerSourcesCurrent $SdkInput
    Assert-CiLocalConsumerProducer $SdkInput.Descriptor
    return $state
}

function Start-CiLocalSdkCompilerLease {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$SdkInput,[Parameter(Mandatory)][string]$OutputRoot)
    if($env:GITHUB_ACTIONS -ceq 'true' -or $env:CI_NATIVE_BUILDS_DISABLED -ceq 'true'){throw 'Local SDK compiler leases are unavailable to hosted or compiler-free execution.'}
    if($SdkInput.CompilerLease -and -not $SdkInput.CompilerLease.Closed){throw 'The local SDK reader already has a live compiler lease.'}
    $state=Assert-CiLocalSdkConsumerInputCurrent $SdkInput
    $binding=& $script:consumer {param($s,$m)Get-CiSdkToolBinding -AbiState $s -MSBuildPath $m} $state $SdkInput.MSBuildPath
    $witness=& $script:consumer {param($r,$s,$p,$b,$o)
        New-CiSdkConsumerWitness -ProjectRoot $r -SdkRoot $s -Platform $p -ToolBinding $b -Contract LocalUnpinnedAbiV1 -OutputRoot $o
    } $SdkInput.ProjectRoot $SdkInput.SdkRoot $SdkInput.Evidence.platform $binding $OutputRoot
    $SdkInput.CompilerLease=[pscustomobject]@{Role='LocalUnpinnedSdkCompilerLease';Path=$witness.Path;Witness=$witness;OutputRoot=[IO.Path]::GetFullPath($OutputRoot);
        Contract='LocalUnpinnedAbiV1';Closed=$false}
    return $SdkInput.CompilerLease
}

function Stop-CiLocalSdkCompilerLease {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$SdkInput)
    if(-not $SdkInput.CompilerLease -or $SdkInput.CompilerLease.Closed){throw 'The local SDK reader has no active compiler lease.'}
    try{$SdkInput.CompilerLease.Witness.Stream.Dispose()}finally{$SdkInput.CompilerLease.Closed=$true}
}

function Close-CiLocalSdkConsumerInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$SdkInput)
    if($SdkInput.Closed){throw 'Local SDK consumer input is already closed.'}
    $failure=$null
    try{
        if($SdkInput.CompilerLease -and -not $SdkInput.CompilerLease.Closed){throw 'Stop the local compiler lease after owned child drain before closing dependency input.'}
        $null=Assert-CiLocalSdkConsumerInputCurrent $SdkInput
    }catch{$failure=$_}
    if($SdkInput.CompilerLease -and -not $SdkInput.CompilerLease.Closed){
        try{Stop-CiLocalSdkCompilerLease $SdkInput}catch{if($null -eq $failure){$failure=$_}else{Write-Warning ('Local compiler lease close also failed: '+$_.Exception.Message)}}
    }
    try{& $script:descriptors {param($h) Close-CiLocalSdkSnapshotDescriptor $h} $SdkInput.Descriptor}
    catch{if($null -eq $failure){$failure=$_}else{Write-Warning ('Local SDK data close also failed: '+$_.Exception.Message)}}
    finally{$SdkInput.Closed=$true}
    if($null -ne $failure){throw $failure}
}

Export-ModuleMember -Function Open-CiLocalSdkConsumerInput,Close-CiLocalSdkConsumerInput,Start-CiLocalSdkCompilerLease,Stop-CiLocalSdkCompilerLease
