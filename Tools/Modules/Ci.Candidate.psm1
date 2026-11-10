# Input freeze only. No native execution, delegated obligation, result adoption or merge authority.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1')

function Get-CiCandidatePullMetadata {
    param([object]$PullRequest,[string]$Repository)
    if($PullRequest.number -isnot [int] -and $PullRequest.number -isnot [long]){throw 'Candidate PR number is not an integer.'}
    if($PullRequest.number -lt 1 -or $PullRequest.number -gt 2147483647 -or $PullRequest.state -cne 'open' -or
        $PullRequest.draft -isnot [bool] -or $PullRequest.draft -or $PullRequest.merged -isnot [bool] -or $PullRequest.merged -or
        $PullRequest.mergeable -isnot [bool] -or -not $PullRequest.mergeable -or
        $PullRequest.base.ref -cne 'main' -or $PullRequest.base.repo.full_name -cne $Repository){throw 'Candidate requires one open, ready, mergeable main-targeting PR; unknown mergeability refuses.'}
    foreach($sha in @($PullRequest.base.sha,$PullRequest.head.sha,$PullRequest.merge_commit_sha)){
        if([string]$sha -cnotmatch '^[a-f0-9]{40}$'){throw 'Candidate requires exact base/head/synthetic-merge commits.'}
    }
    if([string]$PullRequest.head.repo.full_name -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'){throw 'Candidate head repository is missing or malformed.'}
    return [ordered]@{number=[int]$PullRequest.number;headRepository=[string]$PullRequest.head.repo.full_name;
        head=[string]$PullRequest.head.sha;base=[string]$PullRequest.base.sha;merge=[string]$PullRequest.merge_commit_sha}
}

function New-CiIntegrationCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][object]$PullRequest,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$CurrentMainCommit,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$MergeCommit,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ControllerEngineRef)
    if($Repository -cnotmatch '^RedSalamanders/(RedSalamander|DxUi|RedXe|RedPrism|RedTilde|RedMonitor)$'){throw 'Candidate repository is outside the reviewed projects.'}
    $pr=Get-CiCandidatePullMetadata $PullRequest $Repository
    if($pr.base -cne $CurrentMainCommit -or $pr.merge -cne $MergeCommit){throw 'Candidate API/base/merge ref moved; reacquire the exact integration.'}
    $base=Resolve-CiCommit $Root $CurrentMainCommit
    $head=Resolve-CiCommit $Root $pr.head
    $merge=Resolve-CiCommit $Root $MergeCommit
    $parents=((Invoke-CiGit $Root @('show','-s','--format=%P',$merge)).stdout.Trim() -split ' ')
    if($parents.Count -ne 2 -or $parents[0] -cne $base -or $parents[1] -cne $head){throw 'Synthetic merge parents do not match the actual frozen base and PR head.'}
    $input=New-CiInputDescriptor -Root $Root -Ref $merge
    $baseline=New-CiInputDescriptor -Root $Root -Ref $base
    if($input.repository -cne $Repository -or $baseline.repository -cne $Repository){throw 'Candidate source manifests belong to another repository.'}
    $tree=(Invoke-CiGit $Root @('rev-parse',($merge+'^{tree}'))).stdout.Trim()
    $candidate=[ordered]@{schemaVersion=1;role='IntegrationCandidateInputs';repository=$Repository;pullRequest=$pr.number;
        headRepository=$pr.headRepository;headCommit=$head;baseCommit=$base;mergeCommit=$merge;mergeTree=$tree;
        controllerEngineRef=$ControllerEngineRef;input=$input;baseNativeDigest=$baseline.nativeDigest;
        nativeRequired=($input.nativeDigest -cne $baseline.nativeDigest)}
    $candidate.identity=Get-CiSha256 ($candidate|ConvertTo-Json -Depth 15 -Compress)
    $schema=Join-Path $PSScriptRoot '../../Schemas/integration-candidate-inputs.schema.json'
    if(-not(Test-Json -Json ($candidate|ConvertTo-Json -Depth 15) -SchemaFile $schema)){throw 'Candidate input descriptor does not match its strict data-only schema.'}
    return $candidate
}

function Assert-CiIntegrationCandidateCurrent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][Collections.IDictionary]$Candidate,
        [Parameter(Mandatory)][object]$PullRequest,[Parameter(Mandatory)][string]$CurrentMainCommit,[Parameter(Mandatory)][string]$MergeCommit,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ControllerEngineRef)
    $fresh=New-CiIntegrationCandidate -Root $Root -Repository $Candidate.repository -PullRequest $PullRequest `
        -CurrentMainCommit $CurrentMainCommit -MergeCommit $MergeCommit -ControllerEngineRef $ControllerEngineRef
    # Compare complete canonical data as well as its digest. A supplied/recomputed digest alone grants nothing.
    if(($fresh|ConvertTo-Json -Depth 15 -Compress) -cne ($Candidate|ConvertTo-Json -Depth 15 -Compress)){throw 'Frozen candidate inputs changed or were modified; no execution/adoption may be inferred.'}
}

function Get-CiIntegrationCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest)
    $engine=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $controller=Resolve-CiCommit $engine HEAD
    if((Invoke-CiGit $engine @('status','--porcelain','--untracked-files=all')).stdout.Trim()){throw 'Use a clean committed controller for candidate provenance.'}
    $project=Read-CiProject $Root
    $repo=$project.repository
    $remote=(Invoke-CiGit $Root @('remote','get-url','origin')).stdout.Trim().TrimEnd('/')
    if($remote -ine "https://github.com/$repo" -and $remote -ine "https://github.com/$repo.git" -and
        $remote -ine "git@github.com:$repo.git" -and $remote -ine "ssh://git@github.com/$repo.git"){throw 'Candidate fetch requires the exact reviewed GitHub origin.'}
    $before=Invoke-CiApi "repos/$repo/pulls/$PullRequest" -Method GET
    $main=Get-CiMainHead $repo
    $metadata=Get-CiCandidatePullMetadata $before $repo
    if($metadata.number -ne $PullRequest -or $metadata.base -cne $main){throw 'PR/base API snapshots disagree; no candidate was frozen.'}
    $prefix='refs/ci/candidates/'+$PullRequest+'/'+[guid]::NewGuid().ToString('N')
    $savedPrompt=[Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT','Process')
    try{
        $env:GIT_TERMINAL_PROMPT='0'
        $null=Invoke-CiGit $Root @('fetch','--no-tags','origin',('refs/heads/main:'+$prefix+'/main'),
            ('refs/pull/'+$PullRequest+'/head:'+$prefix+'/head'),('refs/pull/'+$PullRequest+'/merge:'+$prefix+'/merge'))
    }finally{[Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT',$savedPrompt,'Process')}
    $fetchedMain=Resolve-CiCommit $Root ($prefix+'/main')
    $fetchedHead=Resolve-CiCommit $Root ($prefix+'/head')
    $fetchedMerge=Resolve-CiCommit $Root ($prefix+'/merge')
    if($fetchedMain -cne $main -or $fetchedHead -cne $metadata.head -or $fetchedMerge -cne $metadata.merge){throw 'Candidate refs moved during acquisition; captured refs remain for diagnosis.'}
    $candidate=New-CiIntegrationCandidate -Root $Root -Repository $repo -PullRequest $before -CurrentMainCommit $main -MergeCommit $fetchedMerge -ControllerEngineRef $controller
    $after=Invoke-CiApi "repos/$repo/pulls/$PullRequest" -Method GET
    $mainAfter=Get-CiMainHead $repo
    Assert-CiIntegrationCandidateCurrent -Root $Root -Candidate $candidate -PullRequest $after -CurrentMainCommit $mainAfter -MergeCommit $fetchedMerge -ControllerEngineRef $controller
    return $candidate
}

Export-ModuleMember -Function New-CiIntegrationCandidate,Assert-CiIntegrationCandidateCurrent,Get-CiIntegrationCandidate
