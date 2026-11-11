# Trusted read-only producer metadata acquisition. Artifact bytes and native results
# require their separate verifier; an envelope never authorizes merge or adoption.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Candidate.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.CandidateExecution.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1')

function New-CiCandidateRunEnvelope {
    param([Collections.IDictionary]$Candidate,[object]$Run,[object]$CurrentRun,
        [object]$Jobs,[object]$Artifacts,[object]$Workflow,[string]$WorkflowBlob,
        [string]$RunId,[int]$Attempt,[string]$IsolationNonce)
    $branch='ci-native/pr'+$Candidate.pullRequest+'/'+$Candidate.identity+'/'+$IsolationNonce
    $path='.github/workflows/integration-execution.yml'
    foreach($producer in @($Run,$CurrentRun)){
        if([string]$producer.id -cne $RunId -or $producer.run_attempt -ne $Attempt -or
            $producer.status -cne 'completed' -or $producer.conclusion -cne 'success' -or
            $producer.event -cne 'workflow_dispatch' -or $producer.path -cne $path -or
            $producer.head_branch -cne $branch -or $producer.head_sha -cne $Candidate.baseCommit -or
            $producer.repository.full_name -cne $Candidate.repository -or
            $producer.head_repository.full_name -cne $Candidate.repository -or
            $producer.repository.id -ne $producer.head_repository.id -or $producer.repository.id -le 0){
            throw 'Candidate artifacts require the exact successful isolated producer and its current attempt.'
        }
        $refs=@($producer.referenced_workflows)
        if($refs.Count -ne 1 -or $refs[0].sha -cne $Candidate.controllerEngineRef -or
            $refs[0].path -cne ('RedSalamanders/.github/.github/workflows/integration-execution.yml@'+$Candidate.controllerEngineRef)){
            throw 'Candidate producer used another reusable workflow or engine.'
        }
    }
    if($Run.workflow_id -ne $CurrentRun.workflow_id -or $Workflow.path -cne $path -or
        $Workflow.sha -cne $WorkflowBlob -or $WorkflowBlob -cnotmatch '^[a-f0-9]{40}$'){
        throw 'Candidate caller differs from the independently fetched trusted Git object.'
    }
    $context=[ordered]@{repository=$Candidate.repository;event='workflow_dispatch';ref=('refs/heads/'+$branch);
        commit=$Candidate.baseCommit;workflowRef=($Candidate.repository+'/'+$path+'@refs/heads/'+$branch);
        runId=$RunId;runAttempt=$Attempt}
    $expected=New-CiCandidateExecutionInputs -Candidate $Candidate -Context $context -IsolationNonce $IsolationNonce -ControllerWorkflowBlob $WorkflowBlob
    if(-not $Candidate.nativeRequired){throw 'A prose-only candidate supplies no native producer acceptance.'}
    if($Jobs.total_count -ne @($Jobs.jobs).Count -or $Jobs.total_count -ne 3 -or
        $Artifacts.total_count -ne @($Artifacts.artifacts).Count){throw 'Incomplete or unexpected candidate producer metadata.'}
    $selectedJobs=[Collections.Generic.List[object]]::new()
    foreach($profile in @(@('freeze','ubuntu-latest'),@('x64','windows-2025-vs2026'),@('ARM64','windows-11-vs2026-arm'))){
        $platform=$profile[0];$runner=$profile[1]
        $name=if($platform -ceq 'freeze'){'shadow / freeze'}else{"shadow / regression ($platform, $runner)"}
        $selected=@($Jobs.jobs|Where-Object name -CEQ $name)
        if($selected.Count -ne 1){throw 'Missing or duplicated native candidate job.'}
        $job=$selected[0]
        if($job.status -cne 'completed' -or $job.conclusion -cne 'success' -or
            [string]$job.run_id -cne $RunId -or $job.run_attempt -ne $Attempt -or
            $job.head_sha -cne $Candidate.baseCommit -or $job.runner_group_name -cne 'GitHub Actions' -or
            $runner -cnotin @($job.labels)){throw 'Candidate job lacks successful matching hosted execution.'}
        if($platform -cne 'freeze'){
            foreach($stepName in @('Build the frozen test-enabled Release profile','Run actual regression tests and the Release assertion probe',
                'Retain original tested profile bytes for independent verification')){
                $steps=@($job.steps|Where-Object name -CEQ $stepName)
                if($steps.Count -ne 1 -or $steps[0].status -cne 'completed' -or $steps[0].conclusion -cne 'success'){
                    throw 'Candidate native build, execution or profile retention did not complete.'
                }
            }
        }
        $selectedJobs.Add([ordered]@{platform=$platform;id=[string]$job.id;runner=$runner})
    }
    $required=@("candidate-inputs-$Attempt")
    foreach($platform in @('x64','ARM64')){
        foreach($kind in @('regression','profile','workspace-evidence')){$required+="candidate-$kind-$platform-$Attempt"}
    }
    $allowed=@($required)+@("candidate-evidence-x64-$Attempt","candidate-evidence-ARM64-$Attempt")
    $records=[Collections.Generic.List[object]]::new()
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($artifact in @($Artifacts.artifacts)){
        if($artifact.name -cnotin $allowed -or -not $names.Add($artifact.name) -or -not $ids.Add([string]$artifact.id) -or
            [string]$artifact.id -cnotmatch '^[1-9][0-9]{0,19}$' -or $artifact.expired -isnot [bool] -or $artifact.expired -or
            $artifact.digest -cnotmatch '^sha256:[a-f0-9]{64}$' -or
            ($artifact.size_in_bytes -isnot [int] -and $artifact.size_in_bytes -isnot [long]) -or
            $artifact.size_in_bytes -lt 1 -or $artifact.size_in_bytes -gt 4GB -or
            [string]$artifact.workflow_run.id -cne $RunId -or $artifact.workflow_run.head_sha -cne $Candidate.baseCommit -or
            $artifact.workflow_run.head_branch -cne $branch -or $artifact.workflow_run.repository_id -ne $Run.repository.id -or
            $artifact.workflow_run.head_repository_id -ne $Run.repository.id){throw 'Candidate artifact server identity, digest, size or attempt differs.'}
        $records.Add([ordered]@{artifactId=[string]$artifact.id;artifactName=$artifact.name;
            archiveSha256=$artifact.digest.Substring(7);archiveBytes=[long]$artifact.size_in_bytes})
    }
    foreach($name in $required){if(-not $names.Contains($name)){throw 'Required original candidate artifact is missing.'}}
    return [ordered]@{schemaVersion=1;role='CandidateRunArtifactEnvelope';repository=$Candidate.repository;
        runId=$RunId;runAttempt=$Attempt;controllerCommit=$Candidate.baseCommit;controllerWorkflowBlob=$WorkflowBlob;
        expectedInputs=$expected;jobs=@($selectedJobs.ToArray());artifacts=@($records.ToArray());
        artifactBytesVerified=$false;nativeResultVerified=$false;suppliesNativeVerdict=$false}
}

function Get-CiCandidateRunEnvelope {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedIdentity,
        [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
        [Parameter(Mandatory)][ValidateRange(1,100000)][int]$Attempt,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$IsolationNonce)
    $candidate=Get-CiIntegrationCandidate -Root $Root -PullRequest $PullRequest
    if($candidate.identity -cne $ExpectedIdentity){throw 'Candidate changed before producer authentication.'}
    $repo=$candidate.repository
    $run=Invoke-CiApi "repos/$repo/actions/runs/$RunId/attempts/$Attempt" -Method GET
    $current=Invoke-CiApi "repos/$repo/actions/runs/$RunId" -Method GET
    $jobs=Invoke-CiApi "repos/$repo/actions/runs/$RunId/attempts/$Attempt/jobs?per_page=100" -Method GET
    $artifacts=Invoke-CiApi "repos/$repo/actions/runs/$RunId/artifacts?per_page=100" -Method GET
    $path='.github/workflows/integration-execution.yml'
    $workflow=Invoke-CiApi "repos/$repo/contents/${path}?ref=$($candidate.baseCommit)" -Method GET
    $blob=(Invoke-CiGit $Root @('rev-parse',($candidate.baseCommit+':'+$path))).stdout.Trim()
    $envelope=New-CiCandidateRunEnvelope -Candidate $candidate -Run $run -CurrentRun $current -Jobs $jobs -Artifacts $artifacts `
        -Workflow $workflow -WorkflowBlob $blob -RunId $RunId -Attempt $Attempt -IsolationNonce $IsolationNonce
    $after=Get-CiIntegrationCandidate -Root $Root -PullRequest $PullRequest
    if(($after|ConvertTo-Json -Depth 20 -Compress) -cne ($candidate|ConvertTo-Json -Depth 20 -Compress)){
        throw 'Candidate/main moved during producer authentication.'
    }
    $latest=Invoke-CiApi "repos/$repo/actions/runs/$RunId" -Method GET
    $null=New-CiCandidateRunEnvelope -Candidate $after -Run $run -CurrentRun $latest -Jobs $jobs -Artifacts $artifacts `
        -Workflow $workflow -WorkflowBlob $blob -RunId $RunId -Attempt $Attempt -IsolationNonce $IsolationNonce
    return $envelope
}

Export-ModuleMember -Function Get-CiCandidateRunEnvelope
