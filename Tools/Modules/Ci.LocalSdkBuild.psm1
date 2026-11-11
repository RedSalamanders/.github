# Local developer builds only. Application layouts and dependency preparation belong to adapters.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SourceInputs.psm1')
$script:local=Import-Module (Join-Path $PSScriptRoot 'Ci.LocalSdkConsumer.psm1') -PassThru
$script:consumer=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkConsumer.psm1') -PassThru

function Read-CiLocalSdkBuildContract {
    param([string]$Root,[Collections.IDictionary]$Contract)
    $keys=@('buildFile','metadataProject','target','sdkProperty','engineProperty','outputProperty','testsProperty','versionProperty','executable')
    if($Contract.Count -ne $keys.Count -or @($keys|Where-Object {-not $Contract.Contains($_)}).Count){throw 'Local SDK application contract has missing or unknown fields.'}
    foreach($name in $keys){if($Contract[$name] -isnot [string] -or [string]::IsNullOrWhiteSpace($Contract[$name])){throw 'Local SDK application contract fields must be nonempty strings.'}}
    foreach($name in @('sdkProperty','engineProperty','outputProperty','testsProperty','versionProperty')){
        if($Contract[$name] -cnotmatch '^[A-Za-z][A-Za-z0-9]*$'){throw 'Application property names must be literal MSBuild identifiers.'}
    }
    if(@($keys|Where-Object {$_ -like '*Property'}|ForEach-Object {$Contract[$_]}|Select-Object -Unique).Count -ne 5){throw 'Application SDK, engine, output, test and version properties must be distinct.'}
    if($Contract.target -cnotmatch '^[A-Za-z0-9_.\\:]+$'){throw 'Local SDK target must be one literal reviewed build target.'}
    foreach($name in @('buildFile','metadataProject')){
        if([IO.Path]::IsPathFullyQualified($Contract[$name])){throw 'Application build paths must be repository relative.'}
        $path=Assert-CiContainedPath $Root (Join-Path $Root $Contract[$name])
        if(-not [IO.File]::Exists($path)){throw 'Application SDK build contract names a missing project or solution.'}
    }
    if($Contract.metadataProject -cnotmatch '\.vcxproj$' -or $Contract.buildFile -cnotmatch '\.(sln|vcxproj)$'){throw 'Local SDK builds require reviewed native MSBuild inputs.'}
    if([IO.Path]::IsPathFullyQualified($Contract.executable) -or $Contract.executable -cnotmatch '\.exe$'){throw 'Application executable must be relative to the evaluated output directory.'}
}

function Get-CiLocalSdkLinkInput {
    param([string]$IntermediateRoot,[string]$SdkRoot,[string]$Platform)
    $wanted=[IO.Path]::GetFullPath((Join-Path $SdkRoot ("lib/$Platform/Release/DxUi.lib"))).Replace('/','\')
    $found=$false;$evidence=[Collections.Generic.List[object]]::new()
    # Unlike the SDK payload catalog, this traversal reads only bounded linker
    # tracking files, not potentially many GiB of compiler intermediates.
    if((Get-Item -LiteralPath $IntermediateRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Local linker tracking never follows reparse points.'}
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($IntermediateRoot)
    $logs=[Collections.Generic.List[IO.FileInfo]]::new();$entries=0
    while($pending.Count){
        $directory=$pending.Pop()
        if(-not [IO.Path]::GetFullPath($directory).Equals([IO.Path]::GetFullPath($IntermediateRoot),[StringComparison]::OrdinalIgnoreCase)){[void](Assert-CiContainedPath $IntermediateRoot $directory)}
        foreach($entry in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop){
            $entries++;if($entries -gt 65536){throw 'Local intermediate tracking exceeds its bounded inventory.'}
            if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Local linker tracking never follows reparse points.'}
            if($entry.PSIsContainer){$pending.Push($entry.FullName)}
            elseif($entry.Name -match '^link\.read\.[0-9]+\.tlog$'){$logs.Add($entry)}
        }
    }
    foreach($log in $logs){
        [void](Assert-CiContainedPath $IntermediateRoot $log.FullName)
        if($log.Length -gt 32MB){throw 'Local linker input tracking exceeds its bounded read.'}
        $text=[IO.File]::ReadAllText($log.FullName)
        foreach($line in ($text -split '\r?\n')){
            $value=$line.Trim().Trim('"').Replace('/','\')
            if($value -notmatch '(?i)(^|\\)DxUi\.lib$'){continue}
            if(-not [IO.Path]::IsPathFullyQualified($value) -or -not [IO.Path]::GetFullPath($value).Equals($wanted,[StringComparison]::OrdinalIgnoreCase)){
                throw 'Actual linker tracking names a DxUi library outside the held immutable snapshot.'
            }
            $found=$true
        }
        $evidence.Add(@{path=[IO.Path]::GetRelativePath($IntermediateRoot,$log.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $log.FullName).Hash.ToLowerInvariant()})
    }
    if(-not $found){throw 'Actual linker tracking does not establish use of the held local SDK archive.'}
    return [ordered]@{library=$wanted;librarySha256=(Get-FileHash -LiteralPath $wanted).Hash.ToLowerInvariant();tracking=$evidence.ToArray()}
}

function Invoke-CiLocalSdkApplicationBuild {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$Descriptor,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedDescriptorSha256,
        [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,
        [Parameter(Mandatory)][string]$MSBuildPath,[Parameter(Mandatory)][Collections.IDictionary]$BuildContract,
        [ValidateRange(0,65535)][int]$BuildNumber=0,[scriptblock]$PrepareDependencies)
    if(-not $IsWindows -or $env:GITHUB_ACTIONS -ceq 'true' -or $env:CI_NATIVE_BUILDS_DISABLED -ceq 'true'){throw 'Local unpinned application builds require local Windows native execution.'}
    $root=[IO.Path]::GetFullPath($ProjectRoot)
    Read-CiLocalSdkBuildContract $root $BuildContract
    $inputState=Open-CiLocalSdkConsumerInput -ProjectRoot $root -Descriptor $Descriptor -ExpectedDescriptorSha256 $ExpectedDescriptorSha256 -Platform $Platform -Configuration Release -MSBuildPath $MSBuildPath
    $frame=$null;$operation=$null;$failure=$null;$result=$null;$output=$null
    try{
        if($null -ne $PrepareDependencies){$null=& $PrepareDependencies}
        # Fresh operations retain failed outputs and cannot overwrite a separately running local app.
        # Shared immutable SDK input is acquired before this consumer output write ownership.
        $output=Assert-CiContainedPath (Join-Path $root '.build/local-unpinned') (Join-Path $root ('.build/local-unpinned/'+[guid]::NewGuid().ToString('N')))
        [void](New-Item -ItemType Directory -Path $output -ErrorAction Stop)
        $operation=[IO.File]::Open((Join-Path $output 'operation.lock'),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $frame=Start-CiLocalSdkCompilerLease -SdkInput $inputState -OutputRoot $output
        foreach($path in @($root,$output,$inputState.SdkRoot,$frame.Path)){if($path -match '[%;"\r\n]'){throw 'Local SDK paths contain unsupported MSBuild delimiters.'}}
        $properties=[ordered]@{Platform=$Platform;Configuration='Release';CiSdkRoot=$inputState.SdkRoot;CiSdkProjectRoot=$root;
            CiSdkLeasePath=$frame.Path;CiSdkContract=$frame.Contract;DxUiRoot='';DxUiDisableStlAnnotations='false';
            PreferredToolArchitecture=[string]$inputState.Abi.Properties.PreferredToolArchitecture;VCToolsVersion=[string]$inputState.Abi.Properties.VCToolsVersion;
            WindowsTargetPlatformVersion=[string]$inputState.Abi.Properties.WindowsTargetPlatformVersion}
        $properties[$BuildContract.sdkProperty]=$inputState.SdkRoot
        $properties[$BuildContract.engineProperty]=Join-Path $root '.ci-engine'
        $properties[$BuildContract.outputProperty]=$output+[IO.Path]::DirectorySeparatorChar
        $properties[$BuildContract.testsProperty]='true';$properties[$BuildContract.versionProperty]=[string]$BuildNumber
        $arguments=@($properties.Keys|ForEach-Object {'/p:'+$_+'='+[string]$properties[$_]})
        $metadataPath=Join-Path $root $BuildContract.metadataProject
        $query=Invoke-CiProcess -FilePath $MSBuildPath -Arguments (@($metadataPath,'/nologo','/v:quiet','-getProperty:OutDir,IntDir,DxUiRoot,DxUiSdkRoot,CiSdkContract')+$arguments) -WorkingDirectory $root -TimeoutSeconds 120
        $actual=($query.stdout|ConvertFrom-Json -AsHashtable).Properties
        if($actual.DxUiRoot -or $actual.CiSdkContract -cne $frame.Contract -or
            -not [IO.Path]::GetFullPath($actual.DxUiSdkRoot).TrimEnd('\','/').Equals([IO.Path]::GetFullPath($inputState.SdkRoot).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)){
            throw 'Actual application metadata redirects or downgrades the local SDK recipe.'
        }
        & $script:consumer {param($r,$p,$s,$a,$o,$i)Assert-CiLocalSdkOutputLease $r $p $s $a Release $o $i} $root $frame.Path $inputState.SdkRoot $Platform $actual.OutDir $actual.IntDir
        [IO.File]::WriteAllText((Join-Path $output 'inputs.json'),([ordered]@{role='LocalUnpinnedApplicationBuild';sourceBytes=$inputState.SourceBytes;engineInputs=$inputState.EngineInputs;
            dependency=$inputState.Evidence;contract=$BuildContract;properties=$properties;evaluated=$actual}|ConvertTo-Json -Depth 14))
        $log=Join-Path $output 'build.log';$clock=[Diagnostics.Stopwatch]::StartNew()
        $build=Invoke-CiProcess -FilePath $MSBuildPath -Arguments (@((Join-Path $root $BuildContract.buildFile),'/nologo','/m:2','/nr:false','/v:normal',('/t:'+$BuildContract.target))+$arguments) -WorkingDirectory $root -TimeoutSeconds 14400 -AllowFailure -Stream
        $clock.Stop();[IO.File]::WriteAllText($log,($build.stdout+$build.stderr))
        if($build.exitCode -ne 0){throw ('Local SDK application build failed; preserve '+$output)}
        # Use the existing producer's diagnostics policy after its authenticated toolkit bootstrap.
        & $script:local {param($v)Assert-CiLocalSdkConsumerSourcesCurrent $v} $inputState
        $diagnostics=Import-Module (Join-Path $inputState.Descriptor.Record.toolingBootstrap.root 'Build/BuildConsole.psm1') -PassThru
        $null=& $diagnostics {param($p)Assert-NativeBuildDiagnostics -LogPath $p} $log
        $executable=Assert-CiContainedPath $output (Join-Path $actual.OutDir $BuildContract.executable)
        if(-not [IO.File]::Exists($executable)){throw 'The local SDK application executable is missing from its owned output.'}
        $link=Get-CiLocalSdkLinkInput -IntermediateRoot $actual.IntDir -SdkRoot $inputState.SdkRoot -Platform $Platform
        $result=[ordered]@{schemaVersion=1;role='LocalUnpinnedApplicationBuild';recipe='LocalUnpinnedReleaseSdk';projectRoot=$root;sourceBytes=$inputState.SourceBytes;engineInputs=$inputState.EngineInputs;
            dependency=$inputState.Evidence;platform=$Platform;configuration='Release';outputRoot=$output;executable=$executable;executableSha256=(Get-FileHash -LiteralPath $executable).Hash.ToLowerInvariant();
            actualLinkInput=$link;buildElapsedMs=$clock.ElapsedMilliseconds;testsExecuted=$false;repositoryQualified=$false;productionQualified=$false}
        Stop-CiLocalSdkCompilerLease $inputState
        Close-CiLocalSdkConsumerInput $inputState
        $receipt=Join-Path $output 'local-unpinned-build.json'
        $stream=[IO.File]::Open($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($result|ConvertTo-Json -Depth 14));$stream.Write($bytes);$stream.Flush($true)}finally{$stream.Dispose()}
        $result.receipt=$receipt
    }catch{
        $failure=$_
        if($output -and [IO.Directory]::Exists($output)){
            try{[IO.File]::WriteAllText((Join-Path $output 'failure.json'),([ordered]@{role='LocalUnpinnedApplicationBuildFailure';passed=$false;error=$failure.Exception.Message;testsExecuted=$false;repositoryQualified=$false;productionQualified=$false}|ConvertTo-Json))}
            catch{Write-Warning ('Could not retain local build failure: '+$_.Exception.Message)}
        }
        throw
    }
    finally{
        if($frame -and -not $frame.Closed){try{Stop-CiLocalSdkCompilerLease $inputState}catch{if(-not $failure){$failure=$_}else{Write-Warning $_.Exception.Message}}}
        if(-not $inputState.Closed){try{Close-CiLocalSdkConsumerInput $inputState}catch{if(-not $failure){$failure=$_}else{Write-Warning $_.Exception.Message}}}
        if($null -ne $operation){$operation.Dispose()}
        if($failure -and $null -ne $result){$result=$null}
    }
    if($null -ne $failure){throw $failure}
    return [pscustomobject]$result
}

Export-ModuleMember -Function Invoke-CiLocalSdkApplicationBuild
