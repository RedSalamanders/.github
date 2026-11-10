# Trusted operator admission only. Never execute candidate content or write a merge verdict.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Candidate.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.Project.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1')

function Write-CiCandidateDispatchEvent {
    param([string]$Directory,[string]$Stage,[Collections.IDictionary]$Request)
    # Append-only operation journal: unlike SDK preparation diagnostics, these
    # fixed stages retain exactly which remote writes completed before a refusal.
    $path=Assert-CiContainedPath $Directory (Join-Path $Directory ($Stage+'.json'))
    $record=[ordered]@{schemaVersion=1;role='CandidateShadowDispatchEvent';stage=$Stage;
        recordedUtc=[DateTimeOffset]::UtcNow.ToString('o');request=$Request}
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Depth 20))
        $stream.Write($bytes);$stream.Flush($true)
    }finally{$stream.Dispose()}
}

function Start-CiCandidateShadow {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
    param([Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedIdentity)
    $Root=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path)
    $engine=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $project=Read-CiProject $Root
    $controller=Resolve-CiCommit $engine HEAD
    if($controller -cne $project.engine.ref -or
        (Invoke-CiGit $engine @('status','--porcelain','--untracked-files=all')).stdout.Trim()){
        throw 'Admission requires the exact clean reviewed project engine.'
    }
    $main=Get-CiMainHead $project.repository
    if((Resolve-CiCommit $Root HEAD) -cne $main -or
        (Invoke-CiGit $Root @('status','--porcelain','--untracked-files=all')).stdout.Trim()){
        throw 'Use a clean exact current main controller checkout; no remote writes occurred.'
    }
    Test-CiProjectConfiguration -Context @{root=$Root;engineRoot=$engine;project=$project;development=$false}
    $candidate=Get-CiIntegrationCandidate -Root $Root -PullRequest $PullRequest
    if($candidate.identity -cne $ExpectedIdentity -or $candidate.baseCommit -cne $main -or
        $candidate.headRepository -cne $project.repository -or $candidate.input.engine.ref -cne $controller){
        throw 'Candidate identity, base, repository or reviewed engine changed before admission.'
    }
    $workflowPath='.github/workflows/integration-execution.yml'
    $workflow=Invoke-CiApi ('repos/'+$project.repository+'/contents/'+$workflowPath+'?ref='+$main) -Method GET
    $blob=(Invoke-CiGit $Root @('rev-parse',($main+':'+$workflowPath))).stdout.Trim()
    if($workflow.path -cne $workflowPath -or $workflow.sha -cne $blob){throw 'Admission caller bytes differ from independent main Git/API objects.'}
    $nonce=[guid]::NewGuid().ToString('N')
    $branch='refs/heads/ci-native/pr'+$PullRequest+'/'+$ExpectedIdentity+'/'+$nonce
    $request=[ordered]@{schemaVersion=1;role='CandidateShadowDispatchRequest';repository=$project.repository;
        controllerCommit=$main;controllerEngineRef=$controller;controllerWorkflowBlob=$blob;
        candidate=$candidate;isolationNonce=$nonce;isolationRef=$branch;nativeExecutions=0;suppliesNativeVerdict=$false}
    if(-not $candidate.nativeRequired){$request.stage='NoNativeRequired';return $request}
    if(-not $PSCmdlet.ShouldProcess($project.repository,('Create '+$branch+' at trusted main and dispatch native shadow'))){
        $request.stage='Preview';return $request
    }
    $directory=Assert-CiContainedPath $Root (Join-Path $Root ('.build/ci/candidate-requests/'+$nonce))
    if(Test-Path -LiteralPath $directory){throw 'Admission journal already exists; never replace an earlier request.'}
    [void][IO.Directory]::CreateDirectory($directory)
    $request.journalDirectory=$directory
    Write-CiCandidateDispatchEvent $directory '01-frozen' $request
    $after=Get-CiIntegrationCandidate -Root $Root -PullRequest $PullRequest
    if(($after|ConvertTo-Json -Depth 15 -Compress) -cne ($candidate|ConvertTo-Json -Depth 15 -Compress) -or
        (Get-CiMainHead $project.repository) -cne $main){throw 'Candidate/main moved before branch creation; frozen journal retained.'}
    $created=Invoke-CiApi ('repos/'+$project.repository+'/git/refs') -Method POST -Body @{ref=$branch;sha=$main}
    if($created.ref -cne $branch -or $created.object.type -cne 'commit' -or $created.object.sha -cne $main){
        throw 'Isolated ref creation did not confirm the trusted controller; no dispatch was requested.'
    }
    Write-CiCandidateDispatchEvent $directory '02-ref-created' $request
    $after=Get-CiIntegrationCandidate -Root $Root -PullRequest $PullRequest
    $ref=Invoke-CiApi ('repos/'+$project.repository+'/git/ref/'+$branch.Substring(5)) -Method GET
    if(($after|ConvertTo-Json -Depth 15 -Compress) -cne ($candidate|ConvertTo-Json -Depth 15 -Compress) -or
        (Get-CiMainHead $project.repository) -cne $main -or $ref.ref -cne $branch -or
        $ref.object.type -cne 'commit' -or $ref.object.sha -cne $main){
        throw 'Candidate, main or isolated ref moved before dispatch; original ref and journal retained.'
    }
    $null=Invoke-CiApi ('repos/'+$project.repository+'/actions/workflows/integration-execution.yml/dispatches') -Method POST -Body @{
        ref=$branch.Substring(11);inputs=@{pull_request=[string]$PullRequest;identity=$ExpectedIdentity;nonce=$nonce}}
    Write-CiCandidateDispatchEvent $directory '03-dispatch-requested' $request
    $request.stage='DispatchRequested'
    return $request
}

Export-ModuleMember -Function Start-CiCandidateShadow
