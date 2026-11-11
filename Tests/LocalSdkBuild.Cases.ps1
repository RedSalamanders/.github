# Native process execution is not exercised here. The real broker's contract and
# actual linker-file reader use bounded synthetic files inside the owned fixture.
$localBuild=Import-Module (Join-Path $engine 'Tools/Modules/Ci.LocalSdkBuild.psm1') -PassThru
$buildRoot=Join-Path $root 'build-contract'
[void][IO.Directory]::CreateDirectory($buildRoot)
foreach($name in @('App.sln','App.vcxproj')){[IO.File]::WriteAllText((Join-Path $buildRoot $name),'synthetic native input')}
$buildContract=[ordered]@{buildFile='App.sln';metadataProject='App.vcxproj';target='App';sdkProperty='AppSdkRoot';engineProperty='AppEngineRoot';outputProperty='AppOutputRoot';testsProperty='AppTests';versionProperty='AppVersion';executable='App.exe'}
Case 'local application contract rejects property collisions, target injection and foreign build inputs' {
    & $localBuild {param($r,$c)Read-CiLocalSdkBuildContract $r $c} $buildRoot $buildContract
    foreach($pair in @(@('target','App;Other'),@('engineProperty','AppSdkRoot'),@('outputProperty','Bad=Value'),@('buildFile','../App.sln'),@('metadataProject','App.sln'),@('executable','C:/App.exe'))){
        $changed=$buildContract|ConvertTo-Json|ConvertFrom-Json -AsHashtable;$changed[$pair[0]]=$pair[1]
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
