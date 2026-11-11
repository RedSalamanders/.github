# Trusted manual reporter. Original artifact verification runs here; saved JSON is not authority.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Candidate.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.CandidateVerification.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.CandidateResults.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.CandidateReadiness.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1')

function Assert-CiCandidateReportCheck {
    param([object]$Check,[string]$Head,[string]$ExternalId,[string]$CheckId)
    if([string]$Check.id -cne $CheckId -or $Check.name -cne 'native / candidate-integration' -or
        $Check.head_sha -cne $Head -or $Check.app.id -ne 15368 -or $Check.external_id -cne $ExternalId){
        throw 'Native report check ownership changed; never overwrite another report.'
    }
}

function Publish-CiCandidateCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedIdentity,
        [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
        [Parameter(Mandatory)][ValidateRange(1,100000)][int]$Attempt,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$IsolationNonce,
        [Parameter(Mandatory)][string]$OutputRoot)
    $project=Read-CiProject $Root
    $engine=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $workflow='.github/workflows/integration-report.yml'
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
        $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/main' -or
        $env:GITHUB_REPOSITORY -cne $project.repository -or
        $env:GITHUB_WORKFLOW_REF -cne ($project.repository+'/'+$workflow+'@refs/heads/main') -or
        $env:GITHUB_RUN_ID -cnotmatch '^[1-9][0-9]{0,19}$' -or $env:GITHUB_RUN_ATTEMPT -cnotmatch '^[1-9][0-9]{0,5}$'){
        throw 'Native reporting requires the actual hosted trusted-main manual reporter.'
    }
    $main=Get-CiMainHead $project.repository
    if([int]$env:GITHUB_RUN_ATTEMPT -gt 100000){throw 'Reporter attempt exceeds the supported original-attempt bound.'}
    if($env:GITHUB_SHA -cne $main -or (Resolve-CiCommit $Root HEAD) -cne $main -or
        (Resolve-CiCommit $engine HEAD) -cne $project.engine.ref -or
        (Invoke-CiGit $Root @('status','--porcelain','--untracked-files=all')).stdout.Trim() -or
        (Invoke-CiGit $engine @('status','--porcelain','--untracked-files=all')).stdout.Trim()){
        throw 'Reporter requires the exact clean current main and reviewed engine.'
    }
    $producer=Invoke-CiApi ('repos/'+$project.repository+'/actions/runs/'+$env:GITHUB_RUN_ID) -Method GET
    if([string]$producer.id -cne $env:GITHUB_RUN_ID -or $producer.run_attempt -ne [int]$env:GITHUB_RUN_ATTEMPT -or
        $producer.repository.full_name -cne $project.repository -or $producer.head_repository.full_name -cne $project.repository -or $producer.event -cne 'workflow_dispatch' -or
        $producer.head_branch -cne 'main' -or $producer.head_sha -cne $main -or $producer.path -cne $workflow -or
        $producer.status -cne 'in_progress'){throw 'Independent original reporter run differs from the live controller.'}
    $references=@($producer.referenced_workflows|Where-Object path -CEQ ('RedSalamanders/.github/.github/workflows/integration-report.yml@'+$project.engine.ref))
    if($references.Count -ne 1 -or $references[0].sha -cne $project.engine.ref){throw 'Original reporter reusable-engine reference differs.'}
    $caller=Invoke-CiApi ('repos/'+$project.repository+'/contents/'+$workflow+'?ref='+$main) -Method GET
    $blob=(Invoke-CiGit $Root @('rev-parse',($main+':'+$workflow))).stdout.Trim()
    if($caller.path -cne $workflow -or $caller.sha -cne $blob){throw 'Reporter caller Git/API bytes differ.'}
    $candidate=Get-CiIntegrationCandidate -Root $Root -PullRequest $PullRequest
    if($candidate.identity -cne $ExpectedIdentity -or $candidate.baseCommit -cne $main -or
        $candidate.controllerEngineRef -cne $project.engine.ref -or -not $candidate.nativeRequired){
        throw 'Reporter requires the exact current native candidate; prose supplies no baseline success.'
    }
    $head=$candidate.headCommit
    $catalog=Invoke-CiApi ('repos/'+$project.repository+'/commits/'+$head+'/check-runs?filter=latest&per_page=100') -Method GET
    $null=Test-CiCandidateReadinessCatalog -Candidate $candidate -Catalog $catalog
    $existing=@($catalog.check_runs|Where-Object name -CEQ 'native / candidate-integration')
    if($existing.Count -gt 1){throw 'Ambiguous native check catalog; no report was written.'}
    $external='i61-native-'+$ExpectedIdentity+'-'+$RunId+'-'+$Attempt+'-report-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT
    $body=@{name='native / candidate-integration';head_sha=$head;status='in_progress';external_id=$external;
        details_url=('https://github.com/'+$project.repository+'/actions/runs/'+$env:GITHUB_RUN_ID);
        output=@{title='Verifying original candidate native evidence';summary=('Candidate '+$ExpectedIdentity+'; original run '+$RunId+', attempt '+$Attempt+'. No result has been accepted yet.')}}
    if($existing.Count){
        $prior=$existing[0]
        if($prior.app.id -ne 15368 -or $prior.head_sha -cne $head -or
            [string]$prior.id -cnotmatch '^[1-9][0-9]{0,19}$' -or
            $prior.external_id -cnotmatch '^i61-native-[a-f0-9]{64}-[1-9][0-9]{0,19}-[1-9][0-9]{0,5}-report-[1-9][0-9]{0,19}-[1-9][0-9]{0,5}$'){
            throw 'Existing same-name check is not an owned native report.'
        }
        $body.Remove('name');$body.Remove('head_sha')
        $pending=Invoke-CiApi ('repos/'+$project.repository+'/check-runs/'+$prior.id) -Method PATCH -Body $body
    }else{$pending=Invoke-CiApi ('repos/'+$project.repository+'/check-runs') -Method POST -Body $body}
    $checkId=[string]$pending.id
    if($checkId -cnotmatch '^[1-9][0-9]{0,19}$'){throw 'Provider did not return an original native check ID.'}
    Assert-CiCandidateReportCheck -Check $pending -Head $head -ExternalId $external -CheckId $checkId
    $request=@{Root=$Root;PullRequest=$PullRequest;ExpectedIdentity=$ExpectedIdentity;RunId=$RunId;Attempt=$Attempt;IsolationNonce=$IsolationNonce}
    try{
        if($pending.status -cne 'in_progress' -or $null -ne $pending.conclusion){throw 'Provider did not clear the earlier native conclusion before verification.'}
        # Invoke the verifier itself, never accept a caller-provided/saved result JSON.
        $result=Get-CiCandidateNativeResult @request -OutputRoot $OutputRoot
        if($result.role -cne 'AuthenticatedCandidateNativeResult' -or $result.nativeResultVerified -isnot [bool] -or -not $result.nativeResultVerified -or
            $result.runId -cne $RunId -or $result.runAttempt -ne $Attempt -or
            ($result.candidate|ConvertTo-Json -Depth 20 -Compress) -cne ($candidate|ConvertTo-Json -Depth 20 -Compress)){
            throw 'Independent verifier returned a different native producer binding.'
        }
        $current=Get-CiIntegrationCandidate -Root $Root -PullRequest $PullRequest
        if(($current|ConvertTo-Json -Depth 20 -Compress) -cne ($candidate|ConvertTo-Json -Depth 20 -Compress)){
            throw 'Candidate changed before native report publication.'
        }
        $catalog=Invoke-CiApi ('repos/'+$project.repository+'/commits/'+$head+'/check-runs?filter=latest&per_page=100') -Method GET
        $null=Test-CiCandidateReadinessCatalog -Candidate $candidate -Catalog $catalog
        $envelope=Get-CiCandidateRunEnvelope @request
        if(($envelope.artifacts|ConvertTo-Json -Depth 20 -Compress) -cne ($result.originalArchives|ConvertTo-Json -Depth 20 -Compress)){
            throw 'Original producer artifact catalog changed before native reporting.'
        }
        $owned=Invoke-CiApi ('repos/'+$project.repository+'/check-runs/'+$checkId) -Method GET
        Assert-CiCandidateReportCheck -Check $owned -Head $head -ExternalId $external -CheckId $checkId
        $complete=Invoke-CiApi ('repos/'+$project.repository+'/check-runs/'+$checkId) -Method PATCH -Body @{
            status='completed';conclusion='success';completed_at=[DateTimeOffset]::UtcNow.ToString('o');
            output=@{title='Original x64 and ARM64 candidate evidence verified';summary=('Candidate '+$ExpectedIdentity+'; head '+$head+'; base '+$candidate.baseCommit+'; original run '+$RunId+', attempt '+$Attempt+'. Both original native receipts, tested profile and canonical evidence bytes were independently verified. This report does not authorize local delegation, main adoption or production.')}}
        Assert-CiCandidateReportCheck -Check $complete -Head $head -ExternalId $external -CheckId $checkId
        if($complete.status -cne 'completed' -or $complete.conclusion -cne 'success'){throw 'Provider did not confirm native report completion.'}
    }catch{
        # Failure never preserves a successful report from an earlier request. If
        # another owner took the check, refuse rather than overwriting its state.
        $failure=$_
        $owned=Invoke-CiApi ('repos/'+$project.repository+'/check-runs/'+$checkId) -Method GET
        Assert-CiCandidateReportCheck -Check $owned -Head $head -ExternalId $external -CheckId $checkId
        $null=Invoke-CiApi ('repos/'+$project.repository+'/check-runs/'+$checkId) -Method PATCH -Body @{
            status='completed';conclusion='failure';completed_at=[DateTimeOffset]::UtcNow.ToString('o');
            output=@{title='Candidate native evidence was not accepted';summary='Original native evidence or current candidate prerequisites could not be independently verified. Retained diagnostics do not grant a native pass.'}}
        throw $failure
    }
    return [ordered]@{role='CandidateNativeCheckReport';repository=$project.repository;headCommit=$head;
        identity=$ExpectedIdentity;runId=$RunId;runAttempt=$Attempt;checkId=$checkId;conclusion='success';
        localDelegationEnabled=$false;adoptionAuthorized=$false;productionAuthorized=$false}
}

Export-ModuleMember -Function Publish-CiCandidateCheck
