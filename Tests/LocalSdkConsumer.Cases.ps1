# Invoked by Test-SdkCache. Actual stores, descriptors, Git/engine bindings and file hashes;
# only original native build acquisition and real Windows ABI evaluation are synthetic.
$consumerRoot=Join-Path $root '.build/local-consumer'
[void][IO.Directory]::CreateDirectory((Join-Path $consumerRoot '.ci'))
$null=Invoke-CiGit $consumerRoot @('init','--initial-branch=main')
foreach($setting in @(@('user.name','Consumer Fixture'),@('user.email','fixture@example.invalid'),@('commit.gpgsign','false'),@('core.autocrlf','false'),@('core.hooksPath',(Join-Path $consumerRoot '.empty-hooks')))){$null=Invoke-CiGit $consumerRoot @('config',$setting[0],$setting[1])}
$consumerProject=$project|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
$consumerProject.repository='RedSalamanders/RedTilde';$consumerProject.kind='application'
$consumerProject.winget=@{identifier='RedSalamanders.RedTilde';executable='RedTilde.exe';alias='redtilde';license='MIT'}
[IO.File]::WriteAllText((Join-Path $consumerRoot '.ci/project.json'),($consumerProject|ConvertTo-Json -Depth 8))
[IO.File]::WriteAllText((Join-Path $consumerRoot '.gitignore'),".build/`n.ci-engine/`n")
[void][IO.Directory]::CreateDirectory((Join-Path $consumerRoot 'Dependencies'))
$lockFile=Join-Path $consumerRoot 'Dependencies/DxUi.lock.json'
$lockText=@{repository='https://github.com/RedSalamanders/DxUi';commit=('a'*40);apiRevision=4;targets=@('DxUi')}|ConvertTo-Json
[IO.File]::WriteAllText($lockFile,$lockText)
$null=Invoke-CiGit $consumerRoot @('add','--all');$null=Invoke-CiGit $consumerRoot @('commit','-m','Consumer baseline')
$null=Invoke-CiGit $consumerRoot @('clone','--quiet','--no-hardlinks',$engine,'.ci-engine')
$null=Invoke-CiGit (Join-Path $consumerRoot '.ci-engine') @('checkout','--quiet','--detach',$engineHead)
$localConsumer=Import-Module (Join-Path $consumerRoot '.ci-engine/Tools/Modules/Ci.LocalSdkConsumer.psm1') -PassThru
$abiModule=& $localConsumer {$script:abi}
$toolRoots=[ordered]@{}
foreach($role in @('MSBuild','VCTargets','MSVCHeaders','MSVCLibraries','MSVCTools','WindowsHeaders','WindowsLibraries','CRuntimeLibraries','WindowsTools')){
    $directory=Join-Path $root ('abi-fixture/'+$role);[void][IO.Directory]::CreateDirectory($directory)
    [IO.File]::WriteAllText((Join-Path $directory 'fixture.txt'),"synthetic $role")
    $toolRoots[$role]=$directory
}
$fileReference=& $abiModule {param($r) Get-CiPortableSdkFileReference $r} $toolRoots
$compiler=[ordered]@{platform='x64';configuration='Release';toolset='v145';vcToolsVersion='14.52.37025';windowsSdkVersion='10.0.26100.0';preferredToolArchitecture='x64';vcToolArchitecture='Native64Bit';windowsSdkToolArchitecture='Native64Bit'}
$reference=& $abiModule {param($c,$f) New-CiSdkAbiReference $c $f} $compiler $fileReference
& $abiModule {param($r)
    $script:localFixtureReference=$r;$script:localFixtureMismatch=$false
    function script:Get-CiSdkAbiReference {
        param($ToolingRoot,$MSBuildPath,$ProjectPath,$Platform,$PreferredToolArchitecture,[switch]$PassThruBinding)
        $ref=$script:localFixtureReference|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable
        if($script:localFixtureMismatch){$ref.digest='0'*64}
        return [pscustomobject]@{Reference=$ref;Properties=@{};SelectedTools=@{};Roots=@{}}
    }
} $reference
$currentRecordFile=Join-Path $producer '.build/current-library.json'
[void][IO.Directory]::CreateDirectory((Split-Path $currentRecordFile))
$moduleDirectory=Join-Path $tooling 'Tools';[void][IO.Directory]::CreateDirectory($moduleDirectory)
$moduleSource=@'
function Assert-DxUiSdkLibraryBuild {
    param([string]$Root,[string]$Platform)
    Get-Content -LiteralPath (Join-Path $Root '.build/current-library.json') -Raw|ConvertFrom-Json -AsHashtable
}
Export-ModuleMember -Function Assert-DxUiSdkLibraryBuild
'@
[IO.File]::WriteAllText((Join-Path $moduleDirectory 'SdkLibraryInputs.psm1'),$moduleSource)
$null=Invoke-CiGit $tooling @('add','--all');$null=Invoke-CiGit $tooling @('commit','-m','Synthetic original native build boundary')
$consumerPayload=Join-Path $root 'consumer-payload'
$consumerRoles=[ordered]@{headers=@('include/DxUi/DxUi.h');libraries=@('lib/x64/Release/DxUi.lib');symbols=@('lib/x64/Release/DxUi.pdb');integration=@('DxUi.Sdk.props','build/NativeBuildPolicy.targets');licenses=@('licenses/LICENSE.txt');buildProvenance=@('provenance/library-inputs.json','provenance/toolchain-reference.json')}
foreach($family in $consumerRoles.Keys){foreach($relative in $consumerRoles[$family]){
    $path=Join-Path $consumerPayload $relative;[void][IO.Directory]::CreateDirectory((Split-Path $path));[IO.File]::WriteAllText($path,"synthetic $family")
}}
$capturedRecord=[ordered]@{schemaVersion=1;files=@('DxUi.lib','DxUi.pdb'|ForEach-Object {@{path=$_;sha256=(Get-FileHash (Join-Path $consumerPayload ('lib/x64/Release/'+$_))).Hash.ToLowerInvariant()}})}
[IO.File]::WriteAllText($currentRecordFile,($capturedRecord|ConvertTo-Json -Depth 8))
[IO.File]::WriteAllText((Join-Path $consumerPayload 'provenance/library-inputs.json'),($capturedRecord|ConvertTo-Json -Depth 8))
[IO.File]::WriteAllText((Join-Path $consumerPayload 'provenance/toolchain-reference.json'),($reference|ConvertTo-Json -Depth 12))
$consumerIdentity=$localIdentity|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable
$consumerIdentity.bindings=$consumerRoles
$consumerEntry=Publish-CiLocalSdkSnapshot $descriptorStore $consumerIdentity $consumerPayload
$consumerDescriptorRecord=$descriptorRecord|ConvertTo-Json -Depth 14|ConvertFrom-Json -AsHashtable
$consumerDescriptorRecord.identity=$consumerEntry.Manifest.identity;$consumerDescriptorRecord.key=$consumerEntry.Key;$consumerDescriptorRecord.manifestSha256=$consumerEntry.ManifestSha256
$consumerDescriptorRecord.producerTooling.commit=Resolve-CiCommit $tooling HEAD
$consumerDescriptorRecord.toolingBootstrap.sourceBytes=Get-CiCheckoutContentIdentity $tooling
$consumerDescriptorRecord.producerTooling.contentIdentity=$consumerDescriptorRecord.toolingBootstrap.sourceBytes
$consumerDescriptor=Join-Path $tooling '.build/local-sdk-capture/consumer/local-unpinned-snapshot.json'
[void][IO.Directory]::CreateDirectory((Split-Path $consumerDescriptor))
[IO.File]::WriteAllText($consumerDescriptor,($consumerDescriptorRecord|ConvertTo-Json -Depth 14))
$consumerHash=(Get-FileHash $consumerDescriptor).Hash.ToLowerInvariant()
$fakeMSBuild=Join-Path $root 'MSBuild.exe';[IO.File]::WriteAllText($fakeMSBuild,'not executable; native ABI acquisition is the recorded boundary')
$consumerArguments=@{ProjectRoot=$consumerRoot;Descriptor=$consumerDescriptor;ExpectedDescriptorSha256=$consumerHash;Platform='x64';Configuration='Release';MSBuildPath=$fakeMSBuild}
function Open-LocalConsumerFixture {& $localConsumer {param($a) Open-CiLocalSdkConsumerInput @a} $consumerArguments}
function Close-LocalConsumerFixture($value){& $localConsumer {param($v) Close-CiLocalSdkConsumerInput $v} $value}
function Rejects-LocalConsumer([scriptblock]$Body,[string]$Pattern){
    $errorText='';try{& $Body|Out-Null}catch{$errorText=$_.Exception.Message}
    Check ($errorText -match $Pattern) ('Expected local consumer refusal '+$Pattern+'; actual: '+$errorText)
}
function Check-LocalConsumerWriterUnlocked {
    $storage=Import-Module (Join-Path $consumerRoot '.ci-engine/Tools/Modules/Ci.SdkCache.psm1') -PassThru
    & $storage {param($s,$k)$lease=Enter-CiSdkEntryLock $s $k -Writer;$lease.Dispose()} $descriptorStore $consumerEntry.Key
}
Case 'local consumer admission binds real immutable bytes and preserves a distinct unpinned role' {
    $value=Open-LocalConsumerFixture
    try{
        Check ($value.Role -ceq 'LocalUnpinnedSdkConsumerInput' -and $value.Evidence.recipe -ceq 'LocalUnpinnedReleaseSdk') 'Local dependency was mislabeled pinned or qualified.'
        Check ($value.SdkRoot -ceq $consumerEntry.Payload -and $value.Evidence.sourceCommit -ceq $localInputs.sourceCommit) 'Another producer/payload was selected.'
        Check ((Get-Content $lockFile -Raw) -ceq $lockText) 'Local admission changed the application lock.'
        Check (-not [IO.File]::Exists((Join-Path $consumerRoot '.build/build-receipt.json'))) 'Dependency admission published a build result.'
    }finally{Close-LocalConsumerFixture $value}
    Rejects-LocalConsumer {Close-LocalConsumerFixture $value} 'already closed'
    Check-LocalConsumerWriterUnlocked
}
Case 'local consumer refuses hosted or non-Release input before discovery' {
    $saved=$env:GITHUB_ACTIONS;$savedRoot=$consumerArguments.ProjectRoot
    try{
        $consumerArguments.ProjectRoot=Join-Path $root 'does-not-exist'
        $env:GITHUB_ACTIONS='true';Rejects-LocalConsumer {Open-LocalConsumerFixture} 'unavailable to hosted'
        $env:GITHUB_ACTIONS=$saved;$consumerArguments.Configuration='Debug';Rejects-LocalConsumer {Open-LocalConsumerFixture} 'require Release'
    }finally{$env:GITHUB_ACTIONS=$saved;$consumerArguments.Configuration='Release';$consumerArguments.ProjectRoot=$savedRoot}
}
Case 'local consumer refuses an API change and different actual toolchain bytes' {
    try{[IO.File]::WriteAllText($lockFile,$lockText.Replace('"apiRevision": 4','"apiRevision": 5'));Rejects-LocalConsumer {Open-LocalConsumerFixture} 'cannot change the application API'}
    finally{[IO.File]::WriteAllText($lockFile,$lockText)}
    try{& $abiModule {$script:localFixtureMismatch=$true};Rejects-LocalConsumer {Open-LocalConsumerFixture} 'ABI differs'}
    finally{& $abiModule {$script:localFixtureMismatch=$false}}
    $value=Open-LocalConsumerFixture;Close-LocalConsumerFixture $value
    Check-LocalConsumerWriterUnlocked
}
Case 'local consumer rejects changed original library provenance and closes its data lease' {
    $saved=[IO.File]::ReadAllText($currentRecordFile)
    try{[IO.File]::WriteAllText($currentRecordFile,$saved.Replace('"schemaVersion": 1','"schemaVersion": 2'));Rejects-LocalConsumer {Open-LocalConsumerFixture} 'build provenance changed'}
    finally{[IO.File]::WriteAllText($currentRecordFile,$saved)}
    # A fresh reader after failure must still acquire and close the exact immutable entry.
    $value=Open-LocalConsumerFixture;Close-LocalConsumerFixture $value
    Check-LocalConsumerWriterUnlocked
}
Case 'local consumer close rejects application and actual engine mutations while releasing ownership' {
    foreach($file in @($lockFile,(Join-Path $consumerRoot '.ci-engine/AGENTS.md'))){
        $value=Open-LocalConsumerFixture;$saved=[IO.File]::ReadAllBytes($file)
        try{[IO.File]::AppendAllText($file,"`nchanged during local dependency use");Rejects-LocalConsumer {Close-LocalConsumerFixture $value} 'Application or actual engine inputs changed|Local engine';Check $value.Closed 'Failed close retained consumer ownership.'}
        finally{[IO.File]::WriteAllBytes($file,$saved)}
        Check-LocalConsumerWriterUnlocked
    }
    $value=Open-LocalConsumerFixture;Close-LocalConsumerFixture $value
}
Case 'local consumer close rechecks actual ABI and releases its immutable reader on mismatch' {
    $value=Open-LocalConsumerFixture
    try{
        & $abiModule {$script:localFixtureMismatch=$true}
        Rejects-LocalConsumer {Close-LocalConsumerFixture $value} 'ABI differs'
        Check $value.Closed 'ABI mismatch retained consumer ownership.'
    }finally{& $abiModule {$script:localFixtureMismatch=$false}}
    Check-LocalConsumerWriterUnlocked
}
Case 'local consumer refuses changed toolkit bytes before importing original build acquisition' {
    $file=Join-Path $moduleDirectory 'SdkLibraryInputs.psm1';$saved=[IO.File]::ReadAllBytes($file)
    try{
        [IO.File]::AppendAllText($file,"`nthrow 'modified acquisition must never execute'`n")
        Rejects-LocalConsumer {Open-LocalConsumerFixture} 'producer tooling or its actual pinned engine changed before import'
    }finally{[IO.File]::WriteAllBytes($file,$saved)}
    Check-LocalConsumerWriterUnlocked
}
