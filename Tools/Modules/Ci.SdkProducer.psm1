# Manual dependency-input producer admission only. No product qualification, main state or publication.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')

function Read-CiSdkProducerPolicy {
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $json=[IO.File]::ReadAllText((Join-Path $root 'Policy/sdk-producer.json'))
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $root 'Schemas/sdk-producer-policy.schema.json'))){throw 'Invalid SDK producer policy.'}
    $policy=$json|ConvertFrom-Json -AsHashtable
    if(@($policy.sources.commit|Sort-Object -Unique).Count -ne $policy.sources.Count){throw 'SDK source pins must be unique.'}
    return $policy
}

function Resolve-CiSdkProducerRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string]$Ref,[Parameter(Mandatory)][string]$Event,
        [Parameter(Mandatory)][string]$SourceCommit,[Parameter(Mandatory)][string]$RunId,[ValidateSet('All','x64','ARM64')][string]$Platform='All')
    $policy=Read-CiSdkProducerPolicy
    if($Repository -cne $policy.repository -or $Ref -cne 'refs/heads/main' -or $Event -cne 'workflow_dispatch' -or
        $RunId -cnotmatch '^[1-9][0-9]{0,19}$'){throw 'SDK input production requires an explicit DxUi main dispatch.'}
    $source=@($policy.sources|Where-Object{$_.commit -ceq $SourceCommit})
    if($source.Count -ne 1){throw 'Requested source is not an exact reviewed SDK pin.'}
    $platforms=if($Platform -ceq 'All'){@('x64','ARM64')}else{@($Platform)}
    return [ordered]@{sourceCommit=$SourceCommit;apiRevision=$source[0].apiRevision;toolingRef=$policy.toolingRef;
        storageEngineRef=$policy.storageEngineRef;version=('0.1.'+$RunId);
        matrix=@{include=@($platforms|ForEach-Object{@{platform=$_;runner=if($_ -ceq 'x64'){'windows-2025-vs2026'}else{'windows-11-vs2026-arm'}}})}}
}

function Assert-CiSdkProducerCheckouts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Request,[Parameter(Mandatory)][string]$ToolingRoot,
        [Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$StorageEngineRoot)
    foreach($entry in @(@($ToolingRoot,$Request.toolingRef),@($SourceRoot,$Request.sourceCommit),@($StorageEngineRoot,$Request.storageEngineRef))){
        $head=(Invoke-CiGit $entry[0] @('rev-parse','--verify','HEAD')).stdout.Trim()
        $dirty=(Invoke-CiGit $entry[0] @('status','--porcelain','--untracked-files=all')).stdout.Trim()
        if($head -cne $entry[1] -or $dirty){throw 'SDK producer requires exact clean source, tooling and storage-engine checkouts.'}
    }
    # A policy may name a reviewed PR source while it is being prepared. Native setup must wait until normal integration.
    $ancestry=Invoke-CiProcess -FilePath git -Arguments @('-C',$ToolingRoot,'merge-base','--is-ancestor',$Request.toolingRef,'refs/remotes/origin/main') -WorkingDirectory $ToolingRoot -AllowFailure
    if($ancestry.exitCode -ne 0){throw 'SDK producer tooling has not integrated into its main branch.'}
    $source=Get-Content (Join-Path $SourceRoot 'capabilities.json') -Raw|ConvertFrom-Json
    $tooling=Get-Content (Join-Path $ToolingRoot '.ci/project.json') -Raw|ConvertFrom-Json
    if($source.apiRevision -ne $Request.apiRevision -or $tooling.repository -cne 'RedSalamanders/DxUi' -or
        $tooling.engine.repository -cne 'RedSalamanders/.github' -or $tooling.engine.ref -cne $Request.storageEngineRef){throw 'SDK source API or producer storage-engine policy differs.'}
}

Export-ModuleMember -Function Read-CiSdkProducerPolicy,Resolve-CiSdkProducerRequest,Assert-CiSdkProducerCheckouts
