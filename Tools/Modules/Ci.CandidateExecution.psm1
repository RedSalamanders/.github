# Frozen shadow-execution inputs only; no test, required-check, merge or adoption authority.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.Candidate.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.Execution.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1')

function New-CiCandidateExecutionInputs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Candidate,
        [Parameter(Mandatory)][Collections.IDictionary]$Context,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$IsolationNonce,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ControllerWorkflowBlob)
    $schema=Join-Path $PSScriptRoot '../../Schemas/integration-candidate-inputs.schema.json'
    if(-not(Test-Json -Json ($Candidate|ConvertTo-Json -Depth 15) -SchemaFile $schema)){throw 'Malformed candidate input snapshot.'}
    $canonical=[ordered]@{}
    foreach($name in @('schemaVersion','role','repository','pullRequest','headRepository','headCommit','baseCommit',
        'mergeCommit','mergeTree','controllerEngineRef','input','baseNativeDigest','nativeRequired')){$canonical[$name]=$Candidate[$name]}
    if((Get-CiSha256 ($canonical|ConvertTo-Json -Depth 15 -Compress)) -cne $Candidate.identity){throw 'Candidate snapshot identity changed.'}
    $keys=@('repository','event','ref','commit','workflowRef','runId','runAttempt')
    if($Context.Count -ne $keys.Count){throw 'Execution context must retain exactly the reviewed fields.'}
    foreach($name in $keys){if(-not $Context.Contains($name)){throw "Execution context missing: $name"}}
    foreach($name in @('repository','event','ref','commit','workflowRef','runId')){
        if($Context[$name] -isnot [string]){throw "Execution context is not a string: $name"}
    }
    if(($Context.runAttempt -isnot [int] -and $Context.runAttempt -isnot [long]) -or
        $Context.runAttempt -lt 1 -or $Context.runAttempt -gt 100000 -or $Context.runId -cnotmatch '^[1-9][0-9]{0,19}$'){
        throw 'Execution context requires an exact producer run and attempt.'
    }
    $branch='refs/heads/ci-native/pr'+$Candidate.pullRequest+'/'+$Candidate.identity+'/'+$IsolationNonce
    if($Context.repository -cne $Candidate.repository -or $Context.event -cne 'workflow_dispatch' -or
        $Context.ref -cne $branch -or $Context.commit -cne $Candidate.baseCommit -or
        $Context.workflowRef -cne ($Candidate.repository+'/.github/workflows/integration-execution.yml@'+$branch)){
        throw 'Shadow execution requires its exact isolated branch at the frozen trusted main controller.'
    }
    if($Candidate.headRepository -cne $Candidate.repository){throw 'Foreign/fork candidate execution is not enabled.'}
    if($Candidate.input.repository -cne $Candidate.repository -or $Candidate.input.commit -cne $Candidate.mergeCommit -or
        $Candidate.controllerEngineRef -ceq ('0'*40) -or $Candidate.input.engine.ref -cne $Candidate.controllerEngineRef -or
        $Candidate.nativeRequired -ne ($Candidate.input.nativeDigest -cne $Candidate.baseNativeDigest)){
        throw 'Candidate repository, source, engine or obligation binding differs.'
    }
    $batch=$Candidate.input|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
    $batch.runId=$Context.runId
    $null=Get-CiNativeExecutionBinding -Descriptor $batch -RunId $Context.runId -RunAttempt ([int]$Context.runAttempt)
    $canonical.identity=$Candidate.identity
    return [ordered]@{schemaVersion=1;role='CandidateExecutionInputs';repository=$Candidate.repository;
        controllerCommit=$Context.commit;controllerWorkflowBlob=$ControllerWorkflowBlob;isolationRef=$branch;
        runId=$Context.runId;runAttempt=[int]$Context.runAttempt;candidate=$canonical;batch=$batch;
        nativeExecutions=0;suppliesNativeVerdict=$false}
}

function Get-CiCandidateExecutionInputs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedIdentity,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$IsolationNonce)
    $project=Read-CiProject $Root
    $context=[ordered]@{repository=$env:GITHUB_REPOSITORY;event=$env:GITHUB_EVENT_NAME;ref=$env:GITHUB_REF;
        commit=$env:GITHUB_SHA;workflowRef=$env:GITHUB_WORKFLOW_REF;runId=$env:GITHUB_RUN_ID;runAttempt=0}
    $runAttempt=0
    $branch='refs/heads/ci-native/pr'+$PullRequest+'/'+$ExpectedIdentity+'/'+$IsolationNonce
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
        $context.repository -cne $project.repository -or $context.event -cne 'workflow_dispatch' -or
        $context.ref -cne $branch -or $context.commit -cnotmatch '^[a-f0-9]{40}$' -or
        $context.runId -cnotmatch '^[1-9][0-9]{0,19}$' -or
        $context.workflowRef -cne ($project.repository+'/.github/workflows/integration-execution.yml@'+$branch) -or
        -not [int]::TryParse($env:GITHUB_RUN_ATTEMPT,[ref]$runAttempt) -or $runAttempt -lt 1 -or $runAttempt -gt 100000){
        throw 'Use the exact hosted manual isolated-branch workflow; no remote request or output is permitted.'
    }
    $context.runAttempt=$runAttempt
    if((Resolve-CiCommit $Root HEAD) -cne $context.commit -or
        (Invoke-CiGit $Root @('status','--porcelain','--untracked-files=all')).stdout.Trim()){
        throw 'Controller checkout differs from its exact clean workflow commit.'
    }
    $main=Get-CiMainHead $project.repository
    if($main -cne $context.commit){throw 'Trusted main advanced before candidate acquisition.'}
    $candidate=Get-CiIntegrationCandidate -Root $Root -PullRequest $PullRequest
    if($candidate.identity -cne $ExpectedIdentity -or $candidate.baseCommit -cne $main -or
        $candidate.input.engine.ref -cne $project.engine.ref){throw 'Candidate or reviewed main engine changed before execution.'}
    $ref=Invoke-CiApi ('repos/'+$project.repository+'/git/ref/'+$branch.Substring(5)) -Method GET
    if($ref.ref -cne $branch -or $ref.object.type -cne 'commit' -or $ref.object.sha -cne $main){throw 'Isolated branch does not point to the trusted controller.'}
    $workflowPath='.github/workflows/integration-execution.yml'
    $workflow=Invoke-CiApi ('repos/'+$project.repository+'/contents/'+$workflowPath+'?ref='+$main) -Method GET
    $blob=(Invoke-CiGit $Root @('rev-parse',($main+':'+$workflowPath))).stdout.Trim()
    if($workflow.path -cne $workflowPath -or $workflow.sha -cne $blob){throw 'Controller caller bytes differ from independent Git/API objects.'}
    # Reuse the complete public acquisition/recheck, including independent Git refs;
    # no second partial implementation of candidate-race validation is permitted.
    $after=Get-CiIntegrationCandidate -Root $Root -PullRequest $PullRequest
    if(($after|ConvertTo-Json -Depth 15 -Compress) -cne ($candidate|ConvertTo-Json -Depth 15 -Compress) -or
        (Get-CiMainHead $project.repository) -cne $main){throw 'Candidate/main changed during isolated execution acquisition.'}
    $refAfter=Invoke-CiApi ('repos/'+$project.repository+'/git/ref/'+$branch.Substring(5)) -Method GET
    if($refAfter.ref -cne $branch -or $refAfter.object.type -cne 'commit' -or $refAfter.object.sha -cne $main){throw 'Isolated controller ref moved during acquisition.'}
    return New-CiCandidateExecutionInputs -Candidate $candidate -Context $context -IsolationNonce $IsolationNonce -ControllerWorkflowBlob $blob
}

Export-ModuleMember -Function New-CiCandidateExecutionInputs,Get-CiCandidateExecutionInputs
