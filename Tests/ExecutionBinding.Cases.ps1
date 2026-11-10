# Sourced by Test-Engine.ps1, using its owned fixture and assertion helpers.
# These are synthetic metadata controls, never native execution/producer evidence.
Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Execution.psm1')
Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Project.psm1')

function Invoke-ExecutionFixtureWriter($Fixture,[string]$Directory) {
    $oldRun=$env:GITHUB_RUN_ID;$oldAttempt=$env:GITHUB_RUN_ATTEMPT;$oldOutput=$env:GITHUB_OUTPUT
    try{
        $env:GITHUB_RUN_ID='777';$env:GITHUB_RUN_ATTEMPT='2';$env:GITHUB_OUTPUT=''
        Write-CiRegressionReceipt -Context $Fixture.context -Discovered 1 -Executed 1 -AssertionProbePassed $true `
            -Artifacts $Fixture.artifacts -CanonicalEvidence $Fixture.evidence -EvidenceDirectory $Directory
    }finally{$env:GITHUB_RUN_ID=$oldRun;$env:GITHUB_RUN_ATTEMPT=$oldAttempt;$env:GITHUB_OUTPUT=$oldOutput}
}

function New-ExecutionBindingFixture([string]$Name,[string]$Platform='x64') {
    $root=New-Fixture $Name
    Write-FixtureFile $root '.gitignore' ".build/`n"
    $null=Save-Fixture $root 'Ignore owned synthetic output'
    $descriptor=New-CiInputDescriptor $root
    $descriptor.runId='777'
    Write-FixtureFile $root ".build/$Platform/Release/fixture.EXE" 'Synthetic bytes; never executed.'
    Write-FixtureFile $root '.build/evidence/native.json' '{"role":"SyntheticMetadataFixture","nativeExecutions":0}'
    $context=@{root=$root;batch=$descriptor;platform=$Platform}
    $data=[pscustomobject]@{root=$root;descriptor=$descriptor;context=$context;
        artifacts=(Get-CiProfileArtifacts -Context $context);
        evidence=(Get-CiEvidenceReference -Paths @((Join-Path $root '.build/evidence/native.json')))}
    Invoke-ExecutionFixtureWriter $data (Join-Path $root '.build/evidence/receipt')
    $receipt=Get-Content (Join-Path $root ".build/evidence/receipt/regression-$Platform.json") -Raw|ConvertFrom-Json -AsHashtable
    $data|Add-Member NoteProperty receipt $receipt
    return $data
}

Invoke-Case 'Actual regression writer retains frozen engine, version and attempt through JSON roundtrip' {
    foreach($platform in @('x64','ARM64')){
        $f=New-ExecutionBindingFixture ("execution-roundtrip-$platform") $platform
        Assert-True (Test-CiRegressionExecutionBinding -Receipt $f.receipt -Descriptor $f.descriptor -Platform $platform -RunId 777 -RunAttempt 2)
        Assert-Equal $f.descriptor.version $f.receipt.version
        Assert-Equal $f.descriptor.buildNumber $f.receipt.buildNumber
        Assert-Equal $f.descriptor.engine.ref $f.receipt.engine.ref
        Assert-Equal 2 $f.receipt.runAttempt
    }
}

Invoke-Case 'Execution binding refuses legacy, stale, mistyped, empty, duplicated and out-of-profile records' {
    $f=New-ExecutionBindingFixture 'execution-refusals'
    $original=$f.receipt|ConvertTo-Json -Depth 15
    $mutations=@(
        {param($r)$r.Remove('executionBindingVersion')},
        {param($r)$r.executionBindingVersion='1'},
        {param($r)$r.runAttempt=1}, {param($r)$r.runAttempt='2'},
        {param($r)$r.version='0.1.999'}, {param($r)$r.buildNumber=999},
        {param($r)$r.buildNumber=[string]$r.buildNumber},
        {param($r)$r.engine.ref='b'*40}, {param($r)$r.engine.repository='other/repository'},
        {param($r)$r.canonicalEvidence=@()}, {param($r)$r.canonicalEvidence=$r.canonicalEvidence[0]},
        {param($r)$r.canonicalEvidence=@($r.canonicalEvidence[0],$r.canonicalEvidence[0])},
        {param($r)$r.canonicalEvidence[0].sha256='bad'},
        {param($r)$r.artifacts=@($r.artifacts[0],$r.artifacts[0])},
        {param($r)$r.artifacts[0].path='.build/ARM64/Release/fixture.EXE'},
        {param($r)$r.artifacts[0].path='.build/x64/Release/../fixture.EXE'},
        {param($r)$r.artifacts[0].path='.build/x64/Release/data.json'},
        {param($r)$r.assertionProbePassed=$false}, {param($r)$r.executed=0}
    )
    foreach($mutate in $mutations){
        $r=$original|ConvertFrom-Json -AsHashtable
        $null=& $mutate $r
        Assert-Refused {Test-CiRegressionExecutionBinding -Receipt $r -Descriptor $f.descriptor -Platform x64 -RunId 777 -RunAttempt 2}
    }
    $legacy=$original|ConvertFrom-Json -AsHashtable
    foreach($field in @('executionBindingVersion','engine','version','buildNumber','runAttempt')){$legacy.Remove($field)}
    Assert-True (Test-CiRegressionReceipt -Receipt $legacy -Descriptor $f.descriptor -Platform x64)
    Assert-Refused {Test-CiRegressionExecutionBinding -Receipt $legacy -Descriptor $f.descriptor -Platform x64 -RunId 777 -RunAttempt 2}
}

Invoke-Case 'Execution publication refuses changed source and independently mismatched run or version inputs' {
    $f=New-ExecutionBindingFixture 'execution-source-mutation'
    Assert-Refused {Get-CiNativeExecutionBinding -Descriptor $f.descriptor -RunId 778 -RunAttempt 2}
    $broken=$f.descriptor|ConvertTo-Json -Depth 10|ConvertFrom-Json -AsHashtable
    $broken.version='0.1.999'
    Assert-Refused {Get-CiNativeExecutionBinding -Descriptor $broken -RunId 777 -RunAttempt 2}
    [IO.File]::AppendAllText((Join-Path $f.root 'src/main.cpp'),' changed input')
    $destination=Join-Path $f.root '.build/evidence/refused'
    Assert-Refused {Invoke-ExecutionFixtureWriter $f $destination}
    Assert-True (-not(Test-Path (Join-Path $destination 'regression-x64.json')))
}
