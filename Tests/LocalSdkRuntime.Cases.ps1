# Real output bytes, paths and exclusive file ownership. Only the already tested
# SDK/native acquisition boundary is synthetic; no fixture launches a product.
$localRuntime=Import-Module (Join-Path $engine 'Tools/Modules/Ci.LocalSdkRuntime.psm1') -PassThru
& $localRuntime {
    $script:fixtureSource='b'*64;$script:fixtureEngine='c'*64;$script:fixtureCloseFails=$false;$script:fixtureLastSdk=$null
    function script:Open-CiLocalSdkConsumerInput {
        param($ProjectRoot,$Descriptor,$ExpectedDescriptorSha256,$Platform,$Configuration,$MSBuildPath)
        $script:fixtureLastSdk=[pscustomobject]@{SourceBytes=$script:fixtureSource;EngineInputs=$script:fixtureEngine;Evidence=@{recipe='synthetic boundary'};Closed=$false}
        $script:fixtureLastSdk
    }
    function script:Close-CiLocalSdkConsumerInput {
        param($SdkInput)
        $SdkInput.Closed=$true
        if($script:fixtureCloseFails){throw 'synthetic SDK close mismatch'}
    }
}
function New-LocalRuntimeFixture {
    $operation=Join-Path $consumerRoot ('.build/local-unpinned/'+[guid]::NewGuid().ToString('N'))
    $bin=Join-Path $operation 'x64/Release'
    [void][IO.Directory]::CreateDirectory((Join-Path $bin 'Lang'))
    foreach($file in @('App.exe','Plugin.dll','Lang/strings.json')){[IO.File]::WriteAllText((Join-Path $bin $file),'synthetic runtime '+$file)}
    [IO.File]::WriteAllText((Join-Path $operation 'operation.lock'),'')
    $catalog=& $localRuntime {param($r)& $script:abi {param($v)Get-CiPortableSdkFileReference @{ApplicationOutput=$v}} $r} $bin
    $record=[ordered]@{schemaVersion=1;role='LocalUnpinnedApplicationBuild';recipe='LocalUnpinnedReleaseSdk';projectRoot=$consumerRoot;
        sourceBytes=('b'*64);engineInputs=('c'*64);dependency=@{recipe='synthetic boundary'};platform='x64';configuration='Release';
        outputRoot=$operation;executable=(Join-Path $bin 'App.exe');executableSha256=(Get-FileHash (Join-Path $bin 'App.exe')).Hash.ToLowerInvariant();
        inputDescriptor=@{path=$consumerDescriptor;sha256=$consumerHash};runtimeRoot=$bin;runtimeBytes=$catalog;
        testsExecuted=$false;repositoryQualified=$false;productionQualified=$false}
    $receipt=Join-Path $operation 'local-unpinned-build.json'
    [IO.File]::WriteAllText($receipt,($record|ConvertTo-Json -Depth 12))
    [pscustomobject]@{Root=$operation;Bin=$bin;Record=$record;Receipt=$receipt;Sha256=(Get-FileHash $receipt).Hash.ToLowerInvariant()}
}
function Open-LocalRuntimeFixture($Fixture){
    & $localRuntime {param($r,$p,$h,$m)Open-CiLocalSdkRuntimeInput -ProjectRoot $r -BuildReceipt $p -ExpectedBuildSha256 $h -MSBuildPath $m} $consumerRoot $Fixture.Receipt $Fixture.Sha256 $fakeMSBuild
}
function Close-LocalRuntimeFixture($Value){& $localRuntime {param($v)Close-CiLocalSdkApplicationRuntimeInput $v} $Value}
function Check-LocalRuntimeUnlocked($Fixture){
    foreach($path in @((Join-Path $Fixture.Root 'operation.lock'),$Fixture.Receipt,(Join-Path $Fixture.Bin 'Plugin.dll'))){
        $stream=[IO.File]::Open($path,'Open','ReadWrite','None');$stream.Dispose()
    }
}
try{
    Case 'runtime admission holds all payload and operation bytes until verified close without granting a result' {
        $f=New-LocalRuntimeFixture;$value=Open-LocalRuntimeFixture $f
        try{
            Check ($value.Role -ceq 'LocalUnpinnedApplicationRuntimeInput' -and $value.PayloadStreams.Count -eq 3) 'Runtime admission omitted a plugin or nested resource.'
            foreach($path in @($f.Receipt,(Join-Path $f.Root 'operation.lock'),(Join-Path $f.Bin 'Lang/strings.json'))){Refuses {$stream=[IO.File]::Open($path,'Open','ReadWrite','None');$stream.Dispose()}}
            Check (-not $value.Build.testsExecuted -and -not $value.Build.repositoryQualified) 'Opening bytes granted a test result.'
        }finally{Close-LocalRuntimeFixture $value}
        Check-LocalRuntimeUnlocked $f
        Refuses {Close-LocalRuntimeFixture $value}
    }
    Case 'runtime admission rejects equal-size equal-time resource corruption and removed plugin bytes' {
        foreach($mutation in @('resource','plugin')){
            $f=New-LocalRuntimeFixture
            if($mutation -ceq 'resource'){
                $path=Join-Path $f.Bin 'Lang/strings.json';$time=[IO.File]::GetLastWriteTimeUtc($path)
                $bytes=[IO.File]::ReadAllBytes($path);$bytes[0]=$bytes[0] -bxor 1;[IO.File]::WriteAllBytes($path,$bytes);[IO.File]::SetLastWriteTimeUtc($path,$time)
            }else{[IO.File]::Move((Join-Path $f.Bin 'Plugin.dll'),(Join-Path $f.Root 'retained-plugin.dll'))}
            Rejects-LocalConsumer {Open-LocalRuntimeFixture $f} 'payload inventory or bytes changed'
            Check (& $localRuntime {$script:fixtureLastSdk.Closed}) 'Failed admission retained its dependency reader.'
            $lock=[IO.File]::Open((Join-Path $f.Root 'operation.lock'),'Open','ReadWrite','None');$lock.Dispose()
        }
    }
    Case 'runtime close rejects added payloads and releases ownership after SDK close failure' {
        foreach($failure in @('added','sdk-close')){
            $f=New-LocalRuntimeFixture;$value=Open-LocalRuntimeFixture $f
            try{
                if($failure -ceq 'added'){[IO.File]::WriteAllText((Join-Path $f.Bin 'Injected.dll'),'synthetic addition')}
                else{& $localRuntime {$script:fixtureCloseFails=$true}}
                Rejects-LocalConsumer {Close-LocalRuntimeFixture $value} $(if($failure -ceq 'added'){'payload inventory or bytes changed'}else{'synthetic SDK close mismatch'})
                Check ($value.Closed -and $value.SdkInput.Closed) 'Failed close retained ownership.'
                Check-LocalRuntimeUnlocked $f
            }finally{& $localRuntime {$script:fixtureCloseFails=$false};if(-not $value.Closed){Close-LocalRuntimeFixture $value}}
        }
    }
    Case 'runtime admission refuses source and engine mismatch and another active output operation' {
        foreach($field in @('fixtureSource','fixtureEngine')){
            $f=New-LocalRuntimeFixture
            try{
                & $localRuntime {param($n)Set-Variable -Name $n -Scope Script -Value ('f'*64)} $field
                Rejects-LocalConsumer {Open-LocalRuntimeFixture $f} 'source, actual engine or dependency differs'
                Check-LocalRuntimeUnlocked $f
            }finally{& $localRuntime {$script:fixtureSource='b'*64;$script:fixtureEngine='c'*64}}
        }
        $f=New-LocalRuntimeFixture;$lock=[IO.File]::Open((Join-Path $f.Root 'operation.lock'),'Open','ReadWrite','None')
        try{Refuses {Open-LocalRuntimeFixture $f}}finally{$lock.Dispose()}
        Check-LocalRuntimeUnlocked $f
    }
    Case 'runtime record refuses old partial catalogs, qualification claims, alternate roots and foreign dependencies' {
        foreach($change in @('missing','qualified','pinned','root','executable','descriptor')){
            $f=New-LocalRuntimeFixture
            switch($change){
                missing {$f.Record.Remove('runtimeBytes')}
                qualified {$f.Record.repositoryQualified=$true}
                pinned {$f.Record.role='PinnedApplicationBuild'}
                root {$f.Record.outputRoot=$consumerRoot}
                executable {$f.Record.executable=Join-Path $f.Root 'foreign.exe'}
                descriptor {$f.Record.inputDescriptor.sha256='not a hash'}
            }
            [IO.File]::WriteAllText($f.Receipt,($f.Record|ConvertTo-Json -Depth 12));$f.Sha256=(Get-FileHash $f.Receipt).Hash.ToLowerInvariant()
            Refuses {Open-LocalRuntimeFixture $f};Check-LocalRuntimeUnlocked $f
        }
        $f=New-LocalRuntimeFixture;$f.Sha256='0'*64
        Rejects-LocalConsumer {Open-LocalRuntimeFixture $f} 'independently retained digest'
        Check-LocalRuntimeUnlocked $f
    }
    Case 'runtime payload refuses linked resource roots without traversing their targets' {
        $f=New-LocalRuntimeFixture;$target=Join-Path $f.Root 'owned-link-target';[void][IO.Directory]::CreateDirectory($target)
        [IO.File]::WriteAllText((Join-Path $target 'sentinel.txt'),'owned synthetic target')
        $link=Join-Path $f.Bin 'LinkedResources'
        $null=New-Item -ItemType $(if($IsWindows){'Junction'}else{'SymbolicLink'}) -Path $link -Target $target
        Rejects-LocalConsumer {Open-LocalRuntimeFixture $f} 'refuse links without traversing'
        Check ([IO.File]::ReadAllText((Join-Path $target 'sentinel.txt')) -ceq 'owned synthetic target') 'Runtime catalog changed a link target.'
        Check-LocalRuntimeUnlocked $f
    }
    Case 'public runtime admission refuses hosted and compiler-free requests before file discovery' {
        $savedNative=$env:CI_NATIVE_BUILDS_DISABLED;$savedActions=$env:GITHUB_ACTIONS
        try{
            foreach($mode in @('native-disabled','hosted')){
                $env:CI_NATIVE_BUILDS_DISABLED=$(if($mode -ceq 'native-disabled'){'true'}else{''})
                $env:GITHUB_ACTIONS=$(if($mode -ceq 'hosted'){'true'}else{''})
                Rejects-LocalConsumer {& $localRuntime {Open-CiLocalSdkApplicationRuntimeInput -ProjectRoot missing -BuildReceipt missing -ExpectedBuildSha256 ('0'*64) -MSBuildPath missing}} 'requires local Windows native execution'
            }
        }finally{$env:CI_NATIVE_BUILDS_DISABLED=$savedNative;$env:GITHUB_ACTIONS=$savedActions}
    }
}finally{Remove-Module $localRuntime -Force}
