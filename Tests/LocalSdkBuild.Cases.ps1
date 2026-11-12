# Native process execution is not exercised here. The real broker's contract and
# actual linker-file reader use bounded synthetic files inside the owned fixture.
$localBuild=Import-Module (Join-Path $engine 'Tools/Modules/Ci.LocalSdkBuild.psm1') -PassThru
$buildRoot=Join-Path $root 'build-contract'
[void][IO.Directory]::CreateDirectory($buildRoot)
foreach($name in @('App.sln','App.vcxproj','App.proj','App.targets')){[IO.File]::WriteAllText((Join-Path $buildRoot $name),'synthetic native input')}
$buildContract=[ordered]@{buildFile='App.sln';metadataProject='App.vcxproj';target='App';sdkProperty='AppSdkRoot';engineProperty='AppEngineRoot';outputProperty='AppOutputRoot';testsProperty='AppTests';versionProperty='AppVersion';executable='App.exe'}
Case 'local application contract rejects property collisions, target injection and foreign build inputs' {
    & $localBuild {param($r,$c)Read-CiLocalSdkBuildContract $r $c} $buildRoot $buildContract
    foreach($pair in @(@('target','App;Other'),@('engineProperty','AppSdkRoot'),@('outputProperty','Bad=Value'),@('buildFile','../App.sln'),@('metadataProject','App.sln'),@('executable',(Join-Path ([IO.Path]::GetPathRoot($buildRoot)) 'App.exe')))){
        $changed=$buildContract|ConvertTo-Json|ConvertFrom-Json -AsHashtable;$changed[$pair[0]]=$pair[1]
        Refuses {& $localBuild {param($r,$c)Read-CiLocalSdkBuildContract $r $c} $buildRoot $changed}
    }
}
Case 'reviewed native project aggregates retain a real vcxproj metadata boundary' {
    $aggregate=$buildContract|ConvertTo-Json|ConvertFrom-Json -AsHashtable
    $aggregate.buildFile='App.proj';$aggregate.target='Build'
    & $localBuild {param($r,$c)Read-CiLocalSdkBuildContract $r $c} $buildRoot $aggregate
    foreach($pair in @(@('metadataProject','App.proj'),@('buildFile','App.targets'),@('target','Build;Publish'))){
        $changed=$aggregate.Clone();$changed[$pair[0]]=$pair[1]
        Refuses {& $localBuild {param($r,$c)Read-CiLocalSdkBuildContract $r $c} $buildRoot $changed}
    }
}
Case 'local application linker evidence requires the exact held archive and refuses any foreign occurrence' {
    $intermediate=Join-Path $buildRoot 'obj';$sdk=Join-Path $buildRoot 'sdk'
    [void][IO.Directory]::CreateDirectory($intermediate)
    $archive=Join-Path $sdk 'lib/x64/Release/DxUi.lib';[void][IO.Directory]::CreateDirectory((Split-Path $archive))
    [IO.File]::WriteAllText($archive,'synthetic library, no native acceptance')
    $tracking=Join-Path $intermediate 'link.read.1.tlog'
    [IO.File]::WriteAllText($tracking,("^synthetic command`r`n"+$archive.ToUpperInvariant()+"`r`n"),[Text.Encoding]::Unicode)
    $proof=& $localBuild {param($i,$s)Get-CiLocalSdkLinkInput $i $s x64} $intermediate $sdk
    Check ($proof.librarySha256 -ceq (Get-FileHash $archive).Hash.ToLowerInvariant() -and $proof.tracking.Count -eq 1) 'Actual linker bytes were not bound.'
    [IO.File]::AppendAllText($tracking,"C:\Foreign\DxUi.lib`r`n",[Text.Encoding]::Unicode)
    Rejects-LocalConsumer {& $localBuild {param($i,$s)Get-CiLocalSdkLinkInput $i $s x64} $intermediate $sdk} 'outside the held immutable snapshot'
    [IO.File]::WriteAllText($tracking,'no DxUi archive')
    Rejects-LocalConsumer {& $localBuild {param($i,$s)Get-CiLocalSdkLinkInput $i $s x64} $intermediate $sdk} 'does not establish use'
}
Case 'unconditional application test surfaces omit an invented switch while guarded build inputs stay identical' {
    $unconditional=$buildContract|ConvertTo-Json|ConvertFrom-Json -AsHashtable
    $unconditional.testsProperty=''
    & $localBuild {param($r,$c)Read-CiLocalSdkBuildContract $r $c} $buildRoot $unconditional
    foreach($invalid in @($null,' ','Bad=Value','AppSdkRoot')){
        $changed=$unconditional.Clone();$changed.testsProperty=$invalid
        Refuses {& $localBuild {param($r,$c)Read-CiLocalSdkBuildContract $r $c} $buildRoot $changed}
    }
    $inputState=[pscustomobject]@{ProjectRoot=$buildRoot;SdkRoot=(Join-Path $buildRoot 'sdk');Evidence=@{platform='x64'};
        CompilerLease=@{Path=(Join-Path $buildRoot 'lease');Contract='LocalUnpinnedAbiV1'};
        Abi=@{Properties=@{PreferredToolArchitecture='x64';VCToolsVersion='fixture';WindowsTargetPlatformVersion='fixture'}}}
    $output=Join-Path $buildRoot 'output'
    $ordinary=& $localBuild {param($s,$c,$o)Get-CiLocalSdkApplicationProperties $s $c $o 123} $inputState $buildContract $output
    $always=& $localBuild {param($s,$c,$o)Get-CiLocalSdkApplicationProperties $s $c $o 123} $inputState $unconditional $output
    Check ($ordinary.AppTests -ceq 'true' -and -not $always.Contains('AppTests') -and -not $always.Contains('')) 'The actual build mapper invented or lost a test-surface override.'
    $ordinary.Remove('AppTests')
    Check (($ordinary|ConvertTo-Json -Compress) -ceq ($always|ConvertTo-Json -Compress)) 'Omitting the absent test switch changed guarded source, SDK, compiler, output or version inputs.'
}
Case 'application link proof covers sibling executable and plugin tracking without accepting a foreign plugin archive' {
    $operation=Join-Path $buildRoot 'multi-project-output'
    $sdk=Join-Path $buildRoot 'multi-project-sdk'
    $archive=Join-Path $sdk 'lib/x64/Release/DxUi.lib'
    [void][IO.Directory]::CreateDirectory((Split-Path $archive))
    [IO.File]::WriteAllText($archive,'synthetic SDK archive')
    foreach($name in @('App','Plugin')){
        $directory=Join-Path $operation ('Intermediate/'+$name)
        [void][IO.Directory]::CreateDirectory($directory)
        [IO.File]::WriteAllText((Join-Path $directory 'link.read.1.tlog'),$archive,[Text.Encoding]::Unicode)
    }
    $proof=& $localBuild {param($o,$s)Get-CiLocalSdkLinkInput $o $s x64} $operation $sdk
    Check ($proof.tracking.Count -eq 2) 'Application proof omitted a sibling plugin tracking file.'
    [IO.File]::WriteAllText((Join-Path $operation 'Intermediate/Plugin/link.read.1.tlog'),'C:\Foreign\DxUi.lib',[Text.Encoding]::Unicode)
    Rejects-LocalConsumer {& $localBuild {param($o,$s)Get-CiLocalSdkLinkInput $o $s x64} $operation $sdk} 'outside the held immutable snapshot'
}
Case 'local application entrypoint refuses hosted and compiler-free requests before dependency or output discovery' {
    $native=$env:CI_NATIVE_BUILDS_DISABLED;$actions=$env:GITHUB_ACTIONS
    try{
        foreach($mode in @('native-disabled','hosted')){
            $env:CI_NATIVE_BUILDS_DISABLED=$(if($mode -eq 'native-disabled'){'true'}else{''})
            $env:GITHUB_ACTIONS=$(if($mode -eq 'hosted'){'true'}else{''})
            Rejects-LocalConsumer {Invoke-CiLocalSdkApplicationBuild -ProjectRoot (Join-Path $buildRoot 'missing') -Descriptor 'missing' -ExpectedDescriptorSha256 ('0'*64) -Platform x64 -MSBuildPath 'missing' -BuildContract $buildContract} 'require local Windows native execution'
        }
    }finally{$env:CI_NATIVE_BUILDS_DISABLED=$native;$env:GITHUB_ACTIONS=$actions}
    Check (-not(Test-Path (Join-Path $buildRoot 'missing'))) 'Early refusal wrote candidate state.'
}
Case 'broker timing covers contiguous invocation phases and distinguishes a failed build from successful cleanup' {
    foreach($failureMode in @('none','nativeBuild','ownedCleanup')){
        $report=& $localBuild {
            param($failure)
            $t=New-CiLocalSdkBuildTiming
            Set-CiLocalSdkBuildPhase $t 'sdkAdmission'
            Set-CiLocalSdkBuildPhase $t 'nativeBuild'
            Set-CiLocalSdkBuildPhase $t 'ownedCleanup' -Outcome $(if($failure -ceq 'nativeBuild'){'failed'}else{'completed'})
            Complete-CiLocalSdkBuildTiming $t ($failure -cne 'none') ($failure -ceq 'ownedCleanup')
        } $failureMode
        $end=0.0
        foreach($phase in $report.phases){
            Check ($phase.elapsedMs -ge 0 -and [Math]::Abs($phase.startMs-$end) -lt 0.001) 'Broker phase timing lost or counted a time interval twice.'
            $end=$phase.startMs+$phase.elapsedMs
        }
        Check ([Math]::Abs($end-$report.totalElapsedMs) -lt 0.001 -and $report.scope -ceq 'BrokerInvocation') 'Compile-only timing was presented as the broker total.'
        Check ($report.passed -eq ($failureMode -ceq 'none')) 'Timing diagnostics changed the observed verdict.'
        Check (($report.phases|Where-Object name -CEQ nativeBuild).outcome -ceq $(if($failureMode -ceq 'nativeBuild'){'failed'}else{'completed'})) 'The failed native phase was hidden.'
        Check (($report.phases|Where-Object name -CEQ ownedCleanup).outcome -ceq $(if($failureMode -ceq 'ownedCleanup'){'failed'}else{'completed'})) 'A primary native failure was incorrectly attributed to cleanup.'
        Check (-not $report.testsExecuted -and -not $report.repositoryQualified -and -not $report.productionQualified) 'Timing granted qualification.'
    }
}
