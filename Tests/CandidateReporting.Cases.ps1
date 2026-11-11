# Recording API/verifier boundaries; these tests never publish a real check or native verdict.
Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.CandidateReporting.psm1')

Invoke-Case 'Trusted reporter invokes original byte verification and fails closed on context, source, prerequisite, producer and check ownership changes' {
    $module=Get-Module Ci.CandidateReporting
    $commands=@('Get-CiMainHead','Get-CiIntegrationCandidate','Invoke-CiApi','Get-CiCandidateNativeResult','Get-CiCandidateRunEnvelope')
    $original=& $module {param($names)$saved=@{};foreach($name in $names){$saved[$name]=(Get-Command $name).ScriptBlock};$saved} $commands
    & $module {
        function script:Get-CiMainHead {param($Repository) if($Repository -cne $script:reportControl.candidate.repository){throw 'Changed reporter repository.'};return $script:reportControl.candidate.baseCommit}
        function script:Get-CiIntegrationCandidate {
            param($Root,$PullRequest)
            $c=$script:reportControl
            if($Root -cne $c.root -or $PullRequest -ne 43){throw 'Changed reporter acquisition.'}
            $c.candidateReads++
            $copy=$c.candidate|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
            if($c.scenario -ceq 'stale-final' -and $c.candidateReads -gt 1){$copy.headCommit='e'*40}
            return $copy
        }
        function script:Get-CiCandidateNativeResult {
            param($Root,$PullRequest,$ExpectedIdentity,$RunId,$Attempt,$IsolationNonce,$OutputRoot)
            $c=$script:reportControl;$c.verifierCalls++
            if($Root -cne $c.root -or $PullRequest -ne 43 -or $ExpectedIdentity -cne $c.candidate.identity -or
                $RunId -cne '777' -or $Attempt -ne 2 -or $IsolationNonce -cne ('b'*32) -or $OutputRoot -cne $c.output){throw 'Changed original verifier request.'}
            if($c.check.status -cne 'in_progress' -or $null -ne $c.check.conclusion){throw 'Earlier green check was not invalidated before verification.'}
            if($c.scenario -in @('missing-evidence','native-failed','cancelled-run','changed-attempt')){throw ('Recording original verifier refusal: '+$c.scenario)}
            return @{role='AuthenticatedCandidateNativeResult';nativeResultVerified=$(if($c.scenario -ceq 'fake-verifier-type'){'true'}else{$true});
                runId=$RunId;runAttempt=$Attempt;candidate=$c.candidate;originalArchives=$c.archives}
        }
        function script:Get-CiCandidateRunEnvelope {
            param($Root,$PullRequest,$ExpectedIdentity,$RunId,$Attempt,$IsolationNonce)
            $c=$script:reportControl;$c.envelopeCalls++
            if($Root -cne $c.root -or $RunId -cne '777' -or $Attempt -ne 2 -or $IsolationNonce -cne ('b'*32) -or $ExpectedIdentity -cne $c.candidate.identity -or $PullRequest -ne 43){throw 'Changed final producer reacquisition.'}
            return @{artifacts=$(if($c.scenario -ceq 'changed-catalog'){@(@{digest='changed'})}else{$c.archives})}
        }
        function script:Invoke-CiApi {
            param($Route,$Method='GET',$Body)
            $c=$script:reportControl;$repo=$c.candidate.repository
            if($Method -ceq 'GET'){
                if($Route -ceq ('repos/'+$repo+'/actions/runs/999')){
                    return @{id=999;run_attempt=1;repository=@{full_name=$repo};head_repository=@{full_name=$repo};event='workflow_dispatch';head_branch='main';
                        referenced_workflows=@(@{sha=$c.candidate.controllerEngineRef;path=('RedSalamanders/.github/.github/workflows/integration-report.yml@'+$c.candidate.controllerEngineRef)});
                        head_sha=$(if($c.scenario -ceq 'wrong-controller-run'){'e'*40}else{$c.candidate.baseCommit});path='.github/workflows/integration-report.yml';status='in_progress'}
                }
                if($Route -ceq ('repos/'+$repo+'/contents/.github/workflows/integration-report.yml?ref='+$c.candidate.baseCommit)){
                    return @{path='.github/workflows/integration-report.yml';sha=$c.blob}
                }
                if($Route -ceq ('repos/'+$repo+'/commits/'+$c.candidate.headCommit+'/check-runs?filter=latest&per_page=100')){
                    $c.catalogReads++;$rows=@();$id=1
                    foreach($name in @('checks / ci-gate','security / codeql','security / dependency-review')){
                        $rows+=@{name=$name;id=$id++;app=@{id=15368};head_sha=$c.candidate.headCommit;status='completed';
                            conclusion=$(if($c.scenario -ceq 'checks-failed' -or ($c.scenario -ceq 'final-checks-failed' -and $c.catalogReads -gt 1)){'failure'}else{'success'})}
                    }
                    if($c.check){$rows+=$c.check}
                    if($c.scenario -ceq 'duplicate-check'){$rows+=$c.check}
                    return @{total_count=$rows.Count;check_runs=$rows}
                }
                if($Route -ceq ('repos/'+$repo+'/check-runs/321')){
                    $copy=$c.check|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
                    if($c.scenario -ceq 'stolen-check'){$copy.external_id='newer owner'}
                    return $copy
                }
                throw ('Unexpected recording reporter GET: '+$Route)
            }
            if($Method -ceq 'POST' -and $Route -ceq ('repos/'+$repo+'/check-runs')){
                $c.writes.Add(@{method=$Method;body=$Body.Clone()})
                $c.check=@{id=321;app=@{id=15368};name=$Body.name;head_sha=$Body.head_sha;status=$Body.status;external_id=$Body.external_id;conclusion=$null}
                return $c.check
            }
            if($Method -ceq 'PATCH' -and $Route -ceq ('repos/'+$repo+'/check-runs/321')){
                $c.writes.Add(@{method=$Method;body=$Body.Clone()})
                foreach($key in $Body.Keys){$c.check[$key]=$Body[$key]}
                if($Body.status -ceq 'in_progress'){$c.check.conclusion=if($c.scenario -ceq 'uncleared-conclusion'){'success'}else{$null}}
                return $c.check
            }
            throw ('Unexpected recording reporter mutation: '+$Route)
        }
    }
    $saved=@{}
    try{
        foreach($scenario in @('valid','existing-owned','wrong-context','wrong-controller-run','dirty-root','wrong-identity','prose','foreign-check','duplicate-check',
            'checks-failed','final-checks-failed','missing-evidence','native-failed','cancelled-run','changed-attempt','fake-verifier-type','stale-final','changed-catalog','stolen-check','uncleared-conclusion')){
            $controller=Resolve-CiCommit $engineRoot HEAD
            $f=New-CandidateFixture ('native-report-'+$scenario) -ReporterCaller -EngineRef $controller -Prose:($scenario -ceq 'prose')
            $candidate=New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef $controller
            $blob=(Invoke-CiGit $f.root @('rev-parse',($f.base+':.github/workflows/integration-report.yml'))).stdout.Trim()
            $null=Invoke-CiGit $f.root @('checkout','--detach',$f.base)
            if($scenario -ceq 'dirty-root'){Write-FixtureFile $f.root 'src/dirty.cpp' 'never execute'}
            $environment=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';GITHUB_EVENT_NAME='workflow_dispatch';GITHUB_REF='refs/heads/main';
                GITHUB_REPOSITORY=$candidate.repository;GITHUB_SHA=$f.base;GITHUB_WORKFLOW_REF=($candidate.repository+'/.github/workflows/integration-report.yml@refs/heads/main');GITHUB_RUN_ID='999';GITHUB_RUN_ATTEMPT='1'}
            foreach($name in $environment.Keys){if(-not $saved.ContainsKey($name)){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')};[Environment]::SetEnvironmentVariable($name,$environment[$name],'Process')}
            if($scenario -ceq 'wrong-context'){$env:GITHUB_REF='refs/pull/43/merge'}
            $output=Join-Path $runRoot ('native-report-output-'+$scenario)
            $control=@{root=$f.root;output=$output;candidate=$candidate;blob=$blob;scenario=$scenario;candidateReads=0;catalogReads=0;verifierCalls=0;envelopeCalls=0;
                archives=@(@{artifactId='123';digest=('f'*64)});check=$null;writes=[Collections.Generic.List[object]]::new()}
            if($scenario -in @('existing-owned','foreign-check','duplicate-check','uncleared-conclusion')){
                $control.check=@{id=321;app=@{id=15368};name='native / candidate-integration';head_sha=$candidate.headCommit;status='completed';conclusion='success';
                    external_id=$(if($scenario -ceq 'foreign-check'){'not-owned'}else{'i61-native-'+('e'*64)+'-776-1-report-998-1'})}
            }
            & $module {param($c)$script:reportControl=$c} $control
            $request=@{Root=$f.root;PullRequest=43;ExpectedIdentity=$(if($scenario -ceq 'wrong-identity'){'f'*64}else{$candidate.identity});RunId='777';Attempt=2;IsolationNonce=('b'*32);OutputRoot=$output}
            if($scenario -in @('valid','existing-owned')){
                $result=Publish-CiCandidateCheck @request
                Assert-Equal 'CandidateNativeCheckReport' $result.role
                Assert-Equal 'success' $result.conclusion
                Assert-True (-not $result.localDelegationEnabled -and -not $result.adoptionAuthorized -and -not $result.productionAuthorized)
                Assert-Equal 1 $control.verifierCalls;Assert-Equal 1 $control.envelopeCalls
                Assert-Equal 'success' $control.check.conclusion
            }else{Assert-Refused {Publish-CiCandidateCheck @request}}
            if($scenario -in @('wrong-context','wrong-controller-run','dirty-root','wrong-identity','prose','foreign-check','duplicate-check','checks-failed')){
                Assert-Equal 0 $control.writes.Count;Assert-Equal 0 $control.verifierCalls
            }elseif($scenario -ceq 'stolen-check'){
                Assert-Equal 1 $control.writes.Count
                Assert-Equal 'in_progress' $control.check.status
            }else{
                Assert-Equal 2 $control.writes.Count
                Assert-Equal 'in_progress' $control.writes[0].body.status
                Assert-Equal $(if($scenario -in @('valid','existing-owned')){'success'}else{'failure'}) $control.writes[1].body.conclusion
            }
            Assert-True (-not(Test-Path -LiteralPath $output))
        }
    }finally{
        foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
        & $module {param($s)foreach($name in $s.Keys){Set-Item ('function:script:'+$name) $s[$name]};Remove-Variable reportControl -Scope Script -ErrorAction SilentlyContinue} $original
    }
}

Invoke-Case 'Native reporter workflow confines check writes to trusted-main metadata and invokes no candidate code or native build' {
    $caller=[IO.File]::ReadAllText((Join-Path $engineRoot 'Templates/integration-report.yml'))
    $workflow=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/integration-report.yml'))
    Assert-True ($caller -match '(?m)^  workflow_dispatch:')
    Assert-True ($caller -notmatch '(?m)^  (pull_request|pull_request_target|push|workflow_run|schedule):')
    Assert-True ($caller.Contains('group: candidate-report-${{ inputs.pull_request }}'))
    Assert-True ($workflow.Contains("if: github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'"))
    Assert-True ($workflow.Contains('ref: ${{ github.sha }}'))
    Assert-True ($workflow.Contains('Publish-CandidateCheck.ps1'))
    Assert-True ($workflow -notmatch 'setup-msvc|actions/cache|setup-vcpkg|Invoke-ProjectCi|build\.ps1|secrets:|contents: write|actions: write')
}
