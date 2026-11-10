# Synthetic archive/transport controls only; fixture bytes are never executed.
Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.CandidateArchives.psm1')
Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.CandidateVerification.psm1')
$candidateVerification=Get-Module Ci.CandidateVerification

function Set-CandidateFixtureArchive($Fixture,[string]$Name,[object[]]$Files){
    $path=Join-Path $Fixture.root ('.build/archives/'+[guid]::NewGuid().ToString('N')+'.zip')
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew)
    $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    try{
        foreach($file in $Files){
            $entry=$zip.CreateEntry($file.name)
            if($file.Contains('attributes')){$entry.ExternalAttributes=$file.attributes}
            $destination=$entry.Open();$bytes=[Text.UTF8Encoding]::new($false).GetBytes([string]$file.text)
            try{$destination.Write($bytes)}finally{$destination.Dispose()}
        }
    }finally{$zip.Dispose();$stream.Dispose()}
    $artifact=@($Fixture.envelope.artifacts|Where-Object artifactName -CEQ $Name)
    Assert-Equal 1 $artifact.Count
    $artifact[0].archiveSha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
    $artifact[0].archiveBytes=(Get-Item -LiteralPath $path).Length
    $Fixture.archives[$Name]=$path
}

function New-CandidateByteFixture([string]$Name){
    $source=New-CandidateResultFixture $Name
    $envelope=Invoke-CandidateResultEnvelope $source
    $f=@{root=$source.root;envelope=$envelope;archives=@{};receipts=@{}}
    Set-CandidateFixtureArchive $f 'candidate-inputs-2' @(
        @{name='candidate-inputs.json';text=($envelope.expectedInputs|ConvertTo-Json -Depth 30)},
        @{name='batch.json';text=($envelope.expectedInputs.batch|ConvertTo-Json -Depth 30)})
    foreach($platform in @('x64','ARM64')){
        $batch=$envelope.expectedInputs.batch
        $receipt=[ordered]@{schemaVersion=1;repository=$envelope.repository;commit=$batch.commit;nativeDigest=$batch.nativeDigest;
            runId=$envelope.runId;platform=$platform;role='ReleaseTest';passed=$true;countUnit='case';registered=1;expectedSkipped=0;
            discovered=1;executed=1;failed=0;unexpectedSkipped=0;assertionProbePassed=$true;
            executionBindingVersion=1;engine=$batch.engine;version=$batch.version;buildNumber=$batch.buildNumber;runAttempt=2;
            artifacts=@(@{path=".build/$platform/Release/fixture.exe";sha256=(Get-CiSha256 'Synthetic bytes; never executed.')});
            canonicalEvidence=@(@{path='D:\a\RedMonitor\RedMonitor\.build\evidence\native.json';sha256=(Get-CiSha256 '{"fixture":"synthetic-metadata-only"}')})}
        $f.receipts[$platform]=$receipt
        Set-CandidateFixtureArchive $f "candidate-regression-$platform-2" @(@{name="regression-$platform.json";text=($receipt|ConvertTo-Json -Depth 30)})
        Set-CandidateFixtureArchive $f "candidate-profile-$platform-2" @(@{name='fixture.exe';text='Synthetic bytes; never executed.'})
        Set-CandidateFixtureArchive $f "candidate-workspace-evidence-$platform-2" @(@{name='evidence/native.json';text='{"fixture":"synthetic-metadata-only"}'})
    }
    Set-CandidateFixtureArchive $f 'candidate-evidence-x64-2' @(@{name='fixture.json';text='{"nativeExecutions":0}'})
    return $f
}
function Invoke-CandidateByteFixture($Fixture){
    & $candidateVerification {param($f) Test-CiCandidateArtifactBytes -Envelope $f.envelope -Archives $f.archives} $Fixture
}

Invoke-Case 'Candidate byte verifier binds both original receipts, complete profiles and canonical evidence without extracting code' {
    $f=New-CandidateByteFixture 'candidate-archive-positive'
    $r=Invoke-CandidateByteFixture $f
    Assert-Equal 'CandidateNativeArtifactBytes' $r.role
    Assert-True $r.artifactBytesVerified
    Assert-Equal 2 $r.profiles.Count
    Assert-True (-not $r.mergeAuthorized -and -not $r.localDelegationEnabled -and -not $r.adoptionAuthorized)
    Assert-True (-not(Test-Path (Join-Path $f.root '.build/archives/fixture.exe')))
    # Closed owners release every file; an independent exclusive read now succeeds.
    foreach($path in $f.archives.Values){$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None);$stream.Dispose()}
}

Invoke-Case 'Candidate archives refuse hostile catalogs, malformed JSON and changed server-bound bytes' {
    $f=New-CandidateByteFixture 'candidate-archive-unsafe'
    $name='candidate-evidence-x64-2'
    foreach($files in @(
        @(@{name='../escape.json';text='{}'}), @(@{name='/absolute.json';text='{}'}),
        @(@{name='dir\file.json';text='{}'}), @(@{name='C:/escape.json';text='{}'}),
        @(@{name='CON.json';text='{}'}), @(@{name='dir/file. ';text='{}'}),
        @(@{name='a';text='x'},@{name='a';text='y'}),
        @(@{name='A';text='x'},@{name='a';text='y'}),
        @(@{name='A';text='x'},@{name='a/child';text='y'}),
        @(@{name='link';text='target';attributes=([int]0xA000 -shl 16)}),
        @(@{name='junction';text='target';attributes=0x400})
    )){
        Set-CandidateFixtureArchive $f $name $files
        Assert-Refused {Invoke-CandidateByteFixture $f}
    }
    foreach($json in @('{"identity":"first","identity":"second"}','{"identity":"first","Identity":"second"}','[]','not JSON')){
        Set-CandidateFixtureArchive $f $name @(@{name='fixture.json';text=$json})
        $record=@($f.envelope.artifacts|Where-Object artifactName -CEQ $name)[0]
        $archive=Open-CiCandidateArchive -Path $f.archives[$name] -Artifact $record
        try{Assert-Refused {Read-CiCandidateArchiveJson -Archive $archive -Path fixture.json}}finally{Close-CiCandidateArchive $archive}
    }
    Set-CandidateFixtureArchive $f $name @(@{name='fixture.json';text='{}'})
    [IO.File]::AppendAllText($f.archives[$name],'changed after server metadata acquisition')
    Assert-Refused {Invoke-CandidateByteFixture $f}
}

Invoke-Case 'Candidate byte verification refuses self-rehashed inputs, incomplete profiles, altered evidence and changed native identities' {
    foreach($scenario in @('inputs','batch','missing-profile','extra-profile','changed-profile','missing-evidence','changed-evidence',
        'foreign-evidence-root','traversal-evidence','failed-detector','zero-execution','wrong-attempt','wrong-version','missing-archive')){
        $f=New-CandidateByteFixture ('candidate-byte-'+$scenario)
        switch($scenario){
            'inputs' {
                $changed=$f.envelope.expectedInputs|ConvertTo-Json -Depth 30|ConvertFrom-Json -AsHashtable;$changed.candidate.identity='d'*64
                Set-CandidateFixtureArchive $f 'candidate-inputs-2' @(@{name='candidate-inputs.json';text=($changed|ConvertTo-Json -Depth 30)},@{name='batch.json';text=($f.envelope.expectedInputs.batch|ConvertTo-Json -Depth 30)})
            }
            'batch' {
                $changed=$f.envelope.expectedInputs.batch|ConvertTo-Json -Depth 30|ConvertFrom-Json -AsHashtable;$changed.commit='d'*40
                Set-CandidateFixtureArchive $f 'candidate-inputs-2' @(@{name='candidate-inputs.json';text=($f.envelope.expectedInputs|ConvertTo-Json -Depth 30)},@{name='batch.json';text=($changed|ConvertTo-Json -Depth 30)})
            }
            'missing-profile' {Set-CandidateFixtureArchive $f 'candidate-profile-ARM64-2' @(@{name='other.exe';text='Synthetic bytes; never executed.'})}
            'extra-profile' {Set-CandidateFixtureArchive $f 'candidate-profile-x64-2' @(@{name='fixture.exe';text='Synthetic bytes; never executed.'},@{name='extra.dll';text='Unbound bytes'})}
            'changed-profile' {Set-CandidateFixtureArchive $f 'candidate-profile-x64-2' @(@{name='fixture.exe';text='Different binary bytes'})}
            'missing-evidence' {Set-CandidateFixtureArchive $f 'candidate-workspace-evidence-x64-2' @(@{name='other.json';text='{}'})}
            'changed-evidence' {Set-CandidateFixtureArchive $f 'candidate-workspace-evidence-x64-2' @(@{name='evidence/native.json';text='{"altered":true}'})}
            'foreign-evidence-root' {$f.receipts.x64.canonicalEvidence[0].path='D:\foreign\.build\evidence\native.json'}
            'traversal-evidence' {$f.receipts.x64.canonicalEvidence[0].path='D:\a\RedMonitor\RedMonitor\.build\evidence\..\native.json'}
            'failed-detector' {$f.receipts.x64.assertionProbePassed=$false}
            'zero-execution' {$f.receipts.x64.executed=0}
            'wrong-attempt' {$f.receipts.x64.runAttempt=1}
            'wrong-version' {$f.receipts.x64.version='0.1.999'}
            'missing-archive' {$f.archives.Remove('candidate-profile-ARM64-2')}
        }
        Set-CandidateFixtureArchive $f 'candidate-regression-x64-2' @(@{name='regression-x64.json';text=($f.receipts.x64|ConvertTo-Json -Depth 30)})
        Assert-Refused {Invoke-CandidateByteFixture $f}
    }
}

Invoke-Case 'Public native result acquisition retains failures and refuses post-download attempt/catalog races before result publication' {
    $f=New-CandidateByteFixture 'candidate-native-result-public'
    $saved=& $candidateVerification {@{Envelope=(Get-Command Get-CiCandidateRunEnvelope).ScriptBlock;Receive=(Get-Command Receive-CiHostedArtifactArchive).ScriptBlock}}
    try{
        foreach($scenario in @('success','download-failure','attempt-race','catalog-race')){
            & $candidateVerification {
                param($f,$scenario)
                $script:verifyFixture=$f;$script:verifyScenario=$scenario;$script:envelopeReads=0
                function script:Get-CiCandidateRunEnvelope {
                    param($Root,$PullRequest,$ExpectedIdentity,$RunId,$Attempt,$IsolationNonce)
                    $script:envelopeReads++
                    $result=$script:verifyFixture.envelope|ConvertTo-Json -Depth 30|ConvertFrom-Json -AsHashtable
                    if($script:envelopeReads -gt 1){
                        if($script:verifyScenario -ceq 'attempt-race'){throw 'Recording current producer attempt changed.'}
                        if($script:verifyScenario -ceq 'catalog-race'){$result.artifacts[0].artifactId='999'}
                    }
                    return $result
                }
                function script:Receive-CiHostedArtifactArchive {
                    param($Repository,$Artifact,$Destination)
                    if($Repository -cne 'RedSalamanders/RedMonitor'){throw 'Foreign recording transport repository.'}
                    if($script:verifyScenario -ceq 'download-failure'){throw 'Recording original artifact download failure.'}
                    Copy-Item -LiteralPath $script:verifyFixture.archives[$Artifact.artifactName] -Destination $Destination
                }
            } $f $scenario
            $output=Join-Path $f.root ('.build/result-'+$scenario);[void][IO.Directory]::CreateDirectory($output)
            $request=@{Root=$f.root;PullRequest=43;ExpectedIdentity=$f.envelope.expectedInputs.candidate.identity;RunId='777';Attempt=2;IsolationNonce=('b'*32);OutputRoot=$output}
            if($scenario -ceq 'success'){
                $result=Get-CiCandidateNativeResult @request
                Assert-True $result.nativeResultVerified
                Assert-True (-not $result.mergeAuthorized -and -not $result.adoptionAuthorized)
            }else{Assert-Refused {Get-CiCandidateNativeResult @request}}
            $written=@(Get-ChildItem -LiteralPath $output -Recurse -Filter verified-result.json -File)
            Assert-Equal ([int]($scenario -ceq 'success')) $written.Count
            Assert-Equal 1 @(Get-ChildItem -LiteralPath $output -Recurse -Filter original-envelope.json -File).Count
            Assert-Equal $(if($scenario -ceq 'download-failure'){1}else{2}) (& $candidateVerification {$script:envelopeReads})
        }
    }finally{
        & $candidateVerification {param($saved) Set-Item Function:script:Get-CiCandidateRunEnvelope $saved.Envelope;Set-Item Function:script:Receive-CiHostedArtifactArchive $saved.Receive} $saved
    }
}
