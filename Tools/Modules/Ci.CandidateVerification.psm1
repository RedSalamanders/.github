Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.CandidateResults.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.CandidateArchives.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.ArtifactTransport.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.Execution.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')

function Test-CiCandidateArtifactBytes {
    param([Collections.IDictionary]$Envelope,[Collections.IDictionary]$Archives)
    $opened=@{}
    try{
        if($Archives.Count -ne @($Envelope.artifacts).Count){throw 'Candidate archive set is incomplete or contains extra inputs.'}
        foreach($artifact in $Envelope.artifacts){
            if(-not $Archives.Contains($artifact.artifactName)){throw 'Original candidate archive is missing.'}
            $opened[$artifact.artifactName]=Open-CiCandidateArchive -Path $Archives[$artifact.artifactName] -Artifact $artifact
        }
        $attempt=$Envelope.runAttempt
        $inputs=$opened["candidate-inputs-$attempt"]
        if($inputs.Entries.Count -ne 2){throw 'Candidate input archive must contain exactly its two original JSON files.'}
        foreach($pair in @(@('candidate-inputs.json',$Envelope.expectedInputs),@('batch.json',$Envelope.expectedInputs.batch))){
            $actual=Read-CiCandidateArchiveJson -Archive $inputs -Path $pair[0]
            if(($actual|ConvertTo-Json -Depth 30 -Compress) -cne ($pair[1]|ConvertTo-Json -Depth 30 -Compress)){
                throw 'Downloaded candidate or batch differs from independently reconstructed producer inputs.'
            }
        }
        $project=($Envelope.repository -split '/')[1];$escaped=[regex]::Escape($project)
        $profiles=[Collections.Generic.List[object]]::new()
        foreach($platform in @('x64','ARM64')){
            $receiptArchive=$opened["candidate-regression-$platform-$attempt"]
            if($receiptArchive.Entries.Count -ne 1){throw 'Regression archive must retain exactly one original receipt.'}
            $receipt=Read-CiCandidateArchiveJson -Archive $receiptArchive -Path "regression-$platform.json"
            $null=Test-CiRegressionExecutionBinding -Receipt $receipt -Descriptor $Envelope.expectedInputs.batch `
                -Platform $platform -RunId $Envelope.runId -RunAttempt $attempt
            $profile=$opened["candidate-profile-$platform-$attempt"]
            if($profile.Entries.Count -ne @($receipt.artifacts).Count){throw 'Tested profile contains missing or unbound extra files.'}
            foreach($file in $receipt.artifacts){
                $path=$file.path.Substring((".build/$platform/Release/").Length)
                $null=Test-CiCandidateArchiveFile -Archive $profile -Path $path -Sha256 $file.sha256
            }
            foreach($file in $receipt.canonicalEvidence){
                $path=$file.path.Replace('\','/')
                if($path -cmatch ("^[CD]:/a/$escaped/$escaped/\.build/(?<relative>.+)$")){
                    $archive=$opened["candidate-workspace-evidence-$platform-$attempt"];$relative=$Matches.relative
                }elseif($Envelope.repository -ceq 'RedSalamanders/RedSalamander' -and
                    $path -cmatch '^[CD]:/RedSalamander\.Perf/evidence/(?<relative>.+)$'){
                    $archive=$opened["candidate-evidence-$platform-$attempt"];$relative=$Matches.relative
                    if($null -eq $archive){throw 'Original canonical sandbox evidence archive is missing.'}
                }else{throw 'Canonical evidence is outside the reviewed hosted workspace or sandbox evidence root.'}
                $null=Test-CiCandidateArchiveFile -Archive $archive -Path $relative -Sha256 $file.sha256
            }
            $profiles.Add([ordered]@{platform=$platform;role=$receipt.role;version=$receipt.version;buildNumber=$receipt.buildNumber;
                countUnit=$receipt.countUnit;registered=$receipt.registered;expectedSkipped=$receipt.expectedSkipped;
                discovered=$receipt.discovered;executed=$receipt.executed;failed=$receipt.failed;
                artifacts=$receipt.artifacts;canonicalEvidence=$receipt.canonicalEvidence})
        }
        return [ordered]@{schemaVersion=1;role='CandidateNativeArtifactBytes';repository=$Envelope.repository;
            candidate=$Envelope.expectedInputs.candidate;runId=$Envelope.runId;runAttempt=$attempt;
            controllerCommit=$Envelope.controllerCommit;controllerWorkflowBlob=$Envelope.controllerWorkflowBlob;
            originalArchives=$Envelope.artifacts;profiles=@($profiles.ToArray());artifactBytesVerified=$true;
            mergeAuthorized=$false;localDelegationEnabled=$false;adoptionAuthorized=$false}
    }finally{foreach($archive in $opened.Values){Close-CiCandidateArchive $archive}}
}

function Get-CiCandidateNativeResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedIdentity,
        [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
        [Parameter(Mandatory)][ValidateRange(1,100000)][int]$Attempt,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$IsolationNonce,
        [Parameter(Mandatory)][string]$OutputRoot)
    $request=@{Root=$Root;PullRequest=$PullRequest;ExpectedIdentity=$ExpectedIdentity;RunId=$RunId;Attempt=$Attempt;IsolationNonce=$IsolationNonce}
    $envelope=Get-CiCandidateRunEnvelope @request
    $output=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $OutputRoot).Path)
    if(-not(Test-Path -LiteralPath $output -PathType Container)){throw 'Use an existing owned evidence output directory.'}
    if($env:GITHUB_ACTIONS -ceq 'true' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted'){
        if(-not $env:RUNNER_TEMP){throw 'Hosted evidence output needs its real runner temporary root.'}
        $null=Assert-CiContainedPath $env:RUNNER_TEMP $output
    }else{
        $sandbox=Join-Path ([IO.Path]::GetPathRoot($output)) 'RedSalamander.Perf'
        $sandboxPrefix=$sandbox.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
        if($output -ieq $sandbox -or $output.StartsWith($sandboxPrefix,[StringComparison]::OrdinalIgnoreCase)){
            $marker=Join-Path $sandbox '.red-salamander-test-root'
            if(-not(Test-Path -LiteralPath $marker -PathType Leaf) -or
                [IO.File]::ReadAllText($marker).Trim() -cne 'red-salamander.test-sandbox-root.v1'){throw 'Existing sandbox ownership marker is required.'}
            $null=Assert-CiContainedPath $sandbox $output
        }elseif($envelope.repository -cne 'RedSalamanders/RedSalamander'){
            $null=Assert-CiContainedPath (Join-Path ([IO.Path]::GetFullPath($Root)) '.build') $output
        }else{throw 'Local RedSalamander evidence must stay inside the existing marked sandbox.'}
    }
    $directory=Assert-CiContainedPath $output (Join-Path $output ('candidate-'+$RunId+'-'+$Attempt+'-'+[guid]::NewGuid().ToString('N')))
    if(Test-Path -LiteralPath $directory){throw 'Never replace original candidate evidence.'}
    [void][IO.Directory]::CreateDirectory($directory)
    [IO.File]::WriteAllText((Join-Path $directory 'original-envelope.json'),($envelope|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
    $archives=@{}
    foreach($artifact in $envelope.artifacts){
        $destination=Assert-CiContainedPath $directory (Join-Path $directory ($artifact.artifactName+'.zip'))
        Receive-CiHostedArtifactArchive -Repository $envelope.repository -Artifact $artifact -Destination $destination
        $archives[$artifact.artifactName]=$destination
    }
    $result=Test-CiCandidateArtifactBytes -Envelope $envelope -Archives $archives
    # Candidate/main, current attempt and original server catalog must still agree
    # after downloads. An original successful attempt cannot mask a later rerun.
    $after=Get-CiCandidateRunEnvelope @request
    if(($after|ConvertTo-Json -Depth 30 -Compress) -cne ($envelope|ConvertTo-Json -Depth 30 -Compress)){
        throw 'Candidate producer or original artifact catalog changed during byte verification.'
    }
    $result.role='AuthenticatedCandidateNativeResult';$result.nativeResultVerified=$true
    $result.verifiedUtc=[DateTimeOffset]::UtcNow.ToString('o');$result.evidenceDirectory=$directory
    [IO.File]::WriteAllText((Join-Path $directory 'verified-result.json'),($result|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
    return $result
}

Export-ModuleMember -Function Get-CiCandidateNativeResult
