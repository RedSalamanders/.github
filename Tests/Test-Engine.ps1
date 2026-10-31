<#
.SYNOPSIS
Runs deterministic behavioral CI-policy tests in owned Git fixtures without native compilation.
.PARAMETER TestRoot
Existing marked RedSalamander.Perf sandbox, or a hosted RUNNER_TEMP child. Creates a unique child only.
.OUTPUTS
Case results and retained results.json beneath the selected root.
.NOTES
Requires PowerShell 7.4 and Git. No credentials, compiler or desktop input.
Windows formatting coverage downloads a pinned native formatter when its verified cache is absent.
Preserves all fixtures and failures. Returns nonzero on a failed case.
.EXAMPLE
./Tests/Test-Engine.ps1 -TestRoot Z:/RedSalamander.Perf
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TestRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$engineRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Policy.psm1') -ErrorAction Stop
$selectedRoot = [IO.Path]::GetFullPath($TestRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$hosted = $env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted' -and $env:RUNNER_TEMP
if ($hosted) {
    $hostedPrefix = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $selectedRoot.StartsWith($hostedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Hosted fixtures must remain under RUNNER_TEMP.' }
} else {
    if ($selectedRoot -notmatch '^[A-Za-z]:[\\/]RedSalamander\.Perf$') { throw 'Local tests require an existing marked RedSalamander.Perf root.' }
    $marker = Join-Path $selectedRoot '.red-salamander-test-root'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or [IO.File]::ReadAllText($marker).Trim() -cne 'red-salamander.test-sandbox-root.v1') { throw 'Missing existing sandbox ownership marker.' }
}
if ((Test-Path -LiteralPath $selectedRoot) -and ((Get-Item -LiteralPath $selectedRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Test root must not be a reparse point.' }
$runRoot = Join-Path $selectedRoot ('unified-ci/engine-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runRoot)
$script:rows = [Collections.Generic.List[object]]::new()

function Assert-True([bool]$Condition, [string]$Message = 'Expected true.') {
    if (-not $Condition) { throw $Message }
}
function Assert-Equal($Expected, $Actual) {
    if ($Expected -cne $Actual) { throw "Expected '$Expected', received '$Actual'." }
}
function Assert-Refused([scriptblock]$Body) {
    $refused = $false
    try { & $Body | Out-Null } catch { $refused = $true }
    if (-not $refused) { throw 'Expected the invalid input to be refused.' }
}
function Invoke-Case([string]$Name, [scriptblock]$Body) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Body
        $script:rows.Add([ordered]@{ name = $Name; passed = $true; elapsedMs = $timer.ElapsedMilliseconds })
        Write-Host "PASS $Name"
    } catch {
        $script:rows.Add([ordered]@{ name = $Name; passed = $false; error = $_.Exception.Message; stack = $_.ScriptStackTrace; elapsedMs = $timer.ElapsedMilliseconds })
        Write-Host "FAIL $Name : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace
    }
}
function Write-FixtureFile([string]$Root, [string]$Path, [string]$Text) {
    $target = Join-Path $Root $Path
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    [IO.File]::WriteAllText($target, $Text, [Text.UTF8Encoding]::new($false))
}
function New-Fixture([string]$Name) {
    $root = Join-Path $runRoot $Name
    [void][IO.Directory]::CreateDirectory($root)
    $null = Invoke-CiGit $root @('init', '--initial-branch=main')
    foreach ($setting in @(@('user.name', 'CI Fixture'), @('user.email', 'ci-fixture@example.invalid'),
            @('commit.gpgsign', 'false'), @('core.autocrlf', 'false'), @('core.longpaths', 'true'),
            @('core.hooksPath', (Join-Path $root '.empty-hooks')))) {
        $null = Invoke-CiGit $root @('config', $setting[0], $setting[1])
    }
    $manifest = [ordered]@{ schemaVersion = 1; policyVersion = '1'; repository = 'RedSalamanders/RedMonitor';
        engine = @{ repository = 'RedSalamanders/.github'; ref = ('a' * 40) }; kind = 'application';
        adapter = 'Tools/Invoke-ProjectCi.ps1'; include = @('Specs/runtime.json', 'Tests/fixtures/**');
        exclude = @('**/*.md', 'docs/**', 'Specs/Plans/**', 'Changes/**'); formatRoots = @('src');
        versionBase = '0.1'; winget = @{ identifier = 'RedSalamanders.RedMonitor'; executable = 'RedMonitor.exe'; alias = 'redmonitor' } }
    Write-FixtureFile $root '.ci/project.json' ($manifest | ConvertTo-Json -Depth 8)
    Write-FixtureFile $root 'src/main.cpp' 'int fixture() { return 0; }'
    Write-FixtureFile $root 'README.md' 'Initial prose.'
    $null = Invoke-CiGit $root @('add', '--all')
    $null = Invoke-CiGit $root @('commit', '-m', 'Fixture baseline')
    return $root
}
function Save-Fixture([string]$Root, [string]$Message) {
    $null = Invoke-CiGit $Root @('add', '--all')
    $null = Invoke-CiGit $Root @('commit', '-m', $Message)
    (Invoke-CiGit $Root @('rev-parse', 'HEAD')).stdout.Trim()
}

Invoke-Case 'Prose changes create zero native obligation and retain native input identity' {
    $root = New-Fixture 'prose'
    $before = New-CiInputDescriptor $root
    Write-FixtureFile $root 'README.md' 'Changed prose.'
    Write-FixtureFile $root 'Specs/Plans/WIP/Proposal.md' 'A proposal only.'
    $null = Save-Fixture $root 'Documentation only'
    $after = New-CiInputDescriptor $root
    Assert-Equal $before.nativeDigest $after.nativeDigest
    Assert-True (-not (Get-CiChangeDecision $root $before.commit).meaningful)
}
Invoke-Case 'A code merge followed by docs still carries the cumulative code obligation' {
    $root = New-Fixture 'cumulative'
    $before = New-CiInputDescriptor $root
    Write-FixtureFile $root 'src/main.cpp' 'int fixture() { return 7; }'
    $code = Save-Fixture $root 'Meaningful code'
    $codeDescriptor = New-CiInputDescriptor $root
    Write-FixtureFile $root 'README.md' 'Prose after code.'
    $null = Save-Fixture $root 'Later documentation'
    $after = New-CiInputDescriptor $root
    Assert-True ($before.nativeDigest -cne $after.nativeDigest)
    Assert-Equal $codeDescriptor.nativeDigest $after.nativeDigest
    Assert-True (-not (Get-CiChangeDecision $root $code).meaningful)
    Assert-True (Get-CiChangeDecision $root $before.commit).meaningful
}
Invoke-Case 'Shipped schema and test fixture Markdown override surrounding exclusions' {
    $root = New-Fixture 'exceptions'
    $before = New-CiInputDescriptor $root
    Write-FixtureFile $root 'Specs/runtime.json' '{"runtime":true}'
    Write-FixtureFile $root 'Tests/fixtures/sample.md' 'Runtime fixture.'
    $null = Save-Fixture $root 'Runtime data'
    $decision = Get-CiChangeDecision $root $before.commit
    Assert-True $decision.meaningful
    Assert-Equal 2 @($decision.paths | Where-Object native).Count
}
Invoke-Case 'Complete comparison sees meaningful input beyond 300 changed paths' {
    $root = New-Fixture 'large-diff'
    $before = New-CiInputDescriptor $root
    foreach ($index in 1..320) { Write-FixtureFile $root ("docs/page-$index.md") 'Prose.' }
    Write-FixtureFile $root 'zz-meaningful.rc' 'A resource input.'
    $null = Save-Fixture $root 'Large comparison'
    $decision = Get-CiChangeDecision $root $before.commit
    Assert-Equal 321 @($decision.paths).Count
    Assert-True $decision.meaningful
}
Invoke-Case 'A rename into an excluded folder retains the old meaningful path' {
    $root = New-Fixture 'rename'
    $before = New-CiInputDescriptor $root
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'docs'))
    $null = Invoke-CiGit $root @('mv', 'src/main.cpp', 'docs/moved.cpp')
    $null = Save-Fixture $root 'Rename'
    $paths = Get-CiChangedPaths $root $before.commit
    Assert-True ($paths -ccontains 'src/main.cpp')
    Assert-True ($paths -ccontains 'docs/moved.cpp')
    Assert-True (Get-CiChangeDecision $root $before.commit).meaningful
}
Invoke-Case 'Deleting a native input changes its identity' {
    $root = New-Fixture 'deletion'
    $before = New-CiInputDescriptor $root
    $null = Invoke-CiGit $root @('rm', '--', 'src/main.cpp')
    $null = Save-Fixture $root 'Delete native input'
    Assert-True (Get-CiChangeDecision $root $before.commit).meaningful
    Assert-True ($before.nativeDigest -cne (New-CiInputDescriptor $root).nativeDigest)
}
Invoke-Case 'Unicode paths survive Git transport and are meaningful' {
    $root = New-Fixture 'unicode'
    $before = New-CiInputDescriptor $root
    Write-FixtureFile $root 'src/été fixture.h' 'A native header.'
    $null = Save-Fixture $root 'Unicode input'
    Assert-True ((Get-CiChangedPaths $root $before.commit) -ccontains 'src/été fixture.h')
}
Invoke-Case 'Unknown inputs are conservative and an unreadable comparison is refused' {
    $root = New-Fixture 'unknown'
    $project = Read-CiProject $root
    Assert-True (Get-CiPathDisposition 'new/input.unrecognized' $project).native
    Assert-Refused { Get-CiChangeDecision $root 'missing-ref' }
    Assert-Refused { Get-CiPathDisposition '../escape' $project }
}
Invoke-Case 'Strict schema rejects unknown policy keys and invalid path patterns' {
    $root = New-Fixture 'invalid-manifest'
    $project = Read-CiProject $root
    $project['unexpected'] = 'not supported'
    Write-FixtureFile $root '.ci/project.json' ($project | ConvertTo-Json -Depth 8)
    Assert-Refused { Read-CiProject $root }
    $null = $project.Remove('unexpected')
    $project.exclude = @('../escape/**')
    Write-FixtureFile $root '.ci/project.json' ($project | ConvertTo-Json -Depth 8)
    Assert-Refused { Read-CiProject $root }
}
Invoke-Case 'Snapshot uses the exact committed manifest rather than mutable working-tree policy' {
    $root = New-Fixture 'committed-manifest'
    $before = New-CiInputDescriptor $root
    $project = Read-CiProject $root
    $project.exclude += 'src/**'
    Write-FixtureFile $root '.ci/project.json' ($project | ConvertTo-Json -Depth 8)
    Assert-Equal $before.nativeDigest (New-CiInputDescriptor $root).nativeDigest
}
Invoke-Case 'Public classification command returns the same real Git decision' {
    $root = New-Fixture 'public-command'
    $before = New-CiInputDescriptor $root
    Write-FixtureFile $root 'src/extra.h' 'A meaningful header.'
    $null = Save-Fixture $root 'Header'
    $result = Invoke-CiProcess (Get-Process -Id $PID).Path @('-NoProfile', '-File', (Join-Path $engineRoot 'Tools/Get-ChangeDecision.ps1'), '-Root', $root, '-Base', $before.commit) $engineRoot
    $decision = $result.stdout | ConvertFrom-Json
    Assert-True $decision.meaningful
    Assert-Equal 'src/extra.h' $decision.paths[0].path
}
Invoke-Case 'Three nearby merges admit only after five minutes from the last merge' {
    $anchor = [DateTimeOffset]'2026-01-01T00:00:00Z'
    $state = Get-CiQuietDecision 'a' $anchor 'a' $anchor.AddSeconds(299)
    Assert-True (-not $state.quiet)
    $state = Get-CiQuietDecision 'a' $anchor 'b' $anchor.AddSeconds(100)
    $state = Get-CiQuietDecision 'b' ([DateTimeOffset]$state.observedAt) 'c' $anchor.AddSeconds(200)
    Assert-True (-not (Get-CiQuietDecision 'c' ([DateTimeOffset]$state.observedAt) 'c' $anchor.AddSeconds(499)).quiet)
    Assert-True (Get-CiQuietDecision 'c' ([DateTimeOffset]$state.observedAt) 'c' $anchor.AddSeconds(500)).quiet
    Assert-Refused { Get-CiQuietDecision 'a' $anchor 'a' $anchor.AddSeconds(-1) }
}
Invoke-Case 'Continuous merges reset admission without a hidden maximum-deferral override' {
    $start = [DateTimeOffset]'2026-01-01T00:00:00Z'
    $head = '0'; $observed = $start
    foreach ($minute in 1..40) {
        $next = [string]$minute
        $state = Get-CiQuietDecision $head $observed $next $start.AddMinutes($minute)
        Assert-True (-not $state.quiet)
        $head = $state.head; $observed = [DateTimeOffset]$state.observedAt
    }
}
Invoke-Case 'Recorded failures survive docs and only an explicit retry readmits identical inputs' {
    $candidate = @{ commit = 'new-docs'; nativeDigest = 'same' }
    foreach ($outcome in @('running','succeeded','failed','cancelled')) {
        $state = @{ nativeDigest = 'same'; outcome = $outcome; runId = '42' }
        $decision = Get-CiAdmissionDecision $candidate $state 'new-docs' $true
        Assert-Equal 'retain' $decision.action
        Assert-Equal $outcome $decision.outcome
    }
    Assert-Equal 'admit' (Get-CiAdmissionDecision $candidate $state 'new-docs' $true -Retry).action
    Assert-Equal 'wait' (Get-CiAdmissionDecision $candidate $null 'new-docs' $false).action
    Assert-Equal 'superseded' (Get-CiAdmissionDecision $candidate $null 'later-code' $true).action
}
Invoke-Case 'Regression gate rejects empty execution, disabled assertions, skips and stale identities' {
    $descriptor = @{ repository = 'RedSalamanders/RedMonitor'; commit = ('a' * 40); nativeDigest = ('b' * 64); runId = '42' }
    $valid = @{ schemaVersion = 1; repository = $descriptor.repository; commit = $descriptor.commit; nativeDigest = $descriptor.nativeDigest;
        platform = 'x64'; role = 'ReleaseTest'; passed = $true; discovered = 12; executed = 12; failed = 0; unexpectedSkipped = 0;
        countUnit='case';registered=12;expectedSkipped=0;assertionProbePassed = $true; runId = '42'; artifacts = @(@{ path = 'MonitorTest.exe'; sha256 = ('c' * 64) }) }
    Assert-True (Test-CiRegressionReceipt $valid $descriptor 'x64')
    foreach ($mutation in @(@{ discovered = 0 }, @{ executed = 0 }, @{ failed = 1 }, @{ unexpectedSkipped = 1 },
            @{ assertionProbePassed = $false }, @{ passed = 'true' }, @{ commit = ('d' * 40) },
            @{ platform = 'ARM64' }, @{ artifacts = @() }, @{ role = 'ProductionRelease' })) {
        $broken = $valid.Clone()
        foreach ($key in $mutation.Keys) { $broken[$key] = $mutation[$key] }
        Assert-Refused { Test-CiRegressionReceipt $broken $descriptor 'x64' }
    }
}

Invoke-Case 'State updates use a captured parent and a non-forced ref update' {
    $module = Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.GitHub.psm1') -PassThru
    $original = & $module { (Get-Command Invoke-CiApi).ScriptBlock }
    try {
        & $module {
            $script:fixtureCalls = [Collections.Generic.List[object]]::new()
            $script:fixtureState = @{ schemaVersion = 1; repository = 'RedSalamanders/RedMonitor'; nativeDigest = ('b' * 64);
                commit = ('a' * 40); runId = '41'; outcome = 'failed' }
            function script:Invoke-CiApi {
                param($Route, $Method = 'GET', $Body, [switch]$AllowNotFound)
                $script:fixtureCalls.Add(@{ route = $Route; method = $Method; body = $Body })
                if ($Route -like '*/git/ref/heads/ci-state') { return @{ object = @{ sha = ('d' * 40) } } }
                if ($Route -like '*/contents/state.json?*') {
                    return @{ encoding = 'base64'; content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($script:fixtureState | ConvertTo-Json -Compress))) }
                }
                if ($Method -eq 'PATCH') { return @{ object = @{ sha = ('e' * 40) } } }
                return @{ sha = ('e' * 40) }
            }
        }
        $state = @{ schemaVersion = 1; repository = 'RedSalamanders/RedMonitor'; nativeDigest = ('c' * 64);
            commit = ('a' * 40); runId = '42'; outcome = 'running' }
        $newHead = & $module { param($Value) Write-CiState 'RedSalamanders/RedMonitor' $Value ('d' * 40) } $state
        Assert-Equal ('e' * 40) $newHead
        $calls = & $module { $script:fixtureCalls.ToArray() }
        $commitCall = @($calls | Where-Object { $_.route -like '*/git/commits' })[0]
        Assert-Equal ('d' * 40) $commitCall.body.parents[0]
        $update = @($calls | Where-Object method -eq 'PATCH')[0]
        Assert-Equal $false $update.body.force
        Assert-True (-not (@($calls | Where-Object { $_.route -like '*/dispatches' }).Count))
        Assert-Refused { & $module { param($Value) Write-CiState 'RedSalamanders/RedMonitor' $Value ('f' * 40) } $state }
    } finally { & $module { param($Original) Set-Item Function:script:Invoke-CiApi -Value $Original } $original }
}
Invoke-Case 'Real Git fast-forward semantics refuse competing sibling state commits' {
    $root = New-Fixture 'atomic-state'
    $parent = (Invoke-CiGit $root @('rev-parse', 'HEAD')).stdout.Trim()
    $tree = (Invoke-CiGit $root @('rev-parse', 'HEAD^{tree}')).stdout.Trim()
    $first = (Invoke-CiGit $root @('commit-tree', $tree, '-p', $parent, '-m', 'First admitted contender')).stdout.Trim()
    $second = (Invoke-CiGit $root @('commit-tree', $tree, '-p', $parent, '-m', 'Competing sibling')).stdout.Trim()
    $null = Invoke-CiGit $root @('update-ref', 'refs/heads/ci-state', $first)
    $canFastForward = Invoke-CiGit $root @('merge-base', '--is-ancestor', $first, $second) -AllowFailure
    Assert-Equal 1 $canFastForward.exitCode
    Assert-Equal $first (Invoke-CiGit $root @('rev-parse', 'refs/heads/ci-state')).stdout.Trim()
}
Invoke-Case 'An ended workflow without a recorded qualification never recovers as success' {
    $module = Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.GitHub.psm1') -PassThru
    $original = & $module { (Get-Command Invoke-CiApi).ScriptBlock }
    try {
        & $module { function script:Invoke-CiApi { param($Route) return @{ status = 'completed'; conclusion = 'success' } } }
        $state = @{ schemaVersion = 1; repository = 'RedSalamanders/RedMonitor'; nativeDigest = ('b' * 64);
            commit = ('a' * 40); runId = '42'; outcome = 'running' }
        $resolved = & $module { param($Value) Resolve-CiStateOutcome $Value } $state
        Assert-Equal 'failed' $resolved.outcome
        Assert-Equal 'running' $state.outcome
    } finally { & $module { param($Original) Set-Item Function:script:Invoke-CiApi -Value $Original } $original }
}
Invoke-Case 'API routes outside the reviewed repositories are refused before credential use' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.GitHub.psm1')
    Assert-Refused { Invoke-CiApi 'repos/untrusted/other/git/ref/heads/main' }
}
if ([OperatingSystem]::IsWindows()) {
    Invoke-Case 'Pinned formatter produces a narrow real patch and leaves the Git head unchanged' {
        Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Format.psm1')
        $root = New-Fixture 'formatting'
        Write-FixtureFile $root '.clang-format' "BasedOnStyle: LLVM"
        $base = Save-Fixture $root 'Format policy'
        Write-FixtureFile $root 'src/main.cpp' 'int fixture(){return  9;}'
        Write-FixtureFile $root 'third-party/vendor.cpp' 'int vendor( ){return  8; }'
        $head = Save-Fixture $root 'Changed native files'
        $result = Invoke-CiFormatting $root $base
        Assert-True $result.drift
        Assert-Equal 1 $result.checked
        Assert-Equal 1 @($result.changedPaths).Count
        Assert-Equal 'src/main.cpp' $result.changedPaths[0]
        Assert-Equal $head (Invoke-CiGit $root @('rev-parse', 'HEAD')).stdout.Trim()
        $patch = [IO.File]::ReadAllText($result.patch)
        Assert-True ($patch.Contains('diff --git a/src/main.cpp b/src/main.cpp'))
        Assert-True (-not $patch.Contains('vendor.cpp'))
        $formatted = Save-Fixture $root 'Explicitly adopt fixture formatting'
        $clean = Invoke-CiFormatting $root $base
        Assert-Equal $false $clean.drift
        Assert-Equal 0 $clean.changedPaths.Count
        Assert-Equal $formatted (Invoke-CiGit $root @('rev-parse','HEAD')).stdout.Trim()
        Write-FixtureFile $root 'src/main.cpp' 'int fixture(){return 10;}'
        Write-FixtureFile $root 'src/second.cpp' 'int second(){return  1;}'
        $null = Save-Fixture $root 'Two independently changed source files'
        $multiple = Invoke-CiFormatting $root $formatted
        Assert-Equal 2 $multiple.checked
        Assert-Equal 2 $multiple.changedPaths.Count
        Assert-True ($multiple.changedPaths -ccontains 'src/main.cpp')
        Assert-True ($multiple.changedPaths -ccontains 'src/second.cpp')
        Assert-Refused { Assert-CiContainedPath $root (Join-Path $root '../outside') }
    }
}

Invoke-Case 'Revision options cannot turn classification into a Git write or external command' {
    $root = New-Fixture 'revision-options'
    Assert-Refused { Get-CiChangeDecision $root '--output=outside.txt' }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'outside.txt')))
}
Invoke-Case 'Static project command selection refuses compiler-dependent entry points' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Project.psm1')
    $root = New-Fixture 'compiler-free'
    Write-FixtureFile $root 'build.ps1' "throw 'A build must never start in static checks.'"
    $context = @{ root = $root; phase = 'Static'; project = @{ repository = 'RedSalamanders/RedMonitor' } }
    Assert-Refused { Invoke-CiProjectScript $context 'build.ps1' }
}
Invoke-Case 'Windowless child diagnostics preserve both output streams and the real exit code' {
    $root = New-Fixture 'streaming-exit'
    $hostPath = (Get-Process -Id $PID).Path
    $old=$env:GH_TOKEN
    try {
        $env:GH_TOKEN='ci-fake-credential-value'
        $command='[Console]::Out.WriteLine("child stdout ci-fake-credential-value"); [Console]::Error.WriteLine("child stderr"); exit 17'
        $records=@(& { Invoke-CiProcess -FilePath $hostPath -Arguments @('-NoProfile','-NonInteractive','-Command',$command) -WorkingDirectory $root -Stream -AllowFailure } 6>&1)
        $result=@($records|Where-Object {$_ -isnot [Management.Automation.InformationRecord]})[0]
        $printed=(@($records|Where-Object {$_ -is [Management.Automation.InformationRecord]}|ForEach-Object ToString) -join [char]10)
        Assert-Equal 17 $result.exitCode
        Assert-True ($result.stdout.Contains('child stdout') -and $result.stderr.Contains('child stderr'))
        Assert-True ($printed.Contains('child stdout <credential>') -and $printed.Contains('child stderr'))
        Assert-True (-not $printed.Contains($env:GH_TOKEN))
    } finally {$env:GH_TOKEN=$old}
}

Invoke-Case 'Production admission refuses test-role evidence, stale attempts and modified ZIP bytes' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Artifacts.psm1')
    $root = New-Fixture 'production-bytes'
    Write-FixtureFile $root 'payload/app.exe' 'qualified synthetic bytes'
    $zip = Join-Path $root 'RedMonitor-x64.zip'
    Compress-Archive -LiteralPath (Join-Path $root 'payload/app.exe') -DestinationPath $zip
    $descriptor = @{ repository='RedSalamanders/RedMonitor';commit=('a'*40);nativeDigest=('b'*64);
        engine=@{repository='RedSalamanders/.github';ref=('c'*40)};version='0.1.123';buildNumber=123;runId='42' }
    $valid = @{ schemaVersion=1;repository=$descriptor.repository;commit=$descriptor.commit;nativeDigest=$descriptor.nativeDigest;
        engine=$descriptor.engine;platform='x64';version=$descriptor.version;buildNumber=123;runId='42';
        role='ProductionRelease';testModeDisabled=$true;smokePassed=$true;kind='application';
        archives=@(@{file='RedMonitor-x64.zip';size=(Get-Item $zip).Length;sha256=(Get-FileHash $zip).Hash.ToLowerInvariant()}) }
    Assert-True (Test-CiProductionReceipt $valid $descriptor 'x64')
    foreach ($mutation in @(@{role='ReleaseTest'},@{runId='41'},@{testModeDisabled=$false},@{smokePassed='true'},@{kind='sdk'},@{archives=@()})) {
        $broken=$valid.Clone();foreach($key in $mutation.Keys){$broken[$key]=$mutation[$key]}
        Assert-Refused { Test-CiProductionReceipt $broken $descriptor 'x64' }
    }
    [IO.File]::AppendAllText($zip,'changed')
    Assert-Refused { Test-CiProductionReceipt $valid $descriptor 'x64' $root }
}
Invoke-Case 'The global test gate needs both architecture receipts from the same admitted run' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Artifacts.psm1')
    $root=New-Fixture 'global-test-gate'
    $descriptor=@{repository='RedSalamanders/RedMonitor';commit=('a'*40);nativeDigest=('b'*64);runId='42'}
    foreach($platform in @('x64','ARM64')){
        $receipt=@{schemaVersion=1;repository=$descriptor.repository;commit=$descriptor.commit;nativeDigest=$descriptor.nativeDigest;runId='42';
            platform=$platform;role='ReleaseTest';passed=$true;discovered=6;executed=6;failed=0;unexpectedSkipped=0;
            countUnit='scenario';registered=6;expectedSkipped=0;assertionProbePassed=$true;artifacts=@(@{path='MonitorTest.exe';sha256=('c'*64)})}
        Write-FixtureFile $root "regression-$platform.json" ($receipt|ConvertTo-Json -Depth 8)
        if($platform -eq 'x64'){Assert-Refused {Test-CiQualification $root $descriptor Regression}}
    }
    Assert-True (Test-CiQualification $root $descriptor Regression)
    $path=Join-Path $root 'regression-ARM64.json'
    $receipt=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable
    $receipt.runId='41'
    Write-FixtureFile $root 'regression-ARM64.json' ($receipt|ConvertTo-Json -Depth 8)
    Assert-Refused { Test-CiQualification $root $descriptor Regression }
}
Invoke-Case 'winget uses the ZIP nested executable and rejects SDK, missing licensing and unsafe paths' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Publication.psm1')
    $root=New-Fixture 'winget-nested'
    $assets=foreach($platform in @('x64','ARM64')){
        $path=Join-Path $root "RedMonitor-$platform.zip"
        $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
        try {$entry=$zip.CreateEntry('product/RedMonitor.exe');$stream=$entry.Open();try{$stream.WriteByte(42)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
        @{platform=$platform;file=[IO.Path]::GetFileName($path);path=$path;sha256=(Get-FileHash $path).Hash.ToLowerInvariant();size=(Get-Item $path).Length}
    }
    $plan=@{project=@{repository='RedSalamanders/RedMonitor';kind='application';winget=@{identifier='RedSalamanders.RedMonitor';executable='RedMonitor.exe';alias='redmonitor';license='MIT';minimumOSVersion='10.0.22000.2600'}};
        batch=@{version='0.1.123'};tag='v0.1.123';assets=@($assets)}
    $directory=Join-Path $root 'manifest'
    $null=New-CiWingetManifest $plan $directory
    $installer=[IO.File]::ReadAllText((Join-Path $directory 'RedSalamanders.RedMonitor.installer.yaml'))
    Assert-True ($installer.Contains("RelativeFilePath: 'product/RedMonitor.exe'"))
    Assert-True ($installer.Contains('Architecture: arm64') -and $installer.Contains('NestedInstallerType: portable'))
    Assert-True ($installer.Contains('MinimumOSVersion: 10.0.22000.2600') -and $installer.Contains('FileType: launch'))
    foreach($asset in $assets){
        $zip=[IO.Compression.ZipFile]::Open($asset.path,[IO.Compression.ZipArchiveMode]::Update)
        try{$entry=$zip.CreateEntry("product/tools/red.exe");$stream=$entry.Open();try{$stream.WriteByte(43)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
    }
    $plan.project.winget.additionalCommands=@(@{executable='red.exe';alias='RedCommand'})
    $multi=Join-Path $root 'multiple-commands'
    $null=New-CiWingetManifest $plan $multi
    $text=[IO.File]::ReadAllText((Join-Path $multi 'RedSalamanders.RedMonitor.installer.yaml'))
    Assert-Equal 2 ([regex]::Matches($text,"PortableCommandAlias: 'RedCommand'").Count)
    Assert-True ($text.Contains("RelativeFilePath: 'product/tools/red.exe'"))
    $plan.project.winget.additionalCommands[0].alias='redmonitor'
    Assert-Refused { New-CiWingetManifest $plan (Join-Path $root 'duplicate-alias') }
    $plan.project.winget.additionalCommands[0].alias='unsafe:alias'
    Assert-Refused { New-CiWingetManifest $plan (Join-Path $root 'unsafe-alias') }
    $plan.project.winget.license=''
    Assert-Refused { New-CiWingetManifest $plan (Join-Path $root 'missing-license') }
    $plan.project.kind='sdk';$plan.project.winget=$null
    Assert-Refused { New-CiWingetManifest $plan (Join-Path $root 'sdk-refused') }
}

function New-InstallFixture([string]$Name) {
    $root=New-Fixture ('install-'+$Name)
    $fixture=@{root=$root;installed=$false;initial=$false;mode='';calls=[Collections.Generic.List[object]]::new()}
    $fixture.plan=@{batch=@{version='1.0.42'};project=@{winget=@{identifier='RedSalamanders.RedXe';executable='RedXeLauncher.exe';alias='RedXe';
        additionalCommands=@(@{executable='red.exe';alias='red'});
        smokeTests=@(@{command='RedXe';arguments=@('--self-test','--warp');timeoutSeconds=300})}}}
    $fixture.readInstalled={
        param($Identifier)
        if($fixture.installed -or $fixture.initial){
            $location=Join-Path $fixture.root $(if($fixture.mode -eq 'foreign'){'foreign'}else{'installed'})
            return @{identifier=$Identifier;version='1.0.42';location=$location}
        }
    }.GetNewClosure()
    $fixture.readAlias={
        param($Command,$Platform)
        if($fixture.installed){
            if($fixture.mode -eq 'missing-alias'){return $null}
            $executable=if($Command -eq 'RedXe'){'RedXeLauncher.exe'}else{'red.exe'}
            $target=Join-Path $fixture.root ('installed/product/'+$executable)
            if($fixture.mode -eq 'wrong-target'){$target=Join-Path $fixture.root 'elsewhere/RedXeLauncher.exe'}
            return @{path=(Join-Path $fixture.root ($Command+'.exe'));target=$target;
                version=$(if($fixture.mode -eq 'wrong-version'){'1.0.41'}else{'1.0.42'})}
        }
    }.GetNewClosure()
    $fixture.execute={
        param($File,$CommandArguments,$Seconds)
        $fixture.calls.Add(@{file=$File;arguments=@($CommandArguments);seconds=$Seconds})
        $exitCode=0
        if($File -eq 'winget-fixture'){
            if($CommandArguments[0] -eq 'list'){throw 'An unpublished install must not depend on source-correlated winget list.'}
            if($CommandArguments[0] -eq 'install'){$fixture.installed=$true;if($fixture.mode -eq 'partial-install'){$exitCode=7}}
            if($CommandArguments[0] -eq 'uninstall' -and $fixture.mode -ne 'failed-cleanup'){$fixture.installed=$false}
        }elseif('--self-test' -in $CommandArguments -and $fixture.mode -eq 'timeout'){
            throw 'Owned smoke timed out.'
        }elseif($fixture.mode -eq 'probe-failure'){$exitCode=21}
        return @{exitCode=$exitCode;stdout='fixture output';stderr=''}
    }.GetNewClosure()
    return $fixture
}
function Run-InstallFixture($Fixture) {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.WingetInstall.psm1')
    $parameters=@{Plan=$Fixture.plan;Manifest=$Fixture.root;Scratch=$Fixture.root;Platform='x64';Winget='winget-fixture';
        ReadInstalled=$Fixture.readInstalled;ReadAlias=$Fixture.readAlias;Execute=$Fixture.execute}
    Invoke-CiOwnedWingetInstall @parameters
}
Invoke-Case 'Unpublished winget installation proves every alias, product smoke and manifest-based cleanup without list correlation' {
    $fixture=New-InstallFixture 'complete'
    $proof=Run-InstallFixture $fixture
    Assert-True ($proof.passed -and $proof.cleanedUp -and -not $fixture.installed)
    Assert-Equal 2 $proof.aliases
    Assert-Equal 3 $proof.probes
    $smoke=@($fixture.calls|Where-Object{'--self-test' -in $_.arguments})
    Assert-Equal 1 $smoke.Count
    Assert-Equal 300 $smoke[0].seconds
    $uninstall=@($fixture.calls|Where-Object{$_.arguments[0] -eq 'uninstall'})
    Assert-Equal 1 $uninstall.Count
    Assert-True ('--manifest' -in $uninstall[0].arguments -and '--version' -in $uninstall[0].arguments)
}
Invoke-Case 'An existing portable product is refused before any install or removal' {
    $fixture=New-InstallFixture 'existing'
    $fixture.initial=$true
    Assert-Refused {Run-InstallFixture $fixture}
    Assert-Equal 0 $fixture.calls.Count
}
Invoke-Case 'Missing, foreign-target and stale-version aliases reject qualification and clean only the owned product' {
    foreach($mode in @('missing-alias','wrong-target','wrong-version')){
        $fixture=New-InstallFixture $mode;$fixture.mode=$mode
        Assert-Refused {Run-InstallFixture $fixture}
        Assert-True (-not $fixture.installed)
        Assert-Equal 1 @($fixture.calls|Where-Object{$_.arguments[0] -eq 'uninstall'}).Count
    }
}
Invoke-Case 'A failing or timed-out installed product probe retains failure and still uninstalls its owned package' {
    foreach($mode in @('probe-failure','timeout')){
        $fixture=New-InstallFixture $mode;$fixture.mode=$mode
        Assert-Refused {Run-InstallFixture $fixture}
        Assert-True (-not $fixture.installed)
        Assert-Equal 1 @($fixture.calls|Where-Object{$_.arguments[0] -eq 'uninstall'}).Count
    }
}
Invoke-Case 'A partial install is cleaned but a foreign registration is never removed' {
    $fixture=New-InstallFixture 'partial';$fixture.mode='partial-install'
    Assert-Refused {Run-InstallFixture $fixture}
    Assert-True (-not $fixture.installed)
    $fixture=New-InstallFixture 'foreign';$fixture.mode='foreign'
    Assert-Refused {Run-InstallFixture $fixture}
    Assert-True $fixture.installed
    Assert-Equal 0 @($fixture.calls|Where-Object{$_.arguments[0] -eq 'uninstall'}).Count
}
Invoke-Case 'Cleanup failure cannot write a passing native installation proof' {
    $fixture=New-InstallFixture 'cleanup';$fixture.mode='failed-cleanup'
    Assert-Refused {Run-InstallFixture $fixture}
    Assert-True $fixture.installed
}
Invoke-Case 'Undeclared or unbounded product smoke commands are refused before installation' {
    foreach($change in @(@{command='another-app'},@{timeoutSeconds=601})){
        $fixture=New-InstallFixture ('bad-smoke-'+@($change.Keys)[0])
        foreach($key in $change.Keys){$fixture.plan.project.winget.smokeTests[0][$key]=$change[$key]}
        Assert-Refused {Run-InstallFixture $fixture}
        Assert-Equal 0 $fixture.calls.Count
    }
}
Invoke-Case 'Submission needs source-matching native alias, product probe and actual cleanup counts' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.WingetInstall.psm1')
    $fixture=New-InstallFixture 'receipt'
    $plan=$fixture.plan;$plan.batch.commit='a'*40;$plan.batch.nativeDigest='b'*64
    $receipt=@{schemaVersion=1;passed=$true;cleanedUp=$true;platform='x64';commit=$plan.batch.commit;nativeDigest=$plan.batch.nativeDigest;
        runId='42';version=$plan.batch.version;manifestDigest='c'*64;aliases=2;probes=3}
    Assert-True (Test-CiWingetInstallReceipt $receipt $plan x64 '42' ('c'*64))
    foreach($change in @(@{aliases=1},@{probes=2},@{probes='3'},@{cleanedUp=$false},@{runId='41'},@{platform='ARM64'})){
        $bad=$receipt.Clone();foreach($key in $change.Keys){$bad[$key]=$change[$key]}
        Assert-Refused {Test-CiWingetInstallReceipt $bad $plan x64 '42' ('c'*64)}
    }
    $bad=$receipt.Clone();$bad.Remove('probes')
    Assert-Refused {Test-CiWingetInstallReceipt $bad $plan x64 '42' ('c'*64)}
}

Invoke-Case 'Manual native admission retains a failed input until explicit retry is supplied' {
    $root=New-Fixture 'manual-admission'
    $candidate=New-CiInputDescriptor $root
    $module=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.GitHub.psm1') -PassThru
    $names=@('Invoke-CiApi','Get-CiMainHead','Read-CiState','Write-CiState','Set-CiQualificationStatus')
    $originals=& $module {param($Names) $saved=@{};foreach($name in $Names){$saved[$name]=(Get-Command $name).ScriptBlock};return $saved} $names
    $oldRepository=$env:GITHUB_REPOSITORY
    try{
        $env:GITHUB_REPOSITORY=$candidate.repository
        & $module {
            param($Candidate)
            $script:admissionCandidate=$Candidate
            $script:admissionWrites=[Collections.Generic.List[object]]::new()
            function script:Invoke-CiApi {
                param($Route,$Method='GET',$Body,[switch]$AllowNotFound)
                return @{path='.github/workflows/qualify.yml';event='workflow_dispatch';head_branch='main';head_sha=$script:admissionCandidate.commit}
            }
            function script:Get-CiMainHead {param($Repository) return $script:admissionCandidate.commit}
            function script:Read-CiState {
                param($Repository)
                return @{head=('d'*40);state=@{repository=$Repository;nativeDigest=$script:admissionCandidate.nativeDigest;runId='41';outcome='failed'}}
            }
            function script:Write-CiState {param($Repository,$State,$ExpectedHead) $script:admissionWrites.Add($State);return ('e'*40)}
            function script:Set-CiQualificationStatus {param($Repository,$Commit,$Status,$Description,$RunId)}
        } $candidate
        $retained=Invoke-CiAdmission -Root $root -Commit $candidate.commit -EngineRef $candidate.engine.ref -RunId '42' -Mode manual
        Assert-Equal $false $retained.admitted
        Assert-Equal 'failed' $retained.decision.outcome
        Assert-Equal 0 (& $module {$script:admissionWrites.Count})
        $retry=Invoke-CiAdmission -Root $root -Commit $candidate.commit -EngineRef $candidate.engine.ref -RunId '42' -Mode manual -Retry
        Assert-Equal $true $retry.admitted
        Assert-Equal 1 (& $module {$script:admissionWrites.Count})
        Assert-Equal '42' $retry.descriptor.runId
    }finally{
        $env:GITHUB_REPOSITORY=$oldRepository
        & $module {param($Saved) foreach($key in $Saved.Keys){Set-Item ("Function:script:"+$key) -Value $Saved[$key]}} $originals
    }
}
Invoke-Case 'winget transport creates one exact manifest PR and reuses it on retry' {
    $root=New-Fixture 'winget-transport'
    $directory=Join-Path $root 'manifests'
    $id='RedSalamanders.RedMonitor'
    foreach($suffix in @('.yaml','.installer.yaml','.locale.en-US.yaml')){
        Write-FixtureFile $root ("manifests/"+$id+$suffix) ("PackageIdentifier: $id"+[char]10+'PackageVersion: 0.1.123'+[char]10+'# Synthetic manifest transport fixture')
    }
    $module=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Winget.psm1') -PassThru
    $publication=Get-Module -All Ci.WingetPublication | Select-Object -First 1
    if(-not $publication){throw 'The nested idempotency module is unavailable.'}
    $oldToken=$env:WINGET_TOKEN
    try{
        $env:WINGET_TOKEN='synthetic-credential-not-a-token'
        & $publication {function script:Start-Sleep {throw 'Mocked transport attempted an unexpected visibility retry.'}}
        & $module {
            param($Directory)
            $script:mockDirectory=$Directory
            $script:mockPr=$null
            $script:mockCreates=0
            $script:mockBlobs=@{}
            $script:mockPaths=@()
            $script:mockBranch=''
            function script:Invoke-RestMethod {
                param($Uri,$Method='GET',$Headers,$TimeoutSec,$ContentType,$Body)
                $route=$Uri.Replace('https://api.github.com/','')
                $bodyData=if($Body){$Body|ConvertFrom-Json -AsHashtable}else{@{}}
                if($route -ceq 'user'){return [pscustomobject]@{login='ci-fixture'}}
                if($route -ceq 'repos/ci-fixture/winget-pkgs'){return @{fork=$true;parent=@{full_name='microsoft/winget-pkgs'}}}
                if($route -ceq 'repos/microsoft/winget-pkgs/git/ref/heads/master'){return @{object=@{sha=('a'*40)}}}
                if($route -like 'repos/microsoft/winget-pkgs/contents/*'){return @()}
                if($route.StartsWith('repos/microsoft/winget-pkgs/pulls?')){if($script:mockPr){return $script:mockPr};return @()}
                if($route -ceq ('repos/microsoft/winget-pkgs/git/commits/'+('a'*40))){return @{tree=@{sha=('b'*40)}}}
                if($route -ceq 'repos/ci-fixture/winget-pkgs/git/blobs'){
                    $sha=[guid]::NewGuid().ToString('N').PadRight(40,'0')
                    $script:mockBlobs[$sha]=$bodyData.content
                    return @{sha=$sha}
                }
                if($route -ceq 'repos/ci-fixture/winget-pkgs/git/trees'){$script:mockPaths=@($bodyData.tree);return @{sha=('c'*40)}}
                if($route -ceq 'repos/ci-fixture/winget-pkgs/git/commits'){return @{sha=('d'*40)}}
                if($route -ceq 'repos/ci-fixture/winget-pkgs/git/refs'){$script:mockBranch=$bodyData.ref.Replace('refs/heads/','');return @{}}
                if($route -ceq 'repos/microsoft/winget-pkgs/pulls' -and $Method -eq 'POST'){
                    ++$script:mockCreates
                    $script:mockPr=[pscustomobject]@{number=123;state='open';title=$bodyData.title;body=$bodyData.body;
                        user=[pscustomobject]@{login='ci-fixture'};head=[pscustomobject]@{ref=$script:mockBranch;sha=('d'*40);repo=[pscustomobject]@{full_name='ci-fixture/winget-pkgs'}};
                        html_url='https://github.com/microsoft/winget-pkgs/pull/123'}
                    return $script:mockPr
                }
                if($route -like 'repos/microsoft/winget-pkgs/pulls/123/files?*'){return @($script:mockPaths|ForEach-Object{[pscustomobject]@{filename=$_.path;status='added'}})}
                if($route -like 'repos/ci-fixture/winget-pkgs/contents/*'){
                    $path=[uri]::UnescapeDataString(($route.Split('?')[0] -replace '^repos/ci-fixture/winget-pkgs/contents/',''))
                    $row=@($script:mockPaths|Where-Object path -ceq $path)
                    if($row.Count -ne 1){throw 'Mock remote manifest lookup differs.'}
                    return @{content=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script:mockBlobs[$row[0].sha]))}
                }
                if($route -ceq 'repos/microsoft/winget-pkgs/pulls/123' -and $Method -eq 'PATCH'){
                    $script:mockPr.title=$bodyData.title;$script:mockPr.body=$bodyData.body;return $script:mockPr
                }
                throw "Unexpected mocked winget route $Method $route"
            }
        } $directory
        $plan=@{project=@{repository='RedSalamanders/RedMonitor';winget=@{identifier=$id}};batch=@{version='0.1.123'};tag='v0.1.123'}
        $first=Submit-CiWinget -Plan $plan -ManifestDirectory $directory
        Assert-Equal 123 $first.PullRequestNumber
        Assert-Equal $true $first.Submitted
        $second=Submit-CiWinget -Plan $plan -ManifestDirectory $directory
        Assert-Equal 123 $second.PullRequestNumber
        Assert-Equal $false $second.Submitted
        Assert-Equal 1 (& $module {$script:mockCreates})
        Write-FixtureFile $root ("manifests/"+$id+'.installer.yaml') ("PackageIdentifier: $id"+[char]10+'PackageVersion: 0.1.123'+[char]10+'InstallerSha256: changed')
        Assert-Refused { Submit-CiWinget -Plan $plan -ManifestDirectory $directory }
        Assert-Equal 1 (& $module {$script:mockCreates})
    }finally{
        $env:WINGET_TOKEN=$oldToken
        & $module {Remove-Item Function:Invoke-RestMethod -ErrorAction SilentlyContinue}
        & $publication {Remove-Item Function:Start-Sleep -ErrorAction SilentlyContinue}
    }
}

if ($IsWindows) {
    Invoke-Case 'Explicit formatting commits use real Git narrow staging and fresh-head dispatch' {
        Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Format.psm1')
        $root=New-Fixture 'manual-format-git'
        Write-FixtureFile $root '.clang-format' 'BasedOnStyle: LLVM'
        Write-FixtureFile $root '.gitignore' '.build/'
        $base=Save-Fixture $root 'Trusted formatter configuration'
        $origin=Join-Path $runRoot 'format-origin.git'
        $null=Invoke-CiGit $root @('init','--bare',$origin)
        $null=Invoke-CiGit $root @('remote','add','origin',$origin)
        $null=Invoke-CiGit $root @('push','origin','main')
        $null=Invoke-CiGit $root @('checkout','-b','ej/format-fixture')
        foreach($file in @('src/witness [1].cpp','src/witness [2].cpp')){
            Write-FixtureFile $root $file ('int Fixture(){return 7;}'+[char]10)
        }
        $head=Save-Fixture $root 'Unformatted PR source'
        $null=Invoke-CiGit $root @('push','origin','HEAD:refs/heads/ej/format-fixture')
        $null=Invoke-CiGit $root @('checkout','main')
        $module=Get-Module Ci.Format
        $original=& $module {(Get-Command Invoke-CiApi).ScriptBlock}
        $names=@('GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_REPOSITORY')
        $saved=@{}
        foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name)}
        try{
            $env:GITHUB_EVENT_NAME='workflow_dispatch';$env:GITHUB_REF='refs/heads/main'
            $env:GITHUB_REPOSITORY='RedSalamanders/RedMonitor'
            & $module {
                param($Origin,$Base,$Head)
                $script:formatOrigin=$Origin;$script:formatBase=$Base;$script:formatHead=$Head
                $script:formatDispatches=[Collections.Generic.List[object]]::new()
                $script:formatFork=$false;$script:formatLagServed=$false
                function script:Invoke-CiApi {
                    param($Route,$Method='GET',$Body)
                    if($Route -like '*/pulls/123'){
                        $sha=(Invoke-CiGit $script:formatOrigin @('rev-parse','refs/heads/ej/format-fixture')).stdout.Trim()
                        if($sha -cne $script:formatHead -and -not $script:formatLagServed){$sha=$script:formatHead;$script:formatLagServed=$true}
                        $repo=if($script:formatFork){'fixture/fork'}else{'RedSalamanders/RedMonitor'}
                        return @{state='open';head=@{repo=@{full_name=$repo};sha=$sha;ref='ej/format-fixture'};base=@{sha=$script:formatBase;ref='main'}}
                    }
                    if($Route.EndsWith('/actions/workflows/ci.yml/dispatches') -and $Method -ceq 'POST'){
                        $script:formatDispatches.Add($Body);return @{}
                    }
                    throw "Unexpected formatter API route: $Method $Route"
                }
            } $origin $base $head
            Invoke-CiFormatCommit -Root $root -Repository $env:GITHUB_REPOSITORY -PullRequest 123
            $formatted=(Invoke-CiGit $origin @('rev-parse','refs/heads/ej/format-fixture')).stdout.Trim()
            Assert-True ($formatted -cne $head)
            $changed=(Invoke-CiGit $root @('diff','--name-only',$head,$formatted)).stdout.Trim() -split [char]10
            Assert-Equal 'src/witness [1].cpp|src/witness [2].cpp' (($changed|Sort-Object)-join '|')
            $dispatches=@(& $module {$script:formatDispatches.ToArray()})
            Assert-Equal 1 @($dispatches).Count
            Assert-Equal $formatted $dispatches[0].inputs.expected_head
            Assert-Equal 'main' $dispatches[0].ref
            Assert-Equal $false (Invoke-CiFormatting $root $base).drift
            Invoke-CiFormatCommit -Root $root -Repository $env:GITHUB_REPOSITORY -PullRequest 123
            Assert-Equal 1 (& $module {$script:formatDispatches.Count})
            & $module {$script:formatFork=$true}
            Assert-Refused {Invoke-CiFormatCommit -Root $root -Repository $env:GITHUB_REPOSITORY -PullRequest 123}
            Assert-Equal $formatted (Invoke-CiGit $origin @('rev-parse','refs/heads/ej/format-fixture')).stdout.Trim()
        }finally{
            foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name])}
            & $module {param($Original) Set-Item Function:script:Invoke-CiApi -Value $Original} $original
        }
    }
}

Invoke-Case 'Production SDK receipts expose distinct real artifact and receipt outputs' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Project.psm1')
    $root=New-Fixture 'sdk-production-outputs'
    $project=Read-CiProject $root
    $project.repository='RedSalamanders/DxUi';$project.kind='sdk';$project.winget=$null
    Write-FixtureFile $root '.ci/project.json' ($project|ConvertTo-Json -Depth 8)
    Write-FixtureFile $root '.gitignore' '.build/'
    $null=Save-Fixture $root 'SDK fixture'
    $context=@{root=$root;project=$project;platform='x64';batch=(New-CiInputDescriptor $root)}
    $archive=Join-Path $root '.build/sdk/fixture.zip'
    [void][IO.Directory]::CreateDirectory((Split-Path $archive))
    $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
    try{$null=$zip.CreateEntry('include/Fixture.h')}finally{$zip.Dispose()}
    $oldOutput=$env:GITHUB_OUTPUT;$oldRun=$env:GITHUB_RUN_ID
    try{
        $env:GITHUB_OUTPUT=Join-Path $root '.build/production-outputs.txt';$env:GITHUB_RUN_ID='654'
        Write-CiProductionReceipt -Context $context -Archives @($archive) -TestModeDisabled $true -SmokePassed $true
        $lines=@(Get-Content -LiteralPath $env:GITHUB_OUTPUT)
        Assert-Equal 2 $lines.Count
        $values=@{}
        foreach($line in $lines){$key,$value=$line -split '=',2;$values[$key]=$value}
        Assert-True (Test-Path -LiteralPath $values.receipt_path -PathType Leaf)
        Assert-True (Test-Path -LiteralPath $values.archive_directory -PathType Container)
        $receipt=Get-Content -LiteralPath $values.receipt_path -Raw|ConvertFrom-Json
        Assert-Equal 1 @($receipt.archives).Count
        Assert-Equal (Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant() $receipt.archives[0].sha256
        Assert-True (Test-Path -LiteralPath (Join-Path $values.archive_directory $receipt.archives[0].file))
    }finally{$env:GITHUB_OUTPUT=$oldOutput;$env:GITHUB_RUN_ID=$oldRun}
}

Invoke-Case 'Prepare command exports distinct version and directory without release mutation' {
    $root=New-Fixture 'prepare-command-outputs'
    $module=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Publication.psm1') -PassThru
    $original=& $module {(Get-Command Get-CiPublicationPlan).ScriptBlock}
    $names=@('GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_RUN_ID','GITHUB_OUTPUT')
    $saved=@{}
    foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name)}
    try{
        $env:GITHUB_EVENT_NAME='workflow_dispatch';$env:GITHUB_REF='refs/heads/main';$env:GITHUB_RUN_ID='987'
        $env:GITHUB_OUTPUT=Join-Path $root 'prepare-output.txt'
        & $module {
            function script:Get-CiPublicationPlan {
                param($Root,$RunId,$EngineRef,$Directory)
                [void][IO.Directory]::CreateDirectory($Directory)
                return @{directory=$Directory;project=(Read-CiProject $Root);batch=@{version='0.1.234'}}
            }
        }
        & (Join-Path $engineRoot 'Tools/Invoke-Publication.ps1') -Root $root -RunId 234 -EngineRef ('a'*40) -Operation Prepare
        $lines=@(Get-Content -LiteralPath $env:GITHUB_OUTPUT)
        Assert-Equal 2 $lines.Count
        $values=@{}
        foreach($line in $lines){$key,$value=$line -split '=',2;$values[$key]=$value}
        Assert-Equal '0.1.234' $values.version
        Assert-True (Test-Path -LiteralPath (Join-Path $values.directory 'publication.json'))
    }finally{
        foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name])}
        & $module {param($Original) Set-Item Function:script:Get-CiPublicationPlan -Value $Original} $original
    }
}

Invoke-Case 'Manual bot-push rechecks bind all three required checks to the exact new PR head' {
    $root=New-Fixture 'manual-security-reporting'
    $module=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.GitHub.psm1') -PassThru
    $original=& $module {(Get-Command Invoke-CiApi).ScriptBlock}
    $names=@('GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_REPOSITORY','GITHUB_RUN_ID','GITHUB_OUTPUT')
    $saved=@{}
    foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name)}
    try{
        $env:GITHUB_EVENT_NAME='workflow_dispatch';$env:GITHUB_REF='refs/heads/main'
        $env:GITHUB_REPOSITORY='RedSalamanders/RedMonitor';$env:GITHUB_RUN_ID='777'
        $env:GITHUB_OUTPUT=Join-Path $root 'check-outputs.txt'
        & $module {
            $script:recheckRecords=[Collections.Generic.List[object]]::new()
            $script:recheckPatches=[Collections.Generic.List[object]]::new()
            function script:Invoke-CiApi {
                param($Route,$Method='GET',$Body,[switch]$AllowNotFound)
                if($Route -like '*/pulls/123'){return @{state='open';head=@{repo=@{full_name='RedSalamanders/RedMonitor'};sha=('a'*40)};base=@{ref='main';sha=('b'*40)}}}
                if($Route.EndsWith('/check-runs') -and $Method -ceq 'POST'){
                    $record=@{id=([string](101+$script:recheckRecords.Count));name=$Body.name;head_sha=$Body.head_sha;external_id=$Body.external_id}
                    $script:recheckRecords.Add($record);return $record
                }
                if($Route -match '/check-runs/([0-9]+)$'){
                    $id=$Matches[1]
                    if($Method -ceq 'GET'){return @($script:recheckRecords|Where-Object id -ceq $id)[0]}
                    if($Method -ceq 'PATCH'){$script:recheckPatches.Add(@{id=$id;body=$Body});return @{}}
                }
                throw "Unexpected recheck fixture route: $Method $Route"
            }
        }
        & (Join-Path $engineRoot 'Tools/Resolve-PrCheck.ps1') -PullRequest 123 -ExpectedHead ('a'*40)
        $records=& $module {$script:recheckRecords.ToArray()}
        Assert-Equal 3 @($records).Count
        Assert-Equal 'checks / ci-gate|security / codeql|security / dependency-review' (($records.name|Sort-Object)-join '|')
        Assert-True (@($records|Where-Object head_sha -cne ('a'*40)).Count -eq 0)
        $command=Join-Path $engineRoot 'Tools/Complete-PrCheck.ps1'
        & $command -CheckId '101' -Kind CI -Result success
        Assert-Refused {& $command -CheckId '102' -Kind CodeQL -Result skipped}
        Assert-Refused {& $command -CheckId '103' -Kind Dependency -Result cancelled}
        $patches=& $module {$script:recheckPatches.ToArray()}
        Assert-Equal 'success|failure|cancelled' (($patches|ForEach-Object {$_.body.conclusion})-join '|')
        Assert-Refused {& $command -CheckId '102' -Kind CI -Result success}
        Assert-Equal 3 (& $module {$script:recheckPatches.Count})
        Assert-Refused {& (Join-Path $engineRoot 'Tools/Resolve-PrCheck.ps1') -PullRequest 123 -ExpectedHead ('c'*40)}
        Assert-Equal 3 (& $module {$script:recheckRecords.Count})
        $outputs=[IO.File]::ReadAllText($env:GITHUB_OUTPUT)
        Assert-True ($outputs.Contains('codeql_id=102') -and $outputs.Contains('dependency_id=103'))
    }finally{
        foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name])}
        & $module {param($Original) Set-Item Function:script:Invoke-CiApi -Value $Original} $original
    }
}

Invoke-Case 'Native architecture checks refuse emulated, malformed and truncated images' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Project.psm1')
    $root=New-Fixture 'native-pe'
    $file=Join-Path $root 'native.exe'
    foreach($profile in @(@{platform='x64';machine=0x8664},@{platform='ARM64';machine=0xaa64})){
        $bytes=[byte[]]::new(256)
        [BitConverter]::GetBytes([uint16]0x5a4d).CopyTo($bytes,0)
        [BitConverter]::GetBytes([uint32]128).CopyTo($bytes,0x3c)
        [BitConverter]::GetBytes([uint32]0x00004550).CopyTo($bytes,128)
        [BitConverter]::GetBytes([uint16]$profile.machine).CopyTo($bytes,132)
        [IO.File]::WriteAllBytes($file,$bytes)
        Assert-CiPeArchitecture $file $profile.platform
        $other=if($profile.platform -ceq 'x64'){'ARM64'}else{'x64'}
        Assert-Refused {Assert-CiPeArchitecture $file $other}
    }
    [IO.File]::WriteAllBytes($file,[byte[]]::new(3))
    Assert-Refused {Assert-CiPeArchitecture $file ARM64}
    $bytes[0]=0
    [IO.File]::WriteAllBytes($file,$bytes)
    Assert-Refused {Assert-CiPeArchitecture $file ARM64}
    $bytes[0]=0x4d
    [BitConverter]::GetBytes([uint32]255).CopyTo($bytes,0x3c)
    [IO.File]::WriteAllBytes($file,$bytes)
    Assert-Refused {Assert-CiPeArchitecture $file ARM64}
}

Invoke-Case 'Workflow conformance refuses a native PR route, pin drift and unreviewed timers' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Project.psm1')
    $root=New-Fixture 'workflow-conformance'
    $project=Read-CiProject $root
    Write-FixtureFile $root 'Tools/Invoke-ProjectCi.ps1' '# Fixture adapter; no source execution.'
    foreach($template in Get-ChildItem (Join-Path $engineRoot 'Templates') -Filter '*.yml'){
        $text=[IO.File]::ReadAllText($template.FullName).Replace('@ENGINE@',$project.engine.ref).Replace('@OPERATIONS@','Prepare, Release, Winget')
        Write-FixtureFile $root ('.github/workflows/'+$template.Name) $text
    }
    $context=@{root=$root;engineRoot=$engineRoot;project=$project;development=$false}
    Test-CiProjectConfiguration $context
    $path=Join-Path $root '.github/workflows/ci.yml'
    $original=[IO.File]::ReadAllText($path)
    Write-FixtureFile $root '.github/workflows/ci.yml' ($original+([char]10)+'  native:'+([char]10)+'    runs-on: windows-latest'+([char]10)+'    steps:'+([char]10)+'      - run: ./build.ps1')
    Assert-Refused { Test-CiProjectConfiguration $context }
    # A change to the workflow's source/pin must be detected even if it remains valid YAML.
    Write-FixtureFile $root '.github/workflows/ci.yml' ($original.Replace($project.engine.ref,('b'*40)))
    Assert-Refused { Test-CiProjectConfiguration $context }
    Write-FixtureFile $root '.github/workflows/ci.yml' $original
    Write-FixtureFile $root '.github/workflows/nightly.yml' ('on:'+([char]10)+'  schedule:'+([char]10)+'    - cron: "* * * * *"')
    Assert-Refused { Test-CiProjectConfiguration $context }
}
Invoke-Case 'SDK conformance retains qualification and rejects every hosted publication route' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Project.psm1')
    $root=New-Fixture 'sdk-no-publication'
    $project=Read-CiProject $root
    $project.repository='RedSalamanders/DxUi';$project.kind='sdk';$project.winget=$null
    Write-FixtureFile $root '.ci/project.json' ($project|ConvertTo-Json -Depth 12)
    Write-FixtureFile $root 'Tools/Invoke-ProjectCi.ps1' '# Fixture adapter.'
    foreach($template in Get-CiProjectWorkflowTemplates $project){
        Write-FixtureFile $root ('.github/workflows/'+$template.Name) ([IO.File]::ReadAllText($template.FullName).Replace('@ENGINE@',$project.engine.ref))
    }
    $context=@{root=$root;engineRoot=$engineRoot;project=$project;development=$false}
    Test-CiProjectConfiguration $context
    Assert-True (Test-Path -LiteralPath (Join-Path $root '.github/workflows/qualify.yml'))
    Assert-Equal 5 @(Get-CiProjectWorkflowTemplates $project).Count
    Write-FixtureFile $root '.github/workflows/publish.yml' 'on: workflow_dispatch'
    Assert-Refused {Test-CiProjectConfiguration $context}
    Remove-Item -LiteralPath (Join-Path $root '.github/workflows/publish.yml')
    foreach($name in @('gallery.yml','release.yml')){
        Write-FixtureFile $root ('.github/workflows/'+$name) 'on: workflow_dispatch'
        Assert-Refused {Test-CiProjectConfiguration $context}
        Remove-Item -LiteralPath (Join-Path $root ('.github/workflows/'+$name))
    }
}
Invoke-Case 'SDK publication APIs refuse before downloads, remote calls or output creation' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Publication.psm1')
    $root=New-Fixture 'sdk-publication-refusal'
    $project=Read-CiProject $root
    $project.repository='RedSalamanders/DxUi';$project.kind='sdk';$project.winget=$null
    Write-FixtureFile $root '.ci/project.json' ($project|ConvertTo-Json -Depth 12)
    $directory=Join-Path $root 'must-not-exist'
    $plan=@{project=$project}
    foreach($operation in @(
        {Get-CiPublicationPlan -Root $root -RunId 42 -EngineRef $project.engine.ref -Directory $directory},
        {Publish-CiGitHubRelease -Plan $plan},
        {Assert-CiPublicationCurrent -Root $root -Plan $plan}
    )){
        $message=''
        try{& $operation|Out-Null}catch{$message=$_.Exception.Message}
        Assert-Equal 'SDK ZIPs remain internal qualification artifacts; publication is disabled.' $message
    }
    Assert-True (-not(Test-Path -LiteralPath $directory))
}
Invoke-Case 'Pin migration removes only the generated SDK publisher and preserves custom changes' {
    # Exercise the real maintenance command from a clean engine fixture, not a mocked file writer.
    $fixtureEngine=New-Fixture 'pin-migration-engine'
    foreach($path in @('Tools/Update-ProjectPin.ps1','Tools/Modules/Ci.Policy.psm1','Schemas/project.schema.json')){
        Write-FixtureFile $fixtureEngine $path ([IO.File]::ReadAllText((Join-Path $engineRoot $path)))
    }
    foreach($template in Get-ChildItem (Join-Path $engineRoot 'Templates') -File){
        Write-FixtureFile $fixtureEngine ('Templates/'+$template.Name) ([IO.File]::ReadAllText($template.FullName))
    }
    $engineCommit=Save-Fixture $fixtureEngine 'Clean maintenance engine'
    $hostPath=(Get-Process -Id $PID).Path
    foreach($kind in @('application','sdk','custom-sdk')){
        $root=New-Fixture ('pin-migration-'+$kind)
        $project=Read-CiProject $root
        if($kind -cne 'application'){$project.repository='RedSalamanders/DxUi';$project.kind='sdk';$project.winget=$null}
        Write-FixtureFile $root '.ci/project.json' ($project|ConvertTo-Json -Depth 12)
        $operations=if($kind -ceq 'application'){'Prepare, Release, Winget'}else{'Prepare, Release'}
        $oldCaller=[IO.File]::ReadAllText((Join-Path $engineRoot 'Templates/publish.yml')).Replace('@ENGINE@',$project.engine.ref).Replace('@OPERATIONS@',$operations)
        if($kind -ceq 'custom-sdk'){$oldCaller+=([string][char]10+'# Preserve this custom workflow for review.')}
        Write-FixtureFile $root '.github/workflows/publish.yml' $oldCaller
        $oldManifest=[IO.File]::ReadAllText((Join-Path $root '.ci/project.json'))
        $result=Invoke-CiProcess $hostPath @('-NoProfile','-NonInteractive','-File',(Join-Path $fixtureEngine 'Tools/Update-ProjectPin.ps1'),'-Root',$root,'-EngineRef',$engineCommit) $root -TimeoutSeconds 120 -AllowFailure
        if($kind -ceq 'custom-sdk'){
            Assert-True ($result.exitCode -ne 0 -and $result.stderr.Contains('custom changes'))
            Assert-Equal $oldManifest ([IO.File]::ReadAllText((Join-Path $root '.ci/project.json')))
            Assert-Equal $oldCaller ([IO.File]::ReadAllText((Join-Path $root '.github/workflows/publish.yml')))
            Assert-True (-not(Test-Path -LiteralPath (Join-Path $root '.github/workflows/qualify.yml')))
        }else{
            Assert-Equal 0 $result.exitCode
            Assert-Equal $engineCommit (Read-CiProject $root).engine.ref
            Assert-Equal ($kind -ceq 'application') (Test-Path -LiteralPath (Join-Path $root '.github/workflows/publish.yml'))
            Assert-True (Test-Path -LiteralPath (Join-Path $root '.github/workflows/qualify.yml'))
        }
    }
}
Invoke-Case 'Queue compatibility validates the official value and noncancellation rules' {
    $lf=[string][char]10
    Assert-True (Test-CiWorkflowQueues ("concurrency:"+$lf+"  group: native"+$lf+"  cancel-in-progress: false"+$lf+"  queue: max"))
    Assert-True (Test-CiWorkflowQueues ("jobs:"+$lf+"  native:"+$lf+"    concurrency:"+$lf+"      group: one"+$lf+"      queue: max"))
    Assert-Refused { Test-CiWorkflowQueues ("concurrency:"+$lf+"  queue: unlimited") }
    Assert-Refused { Test-CiWorkflowQueues ("concurrency:"+$lf+"  queue: max"+$lf+"  cancel-in-progress: true") }
    Assert-Refused { Test-CiWorkflowQueues ("jobs:"+$lf+"  queue: max") }
}

$failed = @($script:rows | Where-Object { -not $_.passed }).Count
$summary = [ordered]@{ schemaVersion = 1; passed = $failed -eq 0; executed = $script:rows.Count; failed = $failed; cases = $script:rows.ToArray() }
$resultPath = Join-Path $runRoot 'results.json'
[IO.File]::WriteAllText($resultPath, ($summary | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
Write-Host "Engine results: $resultPath"
if ($failed) { throw "$failed engine behavior case(s) failed; preserve $runRoot." }
