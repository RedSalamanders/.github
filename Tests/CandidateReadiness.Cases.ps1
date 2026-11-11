# Cheap check catalog metadata only, never native execution or merge evidence.
Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.CandidateReadiness.psm1')
Invoke-Case 'Candidate readiness requires exact-head successful cheap checks and the original Root review app' {
    $candidate=@{repository='RedSalamanders/RedMonitor';headCommit=('a'*40)}
    $checks=@(foreach($name in @('checks / ci-gate','security / codeql','security / dependency-review')){
        @{name=$name;id=([array]::IndexOf(@('checks / ci-gate','security / codeql','security / dependency-review'),$name)+1);
            head_sha=$candidate.headCommit;app=@{id=15368};status='completed';conclusion='success'}
    })
    $catalog=@{total_count=3;check_runs=$checks}
    $records=@(Test-CiCandidateReadinessCatalog -Candidate $candidate -Catalog $catalog)
    Assert-Equal 3 $records.Count
    $original=$catalog|ConvertTo-Json -Depth 10
    foreach($change in @(
        {param($c)$c.total_count=4}, {param($c)$c.check_runs=@($c.check_runs[0],$c.check_runs[1]);$c.total_count=2},
        {param($c)$c.check_runs[0].app.id=999}, {param($c)$c.check_runs[0].head_sha='b'*40},
        {param($c)$c.check_runs[0].status='in_progress'}, {param($c)$c.check_runs[0].conclusion='failure'},
        {param($c)$c.check_runs[0].conclusion='cancelled'}, {param($c)$c.check_runs[0].conclusion='neutral'},
        {param($c)$c.check_runs[0].conclusion='skipped'}, {param($c)$c.check_runs[0].id='invalid'},
        {param($c)$c.check_runs[1].id=$c.check_runs[0].id},
        {param($c)$c.check_runs+=,$c.check_runs[0];$c.total_count=4}
    )){$changed=$original|ConvertFrom-Json -AsHashtable;$null=& $change $changed;Assert-Refused {Test-CiCandidateReadinessCatalog -Candidate $candidate -Catalog $changed}}
    # A native gate's pending state must not deadlock the admission needed to run it.
    $catalog.check_runs+=@{name='native / integration';id=99;head_sha=$candidate.headCommit;app=@{id=15368};status='in_progress';conclusion=$null};$catalog.total_count++
    Assert-Equal 3 @(Test-CiCandidateReadinessCatalog -Candidate $candidate -Catalog $catalog).Count
    $candidate.repository='RedSalamanders/RedSalamander'
    Assert-Refused {Test-CiCandidateReadinessCatalog -Candidate $candidate -Catalog $catalog}
    $catalog.check_runs+=@{name='Entire Gates';id=100;head_sha=$candidate.headCommit;app=@{id=2626939};status='completed';conclusion='success'};$catalog.total_count++
    Assert-Equal 4 @(Test-CiCandidateReadinessCatalog -Candidate $candidate -Catalog $catalog).Count
    $catalog.check_runs[-1].app.id=15368
    Assert-Refused {Test-CiCandidateReadinessCatalog -Candidate $candidate -Catalog $catalog}
    $catalog.check_runs[-1].app.id=2626939;$catalog.check_runs[-1].conclusion='failure'
    Assert-Refused {Test-CiCandidateReadinessCatalog -Candidate $candidate -Catalog $catalog}
}
