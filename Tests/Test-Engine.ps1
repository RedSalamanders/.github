<#
.SYNOPSIS
Runs deterministic behavioral CI-policy tests in owned Git fixtures without native compilation.
.PARAMETER TestRoot
Existing marked RedSalamander.Perf sandbox, or a hosted RUNNER_TEMP child. Creates a unique child only.
.OUTPUTS
Case results and retained results.json beneath the selected root.
.NOTES
Requires PowerShell 7.4 and Git. No credentials, network, compiler or desktop input.
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
        $script:rows.Add([ordered]@{ name = $Name; passed = $false; error = $_.Exception.Message; elapsedMs = $timer.ElapsedMilliseconds })
        Write-Host "FAIL $Name : $($_.Exception.Message)" -ForegroundColor Red
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
    $descriptor = @{ repository = 'RedSalamanders/RedMonitor'; commit = ('a' * 40); nativeDigest = ('b' * 64) }
    $valid = @{ schemaVersion = 1; repository = $descriptor.repository; commit = $descriptor.commit; nativeDigest = $descriptor.nativeDigest;
        platform = 'x64'; role = 'ReleaseTest'; passed = $true; discovered = 12; executed = 12; failed = 0; unexpectedSkipped = 0;
        assertionProbePassed = $true; artifacts = @(@{ path = 'MonitorTest.exe'; sha256 = ('c' * 64) }) }
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
Invoke-Case 'Streaming child execution preserves a real nonzero exit code' {
    $root = New-Fixture 'streaming-exit'
    $hostPath = (Get-Process -Id $PID).Path
    $result = Invoke-CiProcess -FilePath $hostPath -Arguments @('-NoProfile','-NonInteractive','-Command','exit 17') -WorkingDirectory $root -Stream -AllowFailure
    Assert-Equal 17 $result.exitCode
}

$failed = @($script:rows | Where-Object { -not $_.passed }).Count
$summary = [ordered]@{ schemaVersion = 1; passed = $failed -eq 0; executed = $script:rows.Count; failed = $failed; cases = $script:rows.ToArray() }
$resultPath = Join-Path $runRoot 'results.json'
[IO.File]::WriteAllText($resultPath, ($summary | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
Write-Host "Engine results: $resultPath"
if ($failed) { throw "$failed engine behavior case(s) failed; preserve $runRoot." }
