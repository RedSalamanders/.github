# Recording GitHub metadata fixtures only; never native producer/pass evidence.
Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.CandidateResults.psm1')
$candidateResults=Get-Module Ci.CandidateResults

function New-CandidateResultFixture([string]$Name){
    $f=New-CandidateFixture $Name -ShadowCaller
    $candidate=New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('a'*40)
    $nonce='b'*32;$branch='ci-native/pr43/'+$candidate.identity+'/'+$nonce
    $blob=(Invoke-CiGit $f.root @('rev-parse',($f.base+':.github/workflows/integration-execution.yml'))).stdout.Trim()
    $run=@{id=777;run_attempt=2;status='completed';conclusion='success';event='workflow_dispatch';
        path='.github/workflows/integration-execution.yml';head_branch=$branch;head_sha=$f.base;workflow_id=123;
        repository=@{full_name=$candidate.repository;id=456};head_repository=@{full_name=$candidate.repository;id=456};
        referenced_workflows=@(@{sha=$candidate.controllerEngineRef;path=('RedSalamanders/.github/.github/workflows/integration-execution.yml@'+$candidate.controllerEngineRef)})}
    $jobs=@()
    foreach($p in @(@('freeze','ubuntu-latest'),@('x64','windows-2025-vs2026'),@('ARM64','windows-11-vs2026-arm'))){
        $name=if($p[0] -ceq 'freeze'){'shadow / freeze'}else{"shadow / regression ($($p[0]), $($p[1]))"}
        $jobs+=@{id=(100+$jobs.Count);run_id=777;run_attempt=2;head_sha=$f.base;name=$name;
            status='completed';conclusion='success';runner_group_name='GitHub Actions';labels=@($p[1]);
            steps=@(@{name='Build the frozen test-enabled Release profile';status='completed';conclusion='success'},
                @{name='Run actual regression tests and the Release assertion probe';status='completed';conclusion='success'},
                @{name='Retain original tested profile bytes for independent verification';status='completed';conclusion='success'})}
    }
    $artifacts=@()
    foreach($name in @('candidate-inputs-2','candidate-regression-x64-2','candidate-profile-x64-2','candidate-workspace-evidence-x64-2',
        'candidate-regression-ARM64-2','candidate-profile-ARM64-2','candidate-workspace-evidence-ARM64-2','candidate-evidence-x64-2')){
        $artifacts+=@{id=(200+$artifacts.Count);name=$name;expired=$false;digest=('sha256:'+('c'*64));size_in_bytes=100;
            workflow_run=@{id=777;head_sha=$f.base;head_branch=$branch;repository_id=456;head_repository_id=456}}
    }
    return @{root=$f.root;candidate=$candidate;run=$run;currentRun=($run|ConvertTo-Json -Depth 10|ConvertFrom-Json -AsHashtable);
        jobs=@{total_count=3;jobs=$jobs};artifacts=@{total_count=$artifacts.Count;artifacts=$artifacts};
        workflow=@{path=$run.path;sha=$blob};workflowBlob=$blob;runId='777';attempt=2;isolationNonce=$nonce}
}
function Invoke-CandidateResultEnvelope($Fixture){
    & $candidateResults {param($f) New-CiCandidateRunEnvelope -Candidate $f.candidate -Run $f.run -CurrentRun $f.currentRun `
        -Jobs $f.jobs -Artifacts $f.artifacts -Workflow $f.workflow -WorkflowBlob $f.workflowBlob -RunId $f.runId -Attempt $f.attempt -IsolationNonce $f.isolationNonce} $Fixture
}

Invoke-Case 'Candidate producer envelope binds both hosted architectures and server digests without a native verdict' {
    $f=New-CandidateResultFixture 'candidate-result-envelope'
    $r=Invoke-CandidateResultEnvelope $f
    Assert-Equal 'CandidateRunArtifactEnvelope' $r.role
    Assert-Equal 3 $r.jobs.Count
    Assert-Equal 8 $r.artifacts.Count
    Assert-Equal $f.candidate.identity $r.expectedInputs.candidate.identity
    Assert-Equal $f.candidate.mergeCommit $r.expectedInputs.batch.commit
    Assert-Equal 2 $r.expectedInputs.batch.candidateExecution.context.runAttempt
    Assert-True (-not $r.artifactBytesVerified -and -not $r.nativeResultVerified -and -not $r.suppliesNativeVerdict)
    $roundtrip=$f|ConvertTo-Json -Depth 25|ConvertFrom-Json -AsHashtable
    Assert-Equal ($r|ConvertTo-Json -Depth 25 -Compress) ((Invoke-CandidateResultEnvelope $roundtrip)|ConvertTo-Json -Depth 25 -Compress)
}

Invoke-Case 'Candidate producer envelope refuses stale attempts, identities, jobs, detectors and artifact substitution' {
    $original=(New-CandidateResultFixture 'candidate-result-refusals')|ConvertTo-Json -Depth 25
    $mutations=@(
        {param($f)$f.run.event='push'}, {param($f)$f.run.path='.github/workflows/qualify.yml'},
        {param($f)$f.run.head_branch='main'}, {param($f)$f.run.head_sha=$f.candidate.mergeCommit},
        {param($f)$f.run.repository.full_name='RedSalamanders/RedXe'},
        {param($f)$f.run.head_repository.id=123}, {param($f)$f.run.head_repository.full_name='foreign/project'},
        {param($f)$f.run.conclusion='failure'}, {param($f)$f.run.conclusion='cancelled'},
        {param($f)$f.run.status='in_progress'}, {param($f)$f.run.run_attempt=1},
        {param($f)$f.currentRun.run_attempt=3}, {param($f)$f.currentRun.conclusion='failure'},
        {param($f)$f.currentRun.workflow_id=999}, {param($f)$f.currentRun.head_sha='d'*40},
        {param($f)$f.run.referenced_workflows[0].sha='d'*40},
        {param($f)$f.run.referenced_workflows[0].path='RedSalamanders/.github/.github/workflows/qualify.yml@'+('d'*40)},
        {param($f)$f.run.referenced_workflows=@()}, {param($f)$f.workflow.sha='d'*40},
        {param($f)$f.workflow.path='other.yml'}, {param($f)$f.jobs.total_count=4},
        {param($f)$f.jobs.jobs=@($f.jobs.jobs[0],$f.jobs.jobs[1],$f.jobs.jobs[1])},
        {param($f)$f.jobs.jobs[2].conclusion='skipped'}, {param($f)$f.jobs.jobs[2].labels=@('self-hosted')},
        {param($f)$f.jobs.jobs[2].runner_group_name='Other'}, {param($f)$f.jobs.jobs[2].run_attempt=1},
        {param($f)$f.jobs.jobs[2].head_sha=$f.candidate.mergeCommit},
        {param($f)$f.jobs.jobs[1].steps[1].conclusion='skipped'}, {param($f)$f.jobs.jobs[1].steps=@()},
        {param($f)$f.artifacts.total_count=100}, {param($f)$f.artifacts.artifacts[0].expired=$true},
        {param($f)$f.artifacts.artifacts[0].digest='sha256:bad'}, {param($f)$f.artifacts.artifacts[0].size_in_bytes=0},
        {param($f)$f.artifacts.artifacts[0].workflow_run.head_sha=$f.candidate.mergeCommit},
        {param($f)$f.artifacts.artifacts[0].workflow_run.head_branch='main'},
        {param($f)$f.artifacts.artifacts[0].workflow_run.head_repository_id=123},
        {param($f)$f.artifacts.artifacts[0].workflow_run.id=123},
        {param($f)$f.artifacts.artifacts[1].name='candidate-regression-x64-1'},
        {param($f)$f.artifacts.artifacts[1].name=$f.artifacts.artifacts[0].name},
        {param($f)$f.artifacts.artifacts[1].id=$f.artifacts.artifacts[0].id},
        {param($f)$f.artifacts.artifacts[1].name='unrelated-output'},
        {param($f)$f.artifacts.artifacts=@($f.artifacts.artifacts|Where-Object name -CNE 'candidate-profile-ARM64-2');$f.artifacts.total_count--}
    )
    foreach($change in $mutations){$f=$original|ConvertFrom-Json -AsHashtable;$null=& $change $f;Assert-Refused {Invoke-CandidateResultEnvelope $f}}
}

Invoke-Case 'Public candidate result acquisition is read-only and refuses final candidate or producer races' {
    $f=New-CandidateResultFixture 'candidate-result-public'
    $original=& $candidateResults {@{Candidate=(Get-Command Get-CiIntegrationCandidate).ScriptBlock;Api=(Get-Command Invoke-CiApi).ScriptBlock}}
    try{
        foreach($scenario in @('success','wrong-identity','candidate-race','producer-race')){
            & $candidateResults {
                param($f,$scenario)
                $script:resultFixture=$f;$script:resultScenario=$scenario;$script:candidateReads=0;$script:currentReads=0;$script:resultRoutes=@()
                function script:Get-CiIntegrationCandidate {
                    param($Root,$PullRequest)
                    $script:candidateReads++
                    if($script:resultScenario -ceq 'candidate-race' -and $script:candidateReads -gt 1){
                        $r=$script:resultFixture.candidate|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable;$r.identity='d'*64;return $r
                    }
                    return $script:resultFixture.candidate
                }
                function script:Invoke-CiApi {
                    param($Route,$Method='GET')
                    if($Method -cne 'GET'){throw 'Result authentication attempted a remote write.'}
                    $script:resultRoutes+=,$Route
                    $f=$script:resultFixture
                    switch -Regex ($Route){
                        '/attempts/2$' {return $f.run}
                        '/runs/777$' {
                            $script:currentReads++
                            if($script:resultScenario -ceq 'producer-race' -and $script:currentReads -gt 1){
                                $r=$f.currentRun|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable;$r.run_attempt=3;return $r
                            }
                            return $f.currentRun
                        }
                        '/attempts/2/jobs\?per_page=100$' {return $f.jobs}
                        '/runs/777/artifacts\?per_page=100$' {return $f.artifacts}
                        '/contents/.github/workflows/integration-execution.yml\?ref=' {return $f.workflow}
                        default {throw 'Unexpected recording API route.'}
                    }
                }
            } $f $scenario
            $request=@{Root=$f.root;PullRequest=43;ExpectedIdentity=$(if($scenario -ceq 'wrong-identity'){'d'*64}else{$f.candidate.identity});RunId='777';Attempt=2;IsolationNonce=$f.isolationNonce}
            if($scenario -ceq 'success'){
                $result=Get-CiCandidateRunEnvelope @request
                Assert-Equal 'CandidateRunArtifactEnvelope' $result.role
                Assert-True (-not $result.suppliesNativeVerdict)
                Assert-Equal 6 (& $candidateResults {$script:resultRoutes.Count})
            }else{Assert-Refused {Get-CiCandidateRunEnvelope @request}}
            $expectedCalls=switch($scenario){'wrong-identity'{0};'candidate-race'{5};default{6}}
            Assert-Equal $expectedCalls (& $candidateResults {$script:resultRoutes.Count})
        }
    }finally{
        & $candidateResults {param($saved) Set-Item Function:script:Get-CiIntegrationCandidate $saved.Candidate;Set-Item Function:script:Invoke-CiApi $saved.Api} $original
    }
}
