# Hosted main or bound isolated test-build dependency inputs; acceptance remains with the application.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.Project.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkProducer.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkTransport.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkQualifiedTransport.psm1')

function Get-CiDistributedSdkRequest {
    param([string]$SourceCommit,[int]$ApiRevision)
    $json=Get-Content (Join-Path $PSScriptRoot '../../Policy/sdk-distribution.json') -Raw
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/sdk-distribution.schema.json'))){throw 'Invalid SDK distribution policy.'}
    $policy=$json|ConvertFrom-Json
    $producer=Read-CiSdkProducerPolicy
    foreach($group in @($policy.entries|Group-Object sourceCommit)){
        if($group.Count -ne 1){throw 'SDK distribution contains ambiguous source entries.'}
        $entry=$group.Group[0]
        if(@($producer.sources|Where-Object{$_.commit -ceq $entry.sourceCommit -and $_.apiRevision -eq $entry.apiRevision}).Count -ne 1){throw 'SDK distribution cannot advance a reviewed producer source/API.'}
    }
    $selected=@($policy.entries|Where-Object{$_.sourceCommit -ceq $SourceCommit -and $_.apiRevision -eq $ApiRevision})
    if($selected.Count -eq 0){return $null}
    return $selected[0]
}

function New-CiSdkPreparationCheckout {
    param([string]$Workspace,[string]$Destination,[string]$Repository,[string]$Commit)
    $path=Assert-CiContainedPath $Workspace $Destination
    if(Test-Path -LiteralPath $path){throw 'SDK preparation never replaces an existing checkout.'}
    if($Repository -cnotin @('RedSalamanders/DxUi','RedSalamanders/.github') -or $Commit -cnotmatch '^[a-f0-9]{40}$'){throw 'Unreviewed SDK checkout request.'}
    [void](Invoke-CiProcess -FilePath git -Arguments @('-c','core.longpaths=true','clone','--no-checkout','--',"https://github.com/$Repository.git",$path) -WorkingDirectory $Workspace -TimeoutSeconds 600)
    foreach($pair in @(@('core.longpaths','true'),@('core.autocrlf','true'))){[void](Invoke-CiGit $path @('config',$pair[0],$pair[1]))}
    [void](Invoke-CiGit $path @('checkout','--detach',$Commit))
    return $path
}

function Write-CiSdkPreparationEvidence {
    param([Collections.IDictionary]$Context,[Collections.IDictionary]$Record)
    $directory=Assert-CiContainedPath $Context.root (Join-Path $Context.root '.build/evidence/sdk-input-preparation')
    [void][IO.Directory]::CreateDirectory($directory)
    $path=Join-Path $directory ([guid]::NewGuid().ToString('N')+'.json')
    $document=[ordered]@{schemaVersion=1;role='DependencySdkPreparation';phase=$Context.phase;platform=$Context.platform;record=$Record}
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($document|ConvertTo-Json -Depth 8))
        $stream.Write($bytes);$stream.Flush($true)
    }finally{$stream.Dispose()}
    Write-Host "SDK input preparation evidence: $path"
}

function New-CiPinnedSdkInputDescriptor {
    param([string]$SourceCommit,[int]$ApiRevision,[string]$Platform,[string]$SourceRoot,
        [string]$ToolingRoot,[string]$StorageEngineRoot,[string]$StoreRoot,[string]$ManifestSha256)
    $descriptor=[ordered]@{schemaVersion=1;role='LocalPinnedDependencyInput';sourceCommit=$SourceCommit;apiRevision=$ApiRevision;platform=$Platform;
        sourceRoot=$SourceRoot;toolingRoot=$ToolingRoot;storageEngineRoot=$StorageEngineRoot;storeRoot=$StoreRoot;manifestSha256=$ManifestSha256}
    if(-not(Test-Json -Json ($descriptor|ConvertTo-Json) -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/sdk-consumer-local.schema.json'))){throw 'Prepared SDK descriptor does not match the shared reader contract.'}
    return $descriptor
}

function New-CiQualifiedSdkInputDescriptor {
    param([string]$SourceCommit,[int]$ApiRevision,[string]$Platform,[string]$SourceRoot,[string]$ToolingRoot,
        [string]$StorageEngineRoot,[string]$StoreRoot,[string]$ProducerRun,[int]$Attempt,$Imported)
    $descriptor=[ordered]@{schemaVersion=2;role='HostedQualifiedDependencyInput';sourceCommit=$SourceCommit;apiRevision=$ApiRevision;platform=$Platform;
        sourceRoot=$SourceRoot;toolingRoot=$ToolingRoot;storageEngineRoot=$StorageEngineRoot;storeRoot=$StoreRoot;manifestSha256=$Imported.Entry.ManifestSha256;
        producerRun=$ProducerRun;attempt=$Attempt;archivePath=$Imported.ArchivePath;entryPath=$Imported.EntryPath;referencePath=$Imported.ReferencePath;receiptPath=$Imported.ReceiptPath}
    if(-not(Test-Json -Json ($descriptor|ConvertTo-Json) -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/sdk-consumer-qualified.schema.json'))){throw 'Invalid prepared qualified SDK descriptor.'}
    return $descriptor
}

function Initialize-CiPinnedSdkInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Context,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$SourceCommit,
        [Parameter(Mandatory)][ValidateRange(1,65535)][int]$ApiRevision)
    # A verified isolated candidate may read the same immutable dependency inputs.
    # It never receives a main cache scope or a production role.
    $main=$env:GITHUB_REF -ceq 'refs/heads/main'
    $candidate=$false
    if($Context.phase -ceq 'ReleaseTestBuild' -and $env:GITHUB_REF -clike 'refs/heads/ci-native/*'){
        Import-Module (Join-Path $PSScriptRoot 'Ci.CandidateExecution.psm1')
        $candidate=Assert-CiCandidateExecutionBatch -Descriptor $Context.batch
    }
    # Do not give PR code a main/cache writer context, or emulate hosted admission locally.
    if($env:CI_NATIVE_BUILDS_DISABLED -eq 'true' -or -not $IsWindows -or $env:GITHUB_ACTIONS -cne 'true' -or
        $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or (-not $main -and -not $candidate) -or
        $Context.phase -cnotin @('ReleaseTestBuild','Production')){throw 'Automatic SDK preparation requires admitted hosted main Release builds or a bound isolated candidate test build.'}
    $native=if($Context.platform -ceq 'x64'){'X64'}elseif($Context.platform -ceq 'ARM64'){'Arm64'}else{throw 'Invalid native SDK platform.'}
    if([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -cne $native -or
        [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString() -cne $native){throw 'SDK preparation requires the matching native host.'}
    if($env:GITHUB_REPOSITORY -cne $Context.project.repository -or $Context.project.kind -cne 'application' -or
        (Resolve-CiCommit $Context.engineRoot HEAD) -cne $Context.project.engine.ref -or
        (Invoke-CiGit $Context.engineRoot @('status','--porcelain','--untracked-files=all')).stdout.Trim()){
        throw 'SDK preparation needs the exact admitted application and clean pinned controller.'
    }
    $lock=Get-Content (Join-Path $Context.root 'Dependencies/DxUi.lock.json') -Raw|ConvertFrom-Json
    if($lock.repository -cne 'https://github.com/RedSalamanders/DxUi' -or $lock.commit -cne $SourceCommit -or
        $lock.apiRevision -ne $ApiRevision -or @($lock.targets).Count -ne 1 -or $lock.targets[0] -cne 'DxUi'){
        throw 'SDK preparation cannot change the actual application dependency lock.'
    }
    $request=Get-CiDistributedSdkRequest $SourceCommit $ApiRevision
    if($null -eq $request){
        Write-CiSdkPreparationEvidence $Context @{status='NotDistributed';sourceCommit=$SourceCommit;apiRevision=$ApiRevision}
        Write-Host 'No distributed SDK at the exact application pin; retain the governed source recipe.';return $null
    }
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $parent=Assert-CiContainedPath $Context.root (Join-Path $Context.root '.build/sdk-preparation')
    $workspace=Assert-CiContainedPath $parent (Join-Path $parent ([guid]::NewGuid().ToString('N')))
    [void][IO.Directory]::CreateDirectory($workspace)
    $batchPath=Join-Path $workspace 'admitted-batch.json'
    [IO.File]::WriteAllText($batchPath,($Context.batch|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    [void](New-CiProjectContext -Root $Context.root -EngineRoot $Context.engineRoot -Phase $Context.phase -Platform $Context.platform -Descriptor $batchPath)
    $producer=Read-CiSdkProducerPolicy
    $sourcePolicy=@($producer.sources|Where-Object{$_.commit -ceq $SourceCommit -and $_.apiRevision -eq $ApiRevision})[0]
    $bootstrap=@{sourceCommit=$SourceCommit;apiRevision=$ApiRevision;sourceContentIdentity=$sourcePolicy.contentIdentity;
        toolingRef=$producer.toolingRef;toolingContentIdentity=$producer.toolingContentIdentity;
        storageEngineRef=$producer.storageEngineRef;storageEngineContentIdentity=$producer.storageEngineContentIdentity}
    $prompt=[Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT','Process')
    try{
        $env:GIT_TERMINAL_PROMPT='0'
        $source=New-CiSdkPreparationCheckout $workspace (Join-Path $workspace 'source') RedSalamanders/DxUi $SourceCommit
        $tooling=New-CiSdkPreparationCheckout $workspace (Join-Path $workspace 'tooling') RedSalamanders/DxUi $producer.toolingRef
        $storage=New-CiSdkPreparationCheckout $workspace (Join-Path $tooling '.ci-engine') RedSalamanders/.github $producer.storageEngineRef
    }finally{[Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT',$prompt,'Process')}
    Assert-CiSdkProducerCheckouts -Request $bootstrap -SourceRoot $source -ToolingRoot $tooling -StorageEngineRoot $storage
    if($request.PSObject.Properties['contract'] -and $request.contract -ceq 'QualifiedAbiV2'){
        # The independently authenticated producer reference supplies its original
        # build recipe. Consumers prove actual ABI/tool bytes when opening it;
        # do not restore/rebuild that producer's package inventory here.
        $store=Assert-CiContainedPath $Context.root (Join-Path $Context.root '.build/sdk-input-store')
        Write-CiSdkPreparationEvidence $Context @{status='QualifiedRequested';workspace=$workspace;producerRun=$request.runId;attempt=$request.attempt}
        $imported=Import-CiQualifiedHostedSdkArtifact -RepositoryRoot $Context.root -StoreRoot $store -DownloadRoot (Join-Path $workspace 'downloads') `
            -SourceCommit $SourceCommit -ApiRevision $ApiRevision -Platform $Context.platform -RunId $request.runId -Attempt $request.attempt
        [void](New-CiProjectContext -Root $Context.root -EngineRoot $Context.engineRoot -Phase $Context.phase -Platform $Context.platform -Descriptor $batchPath)
        $descriptor=New-CiQualifiedSdkInputDescriptor -SourceCommit $SourceCommit -ApiRevision $ApiRevision -Platform $Context.platform -SourceRoot $source -ToolingRoot $tooling `
            -StorageEngineRoot $storage -StoreRoot $store -ProducerRun $request.runId -Attempt $request.attempt -Imported $imported
        $path=Join-Path $workspace 'descriptor.json'
        [IO.File]::WriteAllText($path,($descriptor|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
        Write-CiSdkPreparationEvidence $Context @{status='QualifiedPrepared';workspace=$workspace;producerRun=$request.runId;attempt=$request.attempt;
            key=$imported.Entry.Key;manifestSha256=$imported.Entry.ManifestSha256;elapsedMs=$timer.ElapsedMilliseconds}
        return $path
    }
    # Only independently authenticated source code may now execute. This restores package inputs, not DxUi.lib.
    [void](Invoke-CiProcess -FilePath pwsh -Arguments @('-NoProfile','-NonInteractive','-File',(Join-Path $source 'vcpkg-install.ps1'),'-Platform',$Context.platform) -WorkingDirectory $source -TimeoutSeconds 1800 -Stream)
    $inputs=Import-Module (Join-Path $tooling 'Tools/SdkCacheInputs.psm1') -PassThru
    $identity=& $inputs {param($r,$p) Get-DxUiSdkCacheInputIdentity -Root $r -Platform $p} $source $Context.platform
    Write-CiSdkPreparationEvidence $Context @{status='Requested';workspace=$workspace;producerRun=$request.runId;attempt=$request.attempt;expectedIdentity=$identity}
    # Transport demands this actual recipe, not the remote artifact's self-declared compiler inputs.
    $store=Assert-CiContainedPath $Context.root (Join-Path $Context.root '.build/sdk-input-store')
    $entry=Import-CiHostedSdkArtifact -RepositoryRoot $Context.root -StoreRoot $store -DownloadRoot (Join-Path $workspace 'downloads') -Identity $identity -RunId $request.runId -Attempt $request.attempt
    [void](New-CiProjectContext -Root $Context.root -EngineRoot $Context.engineRoot -Phase $Context.phase -Platform $Context.platform -Descriptor $batchPath)
    if($null -eq $entry){
        Write-CiSdkPreparationEvidence $Context @{status='ExactInputMiss';workspace=$workspace;producerRun=$request.runId;attempt=$request.attempt;expectedIdentity=$identity;elapsedMs=$timer.ElapsedMilliseconds}
        Write-Host 'No exact compatible SDK input; retain the governed source recipe.';return $null
    }
    $descriptor=New-CiPinnedSdkInputDescriptor -SourceCommit $SourceCommit -ApiRevision $ApiRevision -Platform $Context.platform `
        -SourceRoot $source -ToolingRoot $tooling -StorageEngineRoot $storage -StoreRoot $store -ManifestSha256 $entry.ManifestSha256
    $json=$descriptor|ConvertTo-Json -Depth 3
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/sdk-consumer-local.schema.json'))){throw 'Prepared SDK descriptor does not match the shared reader contract.'}
    $path=Join-Path $workspace 'descriptor.json';[IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $workspace 'preparation.json'),([ordered]@{role='PinnedSdkInputPrepared';key=$entry.Key;elapsedMs=$timer.ElapsedMilliseconds;producerRun=$request.runId;attempt=$request.attempt}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Write-CiSdkPreparationEvidence $Context @{status='Prepared';workspace=$workspace;producerRun=$request.runId;attempt=$request.attempt;key=$entry.Key;manifestSha256=$entry.ManifestSha256;elapsedMs=$timer.ElapsedMilliseconds}
    return $path
}

Export-ModuleMember -Function Initialize-CiPinnedSdkInput
