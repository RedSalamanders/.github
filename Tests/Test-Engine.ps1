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
        exclude = @('README.md','AGENTS.md','CLAUDE.md','CHANGELOG.md','Specs/**/*.md','docs/**','Specs/Plans/**','Changes/**'); formatRoots = @('src');
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
Invoke-Case 'Current conformance refuses extension-wide Markdown exclusions without invalidating historical manifest reads' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Project.psm1')
    $root=New-Fixture 'markdown-conformance'
    $project=Read-CiProject $root
    $project.exclude=@('**/*.md','docs/**')
    Write-FixtureFile $root '.ci/project.json' ($project|ConvertTo-Json -Depth 8)
    $legacy=Save-Fixture $root 'Historical broad exclusion'
    Assert-Equal '**/*.md' (Read-CiProject $root -Ref $legacy).exclude[0]
    foreach($pattern in @('**/*.md','**/*.MD','*.md','**.md','*/*.md')){
        $project.exclude=@($pattern)
        $message=''
        try{Test-CiProjectConfiguration @{root=$root;project=$project;development=$false}}catch{$message=$_.Exception.Message}
        Assert-True ($message.Contains('extension-wide exclusion')) "Unexpected conformance result: $message"
    }
}
Invoke-Case 'Compiler-free planner command is restricted to the reviewed DxUi adapter and preserves nonzero exits' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Project.psm1')
    $root=New-Fixture 'compiler-free-planner'
    $script='Tools/tests/Test-ScopedTesting.ps1'
    Write-FixtureFile $root $script 'Write-Output "recording planner control, no compiler"; exit 0'
    Write-FixtureFile $root 'build.ps1' 'throw "A native build must never be invoked."'
    $context=@{root=$root;phase='Static';project=@{repository='RedSalamanders/RedMonitor'}}
    Assert-Refused {Invoke-CiProjectScript $context $script -TimeoutSeconds 30}
    $context.project.repository='RedSalamanders/DxUi'
    Invoke-CiProjectScript $context $script -TimeoutSeconds 30
    Assert-Refused {Invoke-CiProjectScript $context 'build.ps1' -TimeoutSeconds 30}
    Write-FixtureFile $root $script 'exit 23'
    Assert-Refused {Invoke-CiProjectScript $context $script -TimeoutSeconds 30}
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
Invoke-Case 'Manual qualification selects only the requested architectures before native setup' {
    $root = New-Fixture 'qualification-platforms'
    $workflow = [IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/qualification.yml'))
    $job = [regex]::Match($workflow, '(?ms)^  select-platforms:\r?\n(?<job>.*?)^  native:\r?\n')
    Assert-True $job.Success 'The qualification selector job is missing.'
    $inline = [regex]::Match($job.Groups['job'].Value, '(?ms)^        run: \|\r?\n(?<body>(?:          [^\r\n]*\r?\n)+)')
    Assert-True $inline.Success 'The actual qualification selector script is missing.'
    $scriptText = [regex]::Replace($inline.Groups['body'].Value, '(?m)^          ', '')
    Write-FixtureFile $root 'select-platforms.ps1' $scriptText
    $hostPath = (Get-Process -Id $PID).Path
    $oldPlatform = $env:CI_QUALIFICATION_PLATFORM
    $oldOutput = $env:GITHUB_OUTPUT
    try {
        foreach ($selection in @('All', 'x64', 'ARM64')) {
            $env:CI_QUALIFICATION_PLATFORM = $selection
            $env:GITHUB_OUTPUT = Join-Path $root ($selection + '.output')
            $result = Invoke-CiProcess -FilePath $hostPath -Arguments @('-NoProfile', '-NonInteractive', '-File', (Join-Path $root 'select-platforms.ps1')) -WorkingDirectory $root
            Assert-Equal 0 $result.exitCode
            $lines = @([IO.File]::ReadAllLines($env:GITHUB_OUTPUT))
            Assert-Equal 1 $lines.Count
            Assert-True ($lines[0].StartsWith('matrix=', [StringComparison]::Ordinal))
            $matrix = $lines[0].Substring(7) | ConvertFrom-Json -AsHashtable
            $expected = @(if ($selection -ceq 'All') { 'x64'; 'ARM64' } else { $selection })
            Assert-Equal $expected.Count @($matrix.include).Count
            for ($index = 0; $index -lt $expected.Count; ++$index) {
                Assert-Equal $expected[$index] $matrix.include[$index].platform
                $runner = if ($expected[$index] -ceq 'x64') { 'windows-2025-vs2026' } else { 'windows-11-vs2026-arm' }
                Assert-Equal $runner $matrix.include[$index].runner
            }
        }
        $index = 0
        foreach ($selection in @('', 'all', 'X64', 'x64,ARM64', 'x64;throw "input executed"')) {
            $env:CI_QUALIFICATION_PLATFORM = $selection
            $env:GITHUB_OUTPUT = Join-Path $root ("invalid-$index.output")
            $result = Invoke-CiProcess -FilePath $hostPath -Arguments @('-NoProfile', '-NonInteractive', '-File', (Join-Path $root 'select-platforms.ps1')) -WorkingDirectory $root -AllowFailure
            Assert-True ($result.exitCode -ne 0) "Invalid platform '$selection' was admitted."
            Assert-True (-not (Test-Path -LiteralPath $env:GITHUB_OUTPUT)) 'A refused selector must not publish a native matrix.'
            ++$index
        }
    } finally {
        $env:CI_QUALIFICATION_PLATFORM = $oldPlatform
        $env:GITHUB_OUTPUT = $oldOutput
    }
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
Invoke-Case 'winget manifests carry schema headers, use the ZIP nested executable and reject SDK, missing licensing and unsafe paths' {
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
    foreach($manifest in @(@('','version'),@('.installer','installer'),@('.locale.en-US','defaultLocale'))){
        $lines=[IO.File]::ReadAllLines((Join-Path $directory "RedSalamanders.RedMonitor$($manifest[0]).yaml"))
        Assert-Equal ('# yaml-language-server: $schema=https://aka.ms/winget-manifest.'+$manifest[1]+'.1.12.0.schema.json') $lines[0]
        Assert-Equal ('ManifestType: '+$manifest[1]) @($lines|Where-Object {$_.StartsWith('ManifestType: ')})[0]
    }
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
            if($CommandArguments[0] -eq 'validate' -and $fixture.mode -eq 'validate-warning'){$exitCode=-1978335192}
            if($CommandArguments[0] -eq 'validate' -and $fixture.mode -eq 'validate-failure'){$exitCode=1}
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
Invoke-Case 'winget validation warnings are accepted and logged, while other validation failures refuse before install' {
    $fixture=New-InstallFixture 'validate-warning';$fixture.mode='validate-warning'
    $proof=Run-InstallFixture $fixture
    Assert-True ($proof.passed -and $proof.cleanedUp -and -not $fixture.installed)
    Assert-Equal 'fixture output' ([IO.File]::ReadAllText((Join-Path $fixture.root 'validate.log')))
    Assert-Equal 1 @($fixture.calls|Where-Object{$_.arguments[0] -eq '--version'}).Count
    $fixture=New-InstallFixture 'validate-failure';$fixture.mode='validate-failure'
    Assert-Refused {Run-InstallFixture $fixture}
    Assert-Equal 0 @($fixture.calls|Where-Object{$_.arguments[0] -in 'install','uninstall'}).Count
    Assert-Equal 'fixture output' ([IO.File]::ReadAllText((Join-Path $fixture.root 'validate.log')))
}
Invoke-Case 'winget resolution registers the inbox App Installer only when its alias is absent, and refuses when it stays absent' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.WingetInstall.psm1')
    $root=New-Fixture 'winget-resolution'
    $state=@{path='winget-present';registrations=0;exitCode=0;appears=$true}
    $find={$state.path}.GetNewClosure()
    $register={
        param($Directory)
        $state.registrations++
        if($state.appears){$state.path='winget-registered'}
        return @{exitCode=$state.exitCode;stdout='registration output';stderr=''}
    }.GetNewClosure()
    Assert-Equal 'winget-present' (Resolve-CiWinget -Scratch $root -Find $find -Register $register -WaitSeconds 0)
    Assert-Equal 0 $state.registrations
    $state.path=$null
    Assert-Equal 'winget-registered' (Resolve-CiWinget -Scratch $root -Find $find -Register $register -WaitSeconds 0)
    Assert-Equal 1 $state.registrations
    Assert-Equal 'registration output' ([IO.File]::ReadAllText((Join-Path $root 'appinstaller-register.log')))
    foreach($change in @(@{exitCode=1;appears=$false},@{exitCode=0;appears=$false})){
        $state.path=$null;foreach($key in $change.Keys){$state[$key]=$change[$key]}
        Assert-Refused {Resolve-CiWinget -Scratch $root -Find $find -Register $register -WaitSeconds 0}
    }
    Assert-Equal 3 $state.registrations
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
    $context.batch.runId='654'
    $archive=Join-Path $root '.build/sdk/fixture.zip'
    [void][IO.Directory]::CreateDirectory((Split-Path $archive))
    $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
    try{$null=$zip.CreateEntry('include/Fixture.h')}finally{$zip.Dispose()}
    $oldOutput=$env:GITHUB_OUTPUT;$oldRun=$env:GITHUB_RUN_ID;$oldAttempt=$env:GITHUB_RUN_ATTEMPT
    try{
        $env:GITHUB_OUTPUT=Join-Path $root '.build/production-outputs.txt';$env:GITHUB_RUN_ID='654';$env:GITHUB_RUN_ATTEMPT='2'
        Write-CiProductionReceipt -Context $context -Archives @($archive) -TestModeDisabled $true -SmokePassed $true
        $lines=@(Get-Content -LiteralPath $env:GITHUB_OUTPUT)
        Assert-Equal 2 $lines.Count
        $values=@{}
        foreach($line in $lines){$key,$value=$line -split '=',2;$values[$key]=$value}
        Assert-True (Test-Path -LiteralPath $values.receipt_path -PathType Leaf)
        Assert-True (Test-Path -LiteralPath $values.archive_directory -PathType Container)
        $receipt=Get-Content -LiteralPath $values.receipt_path -Raw|ConvertFrom-Json
        Assert-Equal 1 $receipt.executionBindingVersion
        Assert-Equal 2 $receipt.runAttempt
        Assert-Equal $context.batch.engine.ref $receipt.engine.ref
        Assert-Equal 1 @($receipt.archives).Count
        Assert-Equal (Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant() $receipt.archives[0].sha256
        Assert-True (Test-Path -LiteralPath (Join-Path $values.archive_directory $receipt.archives[0].file))
    }finally{$env:GITHUB_OUTPUT=$oldOutput;$env:GITHUB_RUN_ID=$oldRun;$env:GITHUB_RUN_ATTEMPT=$oldAttempt}
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
    foreach($template in Get-CiProjectWorkflowTemplates $project){
        $text=[IO.File]::ReadAllText($template.FullName).Replace('@ENGINE@',$project.engine.ref).Replace('@OPERATIONS@','Prepare, Release, Winget')
        Write-FixtureFile $root ('.github/workflows/'+$template.Name) $text
    }
    $context=@{root=$root;engineRoot=$engineRoot;project=$project;development=$false}
    Test-CiProjectConfiguration $context
    Write-FixtureFile $root '.github/workflows/sdk-inputs.yml' ([IO.File]::ReadAllText((Join-Path $engineRoot 'Templates/sdk-inputs.yml')).Replace('@ENGINE@',$project.engine.ref))
    Assert-Refused {Test-CiProjectConfiguration $context}
    Remove-Item -LiteralPath (Join-Path $root '.github/workflows/sdk-inputs.yml')
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
    Assert-Equal 7 @(Get-CiProjectWorkflowTemplates $project).Count
    Assert-True (Test-Path -LiteralPath (Join-Path $root '.github/workflows/sdk-inputs.yml'))
    Assert-True (Test-Path -LiteralPath (Join-Path $root '.github/workflows/integration-execution.yml'))
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
        $project.exclude=@('**/*.md','docs/**','Specs/Plans/**','Changes/**')
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
            $migrated=Read-CiProject $root
            Assert-True ('**/*.md' -cnotin $migrated.exclude)
            foreach($path in @('Tests/Data/README.md','src/resource.md','Unknown/native.md')){Assert-True (Get-CiPathDisposition $path $migrated).native}
            Assert-True (-not (Get-CiPathDisposition 'README.md' $migrated).native)
            Assert-Equal ($kind -ceq 'application') (Test-Path -LiteralPath (Join-Path $root '.github/workflows/publish.yml'))
            Assert-True (Test-Path -LiteralPath (Join-Path $root '.github/workflows/qualify.yml'))
        }
    }
    $root=New-Fixture 'pin-migration-untracked-engine'
    $originalCi=[IO.File]::ReadAllText((Join-Path $engineRoot 'Templates/ci.yml')).Replace('@ENGINE@',('a'*40))
    Write-FixtureFile $root '.github/workflows/ci.yml' $originalCi
    $oldManifest=[IO.File]::ReadAllText((Join-Path $root '.ci/project.json'))
    Write-FixtureFile $fixtureEngine 'Templates/unreviewed.yml' 'name: unreviewed'
    $result=Invoke-CiProcess $hostPath @('-NoProfile','-NonInteractive','-File',(Join-Path $fixtureEngine 'Tools/Update-ProjectPin.ps1'),'-Root',$root,'-EngineRef',$engineCommit) $root -TimeoutSeconds 120 -AllowFailure
    Write-FixtureFile $runRoot 'untracked-template-refusal-result.json' ($result|ConvertTo-Json -Depth 6)
    $plainError=[regex]::Replace($result.stderr,'\x1B\[[0-?]*[ -/]*[@-~]','') -replace '(?m)^\s*\|\s*','' -replace '\s+',' '
    Assert-True ($result.exitCode -ne 0 -and $plainError.Contains('mutable development checkout')) ("Untracked engine did not refuse before mutation: "+$result.stderr)
    Assert-Equal $oldManifest ([IO.File]::ReadAllText((Join-Path $root '.ci/project.json')))
    Assert-Equal $originalCi ([IO.File]::ReadAllText((Join-Path $root '.github/workflows/ci.yml')))
    Assert-True (-not(Test-Path -LiteralPath (Join-Path $root '.github/workflows/qualify.yml')))
    # An ignored untracked template is not a committed workflow input and is never executed/copied.
    Write-FixtureFile $fixtureEngine '.git/info/exclude' "Templates/unreviewed.yml`n"
    $result=Invoke-CiProcess $hostPath @('-NoProfile','-NonInteractive','-File',(Join-Path $fixtureEngine 'Tools/Update-ProjectPin.ps1'),'-Root',$root,'-EngineRef',$engineCommit) $root -TimeoutSeconds 120 -AllowFailure
    Write-FixtureFile $runRoot 'ignored-template-migration-result.json' ($result|ConvertTo-Json -Depth 6)
    Assert-True ($result.exitCode -eq 0) ("Ignored template control failed: "+$result.stderr)
    Assert-True (-not(Test-Path -LiteralPath (Join-Path $root '.github/workflows/unreviewed.yml')))
}
Invoke-Case 'Sandbox evidence and workspace logs retain separate artifact roots' {
    function Assert-IsolatedEvidence([string]$Text,[string]$Step) {
        $expression='${{ steps.'+$Step+'.outputs.evidence_directory }}'
        $paths=@([regex]::Matches($Text,'(?m)^\s+path: ([^\r\n]*evidence_directory[^\r\n]*)\r?$'))
        Assert-Equal 1 $paths.Count
        Assert-Equal $expression $paths[0].Groups[1].Value.Trim()
        Assert-True ($Text.Contains("if: always() && steps.$Step.outputs.evidence_directory != ''"))
        Assert-True ($Text -match '(?m)^\s+name: (workspace-evidence|qualification-workspace)-')
        Assert-True ($Text.Contains('.build/logs/**'))
    }
    foreach($item in @(@('native.yml','tests'),@('qualification.yml','qualification'))){
        $text=[IO.File]::ReadAllText((Join-Path $engineRoot ('.github/workflows/'+$item[0])))
        Assert-IsolatedEvidence $text $item[1]
        $expression='${{ steps.'+$item[1]+'.outputs.evidence_directory }}'
        $mixed=$text.Replace(('path: '+$expression),('path: |'+[char]10+'            .build/logs/**'+[char]10+'            '+$expression))
        Assert-Refused {Assert-IsolatedEvidence $mixed $item[1]}
        $unguarded=$text.Replace(("if: always() && steps."+$item[1]+".outputs.evidence_directory != ''"),'if: always()')
        Assert-Refused {Assert-IsolatedEvidence $unguarded $item[1]}
    }
}
Invoke-Case 'SDK library handoff stays within one successful regression run attempt and preserves the global production gate' {
    function Assert-SdkHandoff([string]$Text){
        Assert-True ($Text.Contains("needs: [admission, test-gate]"))
        Assert-True ($Text.Contains("if: steps.tests.outcome == 'success' && github.repository == 'RedSalamanders/DxUi' && steps.tests.outputs.sdk_inputs_directory != ''"))
        Assert-True ($Text.Contains('path: ${{ steps.tests.outputs.sdk_inputs_directory }}'))
        Assert-Equal 2 ([regex]::Matches($Text,[regex]::Escape('name: sdk-library-inputs-${{ matrix.platform }}-${{ github.run_attempt }}')).Count)
        $download=[regex]::Match($Text,'(?ms)^      - name: Download this attempt''s SDK library inputs\r?\n(?<body>.*?)(?=^      - name:)').Groups['body'].Value
        Assert-True ($download.Contains("if: github.repository == 'RedSalamanders/DxUi'"))
        Assert-True ($download.Contains('id: sdk-inputs'))
        Assert-True ($download.Contains('continue-on-error: true'))
        Assert-True ($download.Contains('path: .build/sdk-library-download/${{ matrix.platform }}'))
        Assert-True ($download -notmatch '(?m)^\s+(run-id|github-token|repository):')
        Assert-True ($Text.Contains('CI_SDK_LIBRARY_INPUTS: ${{ steps.sdk-inputs.outputs.download-path }}'))
    }
    $text=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/native.yml'))
    Assert-SdkHandoff $text
    foreach($changed in @($text.Replace('needs: [admission, test-gate]','needs: admission'),
        $text.Replace('-${{ github.run_attempt }}',''),$text.Replace("if: steps.tests.outcome == 'success' && github.repository",'if: always() && github.repository'),
        $text.Replace('id: sdk-inputs',"id: sdk-inputs`n        with:`n          run-id: 999"))){Assert-Refused {Assert-SdkHandoff $changed}}
}
Invoke-Case 'Queue compatibility validates the official value and noncancellation rules' {
    $lf=[string][char]10
    Assert-True (Test-CiWorkflowQueues ("concurrency:"+$lf+"  group: native"+$lf+"  cancel-in-progress: false"+$lf+"  queue: max"))
    Assert-True (Test-CiWorkflowQueues ("jobs:"+$lf+"  native:"+$lf+"    concurrency:"+$lf+"      group: one"+$lf+"      queue: max"))
    Assert-Refused { Test-CiWorkflowQueues ("concurrency:"+$lf+"  queue: unlimited") }
    Assert-Refused { Test-CiWorkflowQueues ("concurrency:"+$lf+"  queue: max"+$lf+"  cancel-in-progress: true") }
    Assert-Refused { Test-CiWorkflowQueues ("jobs:"+$lf+"  queue: max") }
}

Invoke-Case 'Pinned SDK admission is manual main only and preserves independent native architecture requests' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkProducer.psm1')
    $policy=Read-CiSdkProducerPolicy
    $template=[IO.File]::ReadAllText((Join-Path $engineRoot 'Templates/sdk-inputs.yml'))
    foreach($source in $policy.sources){
        Assert-True ($template.Contains($source.commit))
        foreach($platform in @('All','x64','ARM64')){
            $r=Resolve-CiSdkProducerRequest -Repository RedSalamanders/DxUi -Ref refs/heads/main -Event workflow_dispatch -SourceCommit $source.commit -RunId 123 -Platform $platform
            Assert-Equal $source.apiRevision $r.apiRevision
            Assert-Equal $policy.toolingRef $r.toolingRef
            Assert-Equal $policy.toolingContentIdentity $r.toolingContentIdentity
            Assert-Equal $source.contentIdentity $r.sourceContentIdentity
            Assert-Equal $policy.storageEngineRef $r.storageEngineRef
            Assert-Equal $policy.storageEngineContentIdentity $r.storageEngineContentIdentity
            Assert-Equal LegacyV1 $r.contract
            $qualified=Resolve-CiSdkProducerRequest -Repository RedSalamanders/DxUi -Ref refs/heads/main -Event workflow_dispatch -SourceCommit $source.commit -RunId 123 -Platform $platform -Contract QualifiedAbiV2
            Assert-Equal QualifiedAbiV2 $qualified.contract
            Assert-Equal $r.sourceContentIdentity $qualified.sourceContentIdentity
            Assert-Equal $(if($platform -ceq 'All'){2}else{1}) @($r.matrix.include).Count
            if($platform -cne 'All'){Assert-Equal $platform $r.matrix.include[0].platform}
        }
    }
    foreach($bad in @(@('RedSalamanders/RedMonitor','refs/heads/main','workflow_dispatch',$policy.sources[0].commit,'123'),
        @('RedSalamanders/DxUi','refs/heads/feature','workflow_dispatch',$policy.sources[0].commit,'123'),
        @('RedSalamanders/DxUi','refs/heads/main','pull_request',$policy.sources[0].commit,'123'),
        @('RedSalamanders/DxUi','refs/heads/main','schedule',$policy.sources[0].commit,'123'),
        @('RedSalamanders/DxUi','refs/heads/main','workflow_dispatch','main','123'),
        @('RedSalamanders/DxUi','refs/heads/main','workflow_dispatch',('1'*40),'123'),
        @('RedSalamanders/DxUi','refs/heads/main','workflow_dispatch',$policy.sources[0].commit,'0'))){
        Assert-Refused {Resolve-CiSdkProducerRequest -Repository $bad[0] -Ref $bad[1] -Event $bad[2] -SourceCommit $bad[3] -RunId $bad[4]}
    }
    $app=Read-CiProject (New-Fixture 'sdk-template-app')
    Assert-True ('sdk-inputs.yml' -cnotin @(Get-CiProjectWorkflowTemplates $app).Name)
}
Invoke-Case 'SDK producer checks actual clean Git identities, main ancestry, API and storage pin before setup' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkProducer.psm1')
    $tooling=New-Fixture 'sdk-tooling';$source=New-Fixture 'sdk-source';$storage=New-Fixture 'sdk-storage'
    $storageHead=(Invoke-CiGit $storage @('rev-parse','HEAD')).stdout.Trim()
    $manifest=Read-CiProject $tooling;$manifest.repository='RedSalamanders/DxUi';$manifest.kind='sdk';$manifest.winget=$null;$manifest.engine.ref=$storageHead
    Write-FixtureFile $tooling '.ci/project.json' ($manifest|ConvertTo-Json -Depth 8)
    $toolingHead=Save-Fixture $tooling 'Synthetic producer metadata'
    Write-FixtureFile $source 'capabilities.json' '{"apiRevision":4}'
    $sourceHead=Save-Fixture $source 'Synthetic source API'
    $null=Invoke-CiGit $tooling @('update-ref','refs/remotes/origin/main',$toolingHead)
    $request=@{toolingRef=$toolingHead;sourceCommit=$sourceHead;storageEngineRef=$storageHead;apiRevision=4;
        toolingContentIdentity=(Get-CiSdkCheckoutContentIdentity $tooling);sourceContentIdentity=(Get-CiSdkCheckoutContentIdentity $source);storageEngineContentIdentity=(Get-CiSdkCheckoutContentIdentity $storage)}
    Assert-CiSdkProducerCheckouts $request $tooling $source $storage
    $storageFile=Join-Path $storage 'README.md'
    $storageBytes=[IO.File]::ReadAllBytes($storageFile);$storageTime=[IO.File]::GetLastWriteTimeUtc($storageFile)
    $null=Invoke-CiGit $storage @('update-index','--assume-unchanged','README.md')
    try{
        $mutated=$storageBytes.Clone();$mutated[0]=$mutated[0] -bxor 1
        [IO.File]::WriteAllBytes($storageFile,$mutated);[IO.File]::SetLastWriteTimeUtc($storageFile,$storageTime)
        Assert-Equal '' (Invoke-CiGit $storage @('status','--porcelain')).stdout.Trim()
        Assert-Refused {Assert-CiSdkProducerCheckouts $request $tooling $source $storage}
    }finally{
        [IO.File]::WriteAllBytes($storageFile,$storageBytes);[IO.File]::SetLastWriteTimeUtc($storageFile,$storageTime)
        $null=Invoke-CiGit $storage @('update-index','--no-assume-unchanged','README.md')
    }
    $bad=$request.Clone();$bad.sourceCommit='1'*40
    Assert-Refused {Assert-CiSdkProducerCheckouts $bad $tooling $source $storage}
    Write-FixtureFile $source 'untracked.txt' 'mutation witness'
    Assert-Refused {Assert-CiSdkProducerCheckouts $request $tooling $source $storage}
    Remove-Item -LiteralPath (Join-Path $source 'untracked.txt')
    # Git's clean report is insufficient: preserve size/mtime and hide a real byte mutation from its index.
    $capabilities=Join-Path $source 'capabilities.json'
    $original=[IO.File]::ReadAllBytes($capabilities);$mtime=[IO.File]::GetLastWriteTimeUtc($capabilities)
    $null=Invoke-CiGit $source @('update-index','--assume-unchanged','capabilities.json')
    try{
        [IO.File]::WriteAllText($capabilities,'{"apiRevision":5}',[Text.UTF8Encoding]::new($false))
        [IO.File]::SetLastWriteTimeUtc($capabilities,$mtime)
        Assert-Equal $original.Length ([IO.File]::ReadAllBytes($capabilities)).Length
        Assert-Equal '' (Invoke-CiGit $source @('status','--porcelain')).stdout.Trim()
        Assert-Refused {Assert-CiSdkProducerCheckouts $request $tooling $source $storage}
    }finally{
        [IO.File]::WriteAllBytes($capabilities,$original);[IO.File]::SetLastWriteTimeUtc($capabilities,$mtime)
        $null=Invoke-CiGit $source @('update-index','--no-assume-unchanged','capabilities.json')
    }
    Assert-CiSdkProducerCheckouts $request $tooling $source $storage
    Write-FixtureFile $tooling 'README.md' 'Reviewed but not integrated synthetic tooling'
    $request.toolingRef=Save-Fixture $tooling 'Synthetic future tooling'
    $request.toolingContentIdentity=Get-CiSdkCheckoutContentIdentity $tooling
    Assert-Refused {Assert-CiSdkProducerCheckouts $request $tooling $source $storage}
    $null=Invoke-CiGit $tooling @('update-ref','refs/remotes/origin/main',$request.toolingRef)
    Assert-CiSdkProducerCheckouts $request $tooling $source $storage
    Write-FixtureFile $source 'capabilities.json' '{"apiRevision":5}'
    $request.sourceCommit=Save-Fixture $source 'Synthetic changed API'
    $request.sourceContentIdentity=Get-CiSdkCheckoutContentIdentity $source
    Assert-Refused {Assert-CiSdkProducerCheckouts $request $tooling $source $storage}
    Write-FixtureFile $source 'capabilities.json' '{"apiRevision":"4"}'
    $request.sourceCommit=Save-Fixture $source 'Synthetic mistyped API'
    $request.sourceContentIdentity=Get-CiSdkCheckoutContentIdentity $source
    Assert-Refused {Assert-CiSdkProducerCheckouts $request $tooling $source $storage}
}
Invoke-Case 'Actual SDK workflow resolver writes six independent outputs including its validated contract without compilation' {
    $root=New-Fixture 'sdk-workflow-output'
    $clone=Join-Path $root '.ci-engine'
    $null=Invoke-CiProcess git @('clone','--no-local','--no-hardlinks','--no-checkout',$engineRoot,$clone) $root
    $head=(Invoke-CiGit $engineRoot @('rev-parse','HEAD')).stdout.Trim()
    $null=Invoke-CiGit $clone @('checkout','--detach',$head)
    $text=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/sdk-inputs.yml'))
    $body=[regex]::Match($text,'(?m)^      - name: Resolve only reviewed pinned SDK inputs\r?\n[\s\S]*?^        run: \|\r?\n(?<body>(?:          [^\r\n]*\r?\n)+)').Groups['body'].Value
    Assert-True ($body.Length -gt 0)
    $code=($body -split '\r?\n'|ForEach-Object{$_ -replace '^          ',''}) -join "`n"
    Write-FixtureFile $root 'resolve.ps1' $code
    $policy=Read-CiSdkProducerPolicy
    $output=Join-Path $root 'github-output.txt'
    $values=@{CI_ENGINE_REF=$head;SDK_SOURCE=$policy.sources[1].commit;SDK_PLATFORM='ARM64';SDK_CONTRACT='QualifiedAbiV2';GITHUB_REPOSITORY='RedSalamanders/DxUi';
        GITHUB_REF='refs/heads/main';GITHUB_EVENT_NAME='workflow_dispatch';GITHUB_RUN_ID='321';GITHUB_OUTPUT=$output}
    $saved=@{}
    try{
        foreach($name in $values.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name);[Environment]::SetEnvironmentVariable($name,$values[$name])}
        $result=Invoke-CiProcess (Get-Process -Id $PID).Path @('-NoProfile','-NonInteractive','-File',(Join-Path $root 'resolve.ps1')) $root -TimeoutSeconds 30 -AllowFailure
        Assert-True ($result.exitCode -eq 0) $result.stderr
    }finally{foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name])}}
    $lines=@(Get-Content $output)
    Assert-Equal 6 $lines.Count
    $actual=@{}
    foreach($line in $lines){$pair=$line -split '=',2;Assert-Equal 2 $pair.Count;Assert-True (-not $actual.ContainsKey($pair[0]));$actual[$pair[0]]=$pair[1]}
    Assert-Equal $policy.sources[1].commit $actual.source
    Assert-Equal $policy.toolingRef $actual.tooling
    Assert-Equal $policy.storageEngineRef $actual.storage_engine
    Assert-Equal '0.1.321' $actual.version
    Assert-Equal QualifiedAbiV2 $actual.sdk_contract
    $matrix=$actual.matrix|ConvertFrom-Json
    Assert-Equal 1 @($matrix.include).Count
    Assert-Equal 'ARM64' $matrix.include[0].platform
    Assert-True (-not(Test-Path (Join-Path $root '.build')))
}
Invoke-Case 'Actual SDK producer branch emits a qualified reference only after every SDK gate succeeds' {
    $root=New-Fixture 'sdk-qualified-workflow-branch'
    $text=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/sdk-inputs.yml'))
    $body=[regex]::Match($text,'(?m)^      - name: Build and natively check pinned SDK input bytes\r?\n[\s\S]*?^        run: \|\r?\n(?<body>(?:          [^\r\n]*\r?\n)+)').Groups['body'].Value
    Assert-True ($body.Length -gt 0)
    $code=($body -split '\r?\n'|ForEach-Object{$_ -replace '^          ',''}) -join "`n"
    foreach($pair in @(@('.build/sdk-source/vcpkg-install.ps1','restore'),@('.build/sdk-producer/build.ps1','build'),@('.build/sdk-producer/Tools/New-SdkPackage.ps1','sdk'))){
        Write-FixtureFile $root $pair[0] (@'
param()
$Probe.calls.Add('STAGE')
$Probe.hosts.Add($env:PreferredToolArchitecture)
if($Probe.fail -ceq 'STAGE'){throw 'controlled STAGE failure'}
$global:LASTEXITCODE=0
'@.Replace('STAGE',$pair[1]))
    }
    $stage=[scriptblock]::Create(@'
param($Probe)
function Import-Module {param($Name) if(-not ($Name.EndsWith('Ci.SdkQualifiedProducer.psm1') -or $Name.EndsWith('VisualStudio.psm1'))){throw 'Unexpected SDK producer import.'}}
function Get-DxUiVisualStudioInstallation {return Join-Path $PWD '.build/controlled-vs'}
function Write-CiQualifiedSdkAbiReference {
    param($SourceRoot,$ToolingRoot,$StorageEngineRoot,$StoreRoot,$Version,$Platform,$MSBuildPath,$OutputFile)
    $Probe.calls.Add('reference');$Probe.hosts.Add($env:PreferredToolArchitecture)
    if($Probe.fail -ceq 'reference'){throw 'controlled reference failure'}
    if($Version -cne '0.1.123' -or $Platform -cne $env:SDK_PLATFORM){throw 'Qualified reference lost its version/architecture.'}
    $nativeHost=if($Platform -ceq 'x64'){'amd64'}else{'arm64'}
    if($MSBuildPath.Replace('\','/') -cnotmatch ('/MSBuild/Current/Bin/'+$nativeHost+'/MSBuild.exe$')){throw 'Qualified reference selected another MSBuild host.'}
    return $OutputFile
}
'@ + "`n"+$code)
    $names=@('SDK_CONTRACT','SDK_PLATFORM','SDK_VERSION','RUNNER_TEMP','GITHUB_OUTPUT','PreferredToolArchitecture','VCPKG_BINARY_SOURCES')
    $saved=@{};foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    $location=Get-Location
    try{
        Set-Location -LiteralPath $root
        $env:SDK_VERSION='0.1.123';$env:RUNNER_TEMP=Join-Path $root '.build/smoke';$env:GITHUB_OUTPUT=Join-Path $root '.build/outputs.txt'
        foreach($contract in @('LegacyV1','QualifiedAbiV2')){foreach($platform in @('x64','ARM64')){foreach($failure in @('','restore','build','sdk','reference')){
            if($contract -ceq 'LegacyV1' -and $failure -ceq 'reference'){continue}
            $env:SDK_CONTRACT=$contract;$env:SDK_PLATFORM=$platform;$env:PreferredToolArchitecture='fixture-caller'
            $probe=@{calls=[Collections.Generic.List[string]]::new();hosts=[Collections.Generic.List[string]]::new();fail=$failure};$message=''
            try{& $stage $probe}catch{$message=$_.Exception.Message}
            $expected=@('restore','build','sdk');if($contract -ceq 'QualifiedAbiV2'){$expected+=@('reference')}
            if($failure){$expected=$expected[0..[Array]::IndexOf($expected,$failure)]}
            Assert-Equal ($expected -join ',') ($probe.calls -join ',')
            if($failure){Assert-True ($message.Contains("controlled $failure failure"))}else{Assert-Equal '' $message}
            $hostValue=if($contract -ceq 'QualifiedAbiV2'){if($platform -ceq 'x64'){'x64'}else{'arm64'}}else{'fixture-caller'}
            foreach($observed in $probe.hosts){Assert-Equal $hostValue $observed}
        }}}
    }finally{
        Set-Location -LiteralPath $location
        foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
    }
}
Invoke-Case 'Actual qualified producer ABI query explicitly preserves each native compiler host' {
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $engineRoot 'Tools/Modules/Ci.SdkQualifiedProducer.psm1'),[ref]$tokens,[ref]$errors)
    Assert-Equal 0 $errors.Count
    $query=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Get-CiSdkAbiReference'},$true))
    Assert-Equal 1 $query.Count
    $stage=[scriptblock]::Create(@'
param($expectedHost,$Platform)
$ToolingRoot='controlled-tooling';$MSBuildPath='controlled-msbuild';$SourceRoot='controlled-source'
function Get-CiSdkAbiReference {
    param($ToolingRoot,$MSBuildPath,$ProjectPath,$Platform,$PreferredToolArchitecture)
    if($PreferredToolArchitecture -cne $expectedHost.ToLowerInvariant()){throw 'Native compiler-host selection was lost.'}
    if($Platform -cne $(if($expectedHost -ceq 'X64'){'x64'}else{'ARM64'})){throw 'Target platform was lost.'}
    return $PreferredToolArchitecture
}
'@+"`n"+$query[0].Extent.Text)
    Assert-Equal x64 (& $stage X64 x64)
    Assert-Equal arm64 (& $stage Arm64 ARM64)
}
Invoke-Case 'SDK workflow keeps reviewed tooling separate, read-only tokens and native-success attempt-bound artifacts' {
    function Assert-SdkProducerWorkflow([string]$Text){
        foreach($required in @("github.event_name == 'workflow_dispatch'","github.ref == 'refs/heads/main'",'contents: read','actions: read',
            'ref: ${{ needs.resolve.outputs.tooling }}','ref: ${{ needs.resolve.outputs.source }}','ref: ${{ needs.resolve.outputs.storage_engine }}',
            'Assert-CiSdkProducerCheckouts','git config --global core.autocrlf true','if: steps.build.outcome == ''success''','-${{ github.run_attempt }}',
            '-SdkStoreRoot','-ProductionOnly','-SmokeRoot $env:RUNNER_TEMP',
            '    name: sdk (${{ matrix.platform }}, ${{ matrix.runner }})')){Assert-True ($Text.Contains($required))}
        Assert-True (-not($Text.Contains('contents: write') -or $Text.Contains('statuses: write') -or $Text.Contains('secrets: inherit')))
        Assert-True ($Text.IndexOf('Assert-CiSdkProducerCheckouts') -lt $Text.IndexOf('uses: ./.build/sdk-producer/.github/actions/setup-msvc'))
        Assert-True (-not($Text.Contains('Invoke-Admission') -or $Text.Contains('ci-state') -or $Text.Contains('ProductionRelease')))
    }
    $text=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/sdk-inputs.yml'))
    Assert-SdkProducerWorkflow $text
    foreach($bad in @($text.Replace("github.event_name == 'workflow_dispatch'",'true'),
        $text.Replace('contents: read','contents: write'),$text.Replace("if: steps.build.outcome == 'success'",'if: always()'),
        $text.Replace('-${{ github.run_attempt }}',''),$text.Replace('core.autocrlf true','core.autocrlf false'),
        $text.Replace('Assert-CiSdkProducerCheckouts','UncheckedSdkInputs'),
        $text.Replace('    name: sdk (${{ matrix.platform }}, ${{ matrix.runner }})','    name: sdk (${{ matrix.runner }}, ${{ matrix.platform }})'))){Assert-Refused {Assert-SdkProducerWorkflow $bad}}
}

Invoke-Case 'SDK compilation checks the actual live reader handle across processes and refuses stale or mismatched settings' {
    $consumer=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkConsumer.psm1') -PassThru
    $root=New-Fixture 'sdk-reader-owner'
    $payload=Join-Path $root '.build/payload'
    $witness=& $consumer {param($r,$s) New-CiSdkConsumerWitness $r $s x64} $root $payload
    $command=Join-Path $engineRoot 'Tools/Test-SdkConsumerLease.ps1'
    $arguments=@('-NoProfile','-NonInteractive','-File',$command,'-ProjectRoot',$root,'-LeasePath',$witness.Path,'-SdkRoot',$payload,'-Platform','x64','-Configuration','Release')
    try{
        Assert-CiSdkConsumerLease -ProjectRoot $root -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release
        $actual=Invoke-CiProcess (Get-Process -Id $PID).Path $arguments $root -TimeoutSeconds 30 -AllowFailure
        Assert-True ($actual.exitCode -eq 0) ('SDK reader child refused: '+$actual.stderr+' '+$actual.stdout)
        $original=[byte[]]::new($witness.Stream.Length)
        $witness.Stream.Position=0;$witness.Stream.ReadExactly($original)
        $changed=[Text.UTF8Encoding]::new($false).GetString($original)|ConvertFrom-Json
        $changed.ownerIdentity+='-stale'
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($changed|ConvertTo-Json -Compress))
        try{
            $witness.Stream.Position=0;$witness.Stream.SetLength(0);$witness.Stream.Write($bytes);$witness.Stream.Flush($true)
            Assert-Refused {Assert-CiSdkConsumerLease -ProjectRoot $root -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release}
        }finally{$witness.Stream.Position=0;$witness.Stream.SetLength(0);$witness.Stream.Write($original);$witness.Stream.Flush($true)}
        foreach($wrong in @(@($payload,'ARM64','Release'),@($payload,'x64','Debug'),@((Join-Path $root '.build/other'),'x64','Release'))){
            Assert-Refused {Assert-CiSdkConsumerLease -ProjectRoot $root -LeasePath $witness.Path -SdkRoot $wrong[0] -Platform $wrong[1] -Configuration $wrong[2]}
        }
        Assert-Refused {Assert-CiSdkConsumerLease -ProjectRoot (Join-Path $root 'another-project') -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release}
    }finally{$witness.Stream.Dispose()}
    # The creator PID is still alive and the file remains, but its handle no longer exists.
    $stale=Invoke-CiProcess (Get-Process -Id $PID).Path $arguments $root -TimeoutSeconds 30 -AllowFailure
    Assert-True ($stale.exitCode -ne 0)
}

Invoke-Case 'Explicit SDK ABI controls refuse compiler-free invocation before creating fixtures' {
    $fixture=New-Fixture 'sdk-abi-pr-refusal'
    $command=Join-Path $engineRoot 'Tools/Test-SdkConsumerPolicy.ps1'
    $args=@('-NoProfile','-NonInteractive','-File',$command,'-ProjectRoot',$fixture,'-SdkRoot',(Join-Path $fixture 'absent'),
        '-LeasePath',(Join-Path $fixture 'absent.json'),'-Platform','x64','-MSBuildPath',(Join-Path $fixture 'absent.exe'))
    $saved=[Environment]::GetEnvironmentVariable('CI_NATIVE_BUILDS_DISABLED','Process')
    try{
        $env:CI_NATIVE_BUILDS_DISABLED='true'
        $actual=Invoke-CiProcess (Get-Process -Id $PID).Path $args $fixture -TimeoutSeconds 30 -AllowFailure
        Assert-True ($actual.exitCode -ne 0 -and ($actual.stdout+$actual.stderr).Contains('require explicit native-tooling execution'))
        Assert-True (-not(Test-Path (Join-Path $fixture '.build')))
    }finally{[Environment]::SetEnvironmentVariable('CI_NATIVE_BUILDS_DISABLED',$saved,'Process')}
}

Invoke-Case 'Application SDK binding verifies the actual lock and clean pinned controller before invoking any producer tooling' {
    $consumer=Get-Module Ci.SdkConsumer
    $controller=New-Fixture 'sdk-application-controller'
    $fixture=New-Fixture 'sdk-application-lock'
    $project=Read-CiProject $fixture;$project.engine.ref=Resolve-CiCommit $controller HEAD
    Write-FixtureFile $fixture '.ci/project.json' ($project|ConvertTo-Json -Depth 8)
    $lock=@{repository='https://github.com/RedSalamanders/DxUi';commit=('a'*40);apiRevision=4;targets=@('DxUi')}
    Write-FixtureFile $fixture 'Dependencies/DxUi.lock.json' ($lock|ConvertTo-Json)
    $actual=& $consumer {param($r,$c) Read-CiApplicationSdkLock $r $c} $fixture $controller
    Assert-Equal $lock.commit $actual.commit
    foreach($name in @('repository','commit','apiRevision','targets')){
        $bad=$lock.Clone();$bad[$name]=switch($name){repository{'https://example.invalid/DxUi'};commit{'main'};apiRevision{'4'};targets{@('DxUi','Other')}}
        Write-FixtureFile $fixture 'Dependencies/DxUi.lock.json' ($bad|ConvertTo-Json)
        Assert-Refused {& $consumer {param($r,$c) Read-CiApplicationSdkLock $r $c} $fixture $controller}
    }
    Write-FixtureFile $fixture 'Dependencies/DxUi.lock.json' ($lock|ConvertTo-Json)
    Write-FixtureFile $controller 'src/main.cpp' 'changed controller'
    Assert-Refused {& $consumer {param($r,$c) Read-CiApplicationSdkLock $r $c} $fixture $controller}
    $null=Save-Fixture $controller 'Controller changed'
    Assert-Refused {& $consumer {param($r,$c) Read-CiApplicationSdkLock $r $c} $fixture $controller}
}
Invoke-Case 'Local SDK descriptors are independent, strictly typed and cannot change the application lock or profile' {
    $consumer=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkConsumer.psm1') -PassThru
    $root=New-Fixture 'sdk-local-descriptor'
    $policy=Read-CiSdkProducerPolicy
    $d=@{schemaVersion=1;role='LocalPinnedDependencyInput';sourceCommit=$policy.sources[1].commit;apiRevision=4;platform='x64';
        sourceRoot='unused';toolingRoot='unused';storageEngineRoot='unused';storeRoot=(Join-Path $root '.build/store');manifestSha256=('1'*64)}
    $path=Join-Path $root '.build/input.json'
    Write-FixtureFile $root '.build/input.json' ($d|ConvertTo-Json)
    $read=& $consumer {param($r,$p) Read-CiLocalSdkDescriptor $r $p} $root $path
    Assert-Equal $d.sourceCommit $read.Value.sourceCommit
    foreach($changed in @('bad-source','bad-api','bad-platform','unsupported-configuration')){
        $values=@{ProjectRoot=$root;Descriptor=$path;ExpectedSourceCommit=$d.sourceCommit;ExpectedApiRevision=4;Platform='x64';Configuration='Release'}
        switch($changed){'bad-source'{$values.ExpectedSourceCommit='2'*40};'bad-api'{$values.ExpectedApiRevision=5};'bad-platform'{$values.Platform='ARM64'};default{$values.Configuration='Debug'}}
        $reason=$null
        try{Open-CiPinnedSdkInput @values|Out-Null}catch{$reason=$_.Exception.Message}
        Assert-True ($null -ne $reason -and $reason -match $(if($changed -ceq 'unsupported-configuration'){'Release only'}else{'cannot advance the application lock'}))
    }
    foreach($field in @('verdict','apiRevision')){
        $bad=$d.Clone();$bad[$field]=if($field -ceq 'verdict'){'passed'}else{'4'}
        Write-FixtureFile $root '.build/input.json' ($bad|ConvertTo-Json)
        Assert-Refused {& $consumer {param($r,$p) Read-CiLocalSdkDescriptor $r $p} $root $path}
    }
    Write-FixtureFile $root '.build/store/self-input.json' ($d|ConvertTo-Json)
    Assert-Refused {& $consumer {param($r,$p) Read-CiLocalSdkDescriptor $r $p} $root (Join-Path $root '.build/store/self-input.json')}
    Write-FixtureFile $root 'outside-input.json' ($d|ConvertTo-Json)
    Assert-Refused {& $consumer {param($r,$p) Read-CiLocalSdkDescriptor $r $p} $root (Join-Path $root 'outside-input.json')}
}

Invoke-Case 'Fast SDK bootstrap retains the exact ordinal raw map, missing-file refusal and per-read reparse barriers' {
    $root=New-Fixture 'sdk-raw-map'
    Write-FixtureFile $root 'src/café 日本語.cpp' 'Unicode raw source input'
    $listed=(Invoke-CiGit $root @('ls-files','--cached','--others','--exclude-standard','-z')).stdout
    $paths=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach($p in $listed.Split([char]0,[StringSplitOptions]::RemoveEmptyEntries)){[void]$paths.Add($p)}
    $rows=@(foreach($p in $paths){$p+[char]0+(Get-FileHash -LiteralPath (Join-Path $root $p)).Hash})
    Assert-Equal (Get-CiSha256 ($rows -join "`n")) (Get-CiSdkCheckoutContentIdentity $root)
    $src=Join-Path $root 'src';$held=Join-Path $root '.build/original-src'
    [void][IO.Directory]::CreateDirectory((Split-Path $held -Parent))
    Move-Item -LiteralPath $src -Destination $held
    $null=New-Item -ItemType $(if($IsWindows){'Junction'}else{'SymbolicLink'}) -Path $src -Target $held
    try{Assert-Refused {Get-CiSdkCheckoutContentIdentity $root}}
    finally{Remove-Item -LiteralPath $src;Move-Item -LiteralPath $held -Destination $src}
    Remove-Item -LiteralPath (Join-Path $src 'main.cpp')
    Assert-Refused {Get-CiSdkCheckoutContentIdentity $root}
}

function New-CandidateFixture([string]$Name,[switch]$Prose,[switch]$ShadowCaller){
    $root=New-Fixture $Name
    if($ShadowCaller){
        Write-FixtureFile $root '.github/workflows/integration-execution.yml' '# Owned controller fixture data; never executed.'
        $null=Save-Fixture $root 'Owned shadow caller fixture'
    }
    $base=(Invoke-CiGit $root @('rev-parse','HEAD')).stdout.Trim()
    $null=Invoke-CiGit $root @('checkout','-b','candidate-feature')
    if($Prose){Write-FixtureFile $root 'README.md' 'Candidate prose only.'}else{Write-FixtureFile $root 'src/main.cpp' 'int fixture() { return 42; }'}
    $head=Save-Fixture $root 'Candidate head'
    $tree=(Invoke-CiGit $root @('rev-parse',($head+'^{tree}'))).stdout.Trim()
    $merge=(Invoke-CiGit $root @('commit-tree',$tree,'-p',$base,'-p',$head,'-m','Synthetic candidate fixture')).stdout.Trim()
    $pr=@{number=43;state='open';draft=$false;merged=$false;mergeable=$true;
        head=@{sha=$head;repo=@{full_name='RedSalamanders/RedMonitor'}};base=@{sha=$base;ref='main';repo=@{full_name='RedSalamanders/RedMonitor'}}}
    return @{root=$root;base=$base;head=$head;merge=$merge;tree=$tree;pr=$pr}
}
Invoke-Case 'Candidate freeze uses the complete immutable synthetic merge, exact parents, native inputs and version' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.Candidate.psm1')
    $f=New-CandidateFixture 'candidate-native'
    $candidate=New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('f'*40)
    Assert-Equal $f.tree $candidate.mergeTree
    Assert-Equal $f.head $candidate.headCommit
    Assert-Equal $f.base $candidate.baseCommit
    Assert-Equal $f.merge $candidate.input.commit
    Assert-True ($candidate.nativeRequired -and $candidate.input.nativeDigest -cne $candidate.baseNativeDigest)
    Assert-Equal (New-CiInputDescriptor $f.root -Ref $f.merge).version $candidate.input.version
    Assert-CiIntegrationCandidateCurrent -Root $f.root -Candidate $candidate -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('f'*40)
    # Uncommitted workspace data cannot substitute for a committed integration or execute as controller code.
    Write-FixtureFile $f.root '.ci/project.json' 'Unreadable working policy must not enter a committed source snapshot.'
    Write-FixtureFile $f.root 'src/never-run.ps1' 'throw "Untrusted source was executed"'
    $again=New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('f'*40)
    Assert-Equal $candidate.identity $again.identity
}
Invoke-Case 'Candidate snapshots refuse draft, closed, conflicting, unknown, moved and malformed PR metadata' {
    $f=New-CandidateFixture 'candidate-refusals'
    foreach($field in @('draft','merged','state','mergeable','number','base-ref','base-repository','base-sha','head-sha','head-repository')){
        $pr=$f.pr|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
        switch($field){
            'draft'{$pr.draft=$true};'merged'{$pr.merged=$true};'state'{$pr.state='closed'};'mergeable'{$pr.mergeable=$null};'number'{$pr.number='43'}
            'base-ref'{$pr.base.ref='feature'};'base-repository'{$pr.base.repo.full_name='RedSalamanders/DxUi'};'base-sha'{$pr.base.sha='1'*40}
            'head-sha'{$pr.head.sha='--output=unexpected'};'head-repository'{$pr.head.repo.full_name='../../outside'}
        }
        Assert-Refused {New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('f'*40)}
    }
    Assert-Refused {New-CiIntegrationCandidate -Root $f.root -Repository 'outside/project' -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('f'*40)}
    $reverse=(Invoke-CiGit $f.root @('commit-tree',$f.tree,'-p',$f.head,'-p',$f.base,'-m','Reversed synthetic parents')).stdout.Trim()
    $pr=$f.pr|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
    Assert-Refused {New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $pr -CurrentMainCommit $f.base -MergeCommit $reverse -ControllerEngineRef ('f'*40)}
    Assert-Refused {New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $pr -CurrentMainCommit $f.base -MergeCommit $f.head -ControllerEngineRef ('f'*40)}
}
Invoke-Case 'Candidate recheck refuses source/base movement and complete descriptor tampering, including recomputed digests' {
    $f=New-CandidateFixture 'candidate-drift'
    $candidate=New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('f'*40)
    Assert-Refused {Assert-CiIntegrationCandidateCurrent -Root $f.root -Candidate $candidate -PullRequest $f.pr -CurrentMainCommit $f.head -MergeCommit $f.merge -ControllerEngineRef ('f'*40)}
    foreach($field in @('pullRequest','mergeTree','headCommit','controllerEngineRef','input','nativeRequired','passed')){
        $changed=$candidate|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable
        switch($field){'pullRequest'{$changed.pullRequest=44};'mergeTree'{$changed.mergeTree='1'*40};'headCommit'{$changed.headCommit='2'*40};'controllerEngineRef'{$changed.controllerEngineRef='3'*40};
            'input'{$changed.input.buildNumber++};'nativeRequired'{$changed.nativeRequired=$false};default{$changed.passed=$true}}
        $changed.Remove('identity');$changed.identity=Get-CiSha256 ($changed|ConvertTo-Json -Depth 15 -Compress)
        Assert-Refused {Assert-CiIntegrationCandidateCurrent -Root $f.root -Candidate $changed -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('f'*40)}
    }
}
Invoke-Case 'Current REST candidate acquisition reads the exact merge ref independently of PR payloads' {
    $module=Get-Module Ci.Candidate
    $valid=@{ref='refs/pull/43/merge';object=@{type='commit';sha=('b'*40)}}
    Assert-Equal ('b'*40) (& $module {param($r) Get-CiCandidateMergeRefCommit $r 43} $valid)
    foreach($field in @('ref','type','sha')){
        $bad=$valid|ConvertTo-Json -Depth 3|ConvertFrom-Json -AsHashtable
        switch($field){'ref'{$bad.ref='refs/pull/44/merge'};'type'{$bad.object.type='tag'};'sha'{$bad.object.sha='--output=unexpected'}}
        Assert-Refused {& $module {param($r) Get-CiCandidateMergeRefCommit $r 43} $bad}
    }
}
Invoke-Case 'Prose-only candidate inputs create no native obligation and supply no execution or qualification verdict' {
    $f=New-CandidateFixture 'candidate-prose' -Prose
    $candidate=New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('f'*40)
    Assert-True (-not $candidate.nativeRequired)
    Assert-Equal $candidate.baseNativeDigest $candidate.input.nativeDigest
    Assert-True ($candidate.input.buildNumber -gt (New-CiInputDescriptor $f.root -Ref $f.base).buildNumber)
    foreach($field in @('passed','qualified','outcome','executed','adopted')){Assert-True (-not $candidate.Contains($field))}
}

Invoke-Case 'Candidate shadow inputs bind the exact isolated controller and frozen native batch without verdict authority' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.CandidateExecution.psm1')
    foreach($prose in @($false,$true)){
        $f=New-CandidateFixture ('shadow-context-'+$prose) -Prose:$prose
        $candidate=New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('a'*40)
        $nonce='d'*32
        $branch='refs/heads/ci-native/pr43/'+$candidate.identity+'/'+$nonce
        $context=[ordered]@{repository='RedSalamanders/RedMonitor';event='workflow_dispatch';ref=$branch;commit=$f.base;
            workflowRef=('RedSalamanders/RedMonitor/.github/workflows/integration-execution.yml@'+$branch);runId='678';runAttempt=2}
        $before=$candidate|ConvertTo-Json -Depth 15 -Compress
        $result=New-CiCandidateExecutionInputs -Candidate $candidate -Context $context -IsolationNonce $nonce -ControllerWorkflowBlob ('e'*40)
        Assert-Equal 'CandidateExecutionInputs' $result.role
        Assert-Equal $f.merge $result.batch.commit
        Assert-Equal $candidate.input.version $result.batch.version
        Assert-Equal $candidate.input.buildNumber $result.batch.buildNumber
        Assert-Equal $candidate.input.nativeDigest $result.batch.nativeDigest
        Assert-Equal '678' $result.batch.runId
        Assert-Equal 2 $result.runAttempt
        Assert-Equal $f.base $result.controllerCommit
        Assert-Equal $branch $result.isolationRef
        Assert-Equal (-not $prose) $result.candidate.nativeRequired
        Assert-Equal 0 $result.nativeExecutions
        Assert-True (-not $result.suppliesNativeVerdict)
        Assert-Equal $before ($candidate|ConvertTo-Json -Depth 15 -Compress)
        foreach($field in @('event','ref','commit','workflowRef','repository','runId','runAttempt','unknown')){
            $changed=$context|ConvertTo-Json|ConvertFrom-Json -AsHashtable
            switch($field){
                'event'{$changed.event='pull_request_target'};'ref'{$changed.ref='refs/heads/main'}
                'commit'{$changed.commit=$f.head};'workflowRef'{$changed.workflowRef+='-other'}
                'repository'{$changed.repository='RedSalamanders/DxUi'};'runId'{$changed.runId='0'}
                'runAttempt'{$changed.runAttempt='2'};'unknown'{$changed.passed=$true}
            }
            Assert-Refused {New-CiCandidateExecutionInputs -Candidate $candidate -Context $changed -IsolationNonce $nonce -ControllerWorkflowBlob ('e'*40)}
        }
        foreach($failure in @('fork','engine','obligation','version','identity')){
            $changed=$candidate|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable
            switch($failure){
                'fork'{$changed.headRepository='outside/project'};'engine'{$changed.controllerEngineRef='f'*40}
                'obligation'{$changed.nativeRequired=-not $changed.nativeRequired};'version'{$changed.input.version='0.1.65535'}
                'identity'{$changed.identity='0'*64}
            }
            if($failure -cne 'identity'){
                $changed.Remove('identity')
                $changed.identity=Get-CiSha256 ($changed|ConvertTo-Json -Depth 15 -Compress)
            }
            $changedContext=$context|ConvertTo-Json|ConvertFrom-Json -AsHashtable
            $changedContext.ref='refs/heads/ci-native/pr43/'+$changed.identity+'/'+$nonce
            $changedContext.workflowRef='RedSalamanders/RedMonitor/.github/workflows/integration-execution.yml@'+$changedContext.ref
            Assert-Refused {New-CiCandidateExecutionInputs -Candidate $changed -Context $changedContext -IsolationNonce $nonce -ControllerWorkflowBlob ('e'*40)}
        }
    }
}

Invoke-Case 'Public shadow acquisition refuses invalid hosted context before API requests or output mutation' {
    $module=Get-Module Ci.CandidateExecution
    $f=New-CandidateFixture 'shadow-public-refusals'
    $null=Invoke-CiGit $f.root @('checkout','--detach',$f.base)
    $expected='d'*64;$nonce='e'*32
    $branch='refs/heads/ci-native/pr43/'+$expected+'/'+$nonce
    $environment=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';GITHUB_REPOSITORY='RedSalamanders/RedMonitor';
        GITHUB_EVENT_NAME='workflow_dispatch';GITHUB_REF=$branch;GITHUB_SHA=$f.base;
        GITHUB_WORKFLOW_REF=('RedSalamanders/RedMonitor/.github/workflows/integration-execution.yml@'+$branch);
        GITHUB_RUN_ID='678';GITHUB_RUN_ATTEMPT='1'}
    $saved=@{};foreach($name in $environment.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    $original=& $module {(Get-Command Get-CiMainHead).ScriptBlock}
    & $module {$script:shadowApiCalls=0;function script:Get-CiMainHead {$script:shadowApiCalls++;throw 'Recording API boundary; no remote request'}}
    try{
        foreach($field in @('GITHUB_ACTIONS','RUNNER_ENVIRONMENT','GITHUB_REPOSITORY','GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_SHA','GITHUB_WORKFLOW_REF','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT','valid-context')){
            foreach($name in $environment.Keys){[Environment]::SetEnvironmentVariable($name,$environment[$name],'Process')}
            if($field -cne 'valid-context'){[Environment]::SetEnvironmentVariable($field,'invalid','Process')}
            & $module {$script:shadowApiCalls=0}
            Assert-Refused {Get-CiCandidateExecutionInputs -Root $f.root -PullRequest 43 -ExpectedIdentity $expected -IsolationNonce $nonce}
            Assert-Equal $(if($field -ceq 'valid-context'){1}else{0}) (& $module {$script:shadowApiCalls})
            Assert-True (-not(Test-Path -LiteralPath (Join-Path $f.root '.build')))
            Assert-Equal $f.base (Resolve-CiCommit $f.root HEAD)
            Assert-Equal '' (Invoke-CiGit $f.root @('status','--porcelain','--untracked-files=all')).stdout.Trim()
        }
    }finally{
        foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
        & $module {param($saved)Set-Item function:script:Get-CiMainHead $saved;Remove-Variable shadowApiCalls -Scope Script} $original
    }
}

Invoke-Case 'Actual shadow gateway rechecks independent controller refs, workflow blob and complete candidate after acquisition' {
    $module=Get-Module Ci.CandidateExecution
    $f=New-CandidateFixture 'shadow-gateway-roundtrip' -ShadowCaller
    $null=Invoke-CiGit $f.root @('checkout','--detach',$f.base)
    $candidate=New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('a'*40)
    $nonce='e'*32;$branch='refs/heads/ci-native/pr43/'+$candidate.identity+'/'+$nonce
    $blob=(Invoke-CiGit $f.root @('rev-parse',($f.base+':.github/workflows/integration-execution.yml'))).stdout.Trim()
    $environment=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';GITHUB_REPOSITORY='RedSalamanders/RedMonitor';
        GITHUB_EVENT_NAME='workflow_dispatch';GITHUB_REF=$branch;GITHUB_SHA=$f.base;
        GITHUB_WORKFLOW_REF=('RedSalamanders/RedMonitor/.github/workflows/integration-execution.yml@'+$branch);
        GITHUB_RUN_ID='678';GITHUB_RUN_ATTEMPT='1'}
    $saved=@{};foreach($name in $environment.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    $originals=& $module { $saved=@{};foreach($name in @('Get-CiMainHead','Get-CiIntegrationCandidate','Invoke-CiApi')){$saved[$name]=(Get-Command $name).ScriptBlock};return $saved }
    & $module {
        function script:Get-CiMainHead {
            $script:shadowControl.mainReads++
            if($script:shadowControl.failure -ceq 'main-moved' -and $script:shadowControl.mainReads -eq 2){return ('f'*40)}
            return $script:shadowControl.base
        }
        function script:Get-CiIntegrationCandidate {
            $script:shadowControl.acquisitions++
            $result=$script:shadowControl.candidate|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable
            if($script:shadowControl.failure -ceq 'engine-pin'){$result.input.engine.ref='f'*40}
            if($script:shadowControl.failure -ceq 'candidate-moved' -and $script:shadowControl.acquisitions -eq 2){$result.headCommit='f'*40}
            return $result
        }
        function script:Invoke-CiApi {
            param($Route,$Method)
            if($Method -cne 'GET'){throw 'Unexpected remote write in shadow input acquisition'}
            $c=$script:shadowControl
            if($Route -ceq ('repos/RedSalamanders/RedMonitor/git/ref/'+$c.branch.Substring(5))){
                $c.refReads++
                $sha=if(($c.failure -ceq 'ref-before' -and $c.refReads -eq 1) -or ($c.failure -ceq 'ref-after' -and $c.refReads -eq 2)){'f'*40}else{$c.base}
                return @{ref=$c.branch;object=@{type='commit';sha=$sha}}
            }
            if($Route -ceq ('repos/RedSalamanders/RedMonitor/contents/.github/workflows/integration-execution.yml?ref='+$c.base)){
                $c.workflowReads++
                return @{path='.github/workflows/integration-execution.yml';sha=$(if($c.failure -ceq 'workflow-blob'){'f'*40}else{$c.blob})}
            }
            throw 'Unexpected remote route in shadow input acquisition'
        }
    }
    try{
        foreach($name in $environment.Keys){[Environment]::SetEnvironmentVariable($name,$environment[$name],'Process')}
        foreach($failure in @('none','engine-pin','candidate-moved','main-moved','ref-before','ref-after','workflow-blob','untracked-controller')){
            & $module {param($f,$c,$b,$blob,$failure)$script:shadowControl=@{base=$f.base;candidate=$c;branch=$b;blob=$blob;failure=$failure;mainReads=0;acquisitions=0;refReads=0;workflowReads=0}} $f $candidate $branch $blob $failure
            $untracked=Join-Path $f.root 'never-execute.ps1'
            if($failure -ceq 'untracked-controller'){[IO.File]::WriteAllText($untracked,'throw "Candidate code must never execute during acquisition"')}
            try{
                if($failure -ceq 'none'){
                    $result=Get-CiCandidateExecutionInputs -Root $f.root -PullRequest 43 -ExpectedIdentity $candidate.identity -IsolationNonce $nonce
                    Assert-Equal $blob $result.controllerWorkflowBlob
                    Assert-Equal $f.merge $result.batch.commit
                    Assert-Equal 0 $result.nativeExecutions
                    Assert-True (-not $result.suppliesNativeVerdict)
                    $counts=& $module {$script:shadowControl}
                    Assert-Equal 2 $counts.mainReads;Assert-Equal 2 $counts.acquisitions
                    Assert-Equal 2 $counts.refReads;Assert-Equal 1 $counts.workflowReads
                }else{Assert-Refused {Get-CiCandidateExecutionInputs -Root $f.root -PullRequest 43 -ExpectedIdentity $candidate.identity -IsolationNonce $nonce}}
                Assert-True (-not(Test-Path -LiteralPath (Join-Path $f.root '.build')))
                Assert-Equal $f.base (Resolve-CiCommit $f.root HEAD)
            }finally{if($failure -ceq 'untracked-controller'){Remove-Item -LiteralPath $untracked}}
        }
    }finally{
        foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
        & $module {param($saved)foreach($name in $saved.Keys){Set-Item ('function:script:'+$name) $saved[$name]};Remove-Variable shadowControl -Scope Script} $originals
    }
}

Invoke-Case 'Isolated native batch roundtrips retain live context and cannot enter production' {
    $f=New-CandidateFixture 'candidate-native-batch'
    $candidate=New-CiIntegrationCandidate -Root $f.root -Repository RedSalamanders/RedMonitor -PullRequest $f.pr -CurrentMainCommit $f.base -MergeCommit $f.merge -ControllerEngineRef ('a'*40)
    $nonce='d'*32;$branch='refs/heads/ci-native/pr43/'+$candidate.identity+'/'+$nonce
    $context=[ordered]@{repository='RedSalamanders/RedMonitor';event='workflow_dispatch';ref=$branch;commit=$f.base;
        workflowRef=('RedSalamanders/RedMonitor/.github/workflows/integration-execution.yml@'+$branch);runId='678';runAttempt=2}
    $input=New-CiCandidateExecutionInputs -Candidate $candidate -Context $context -IsolationNonce $nonce -ControllerWorkflowBlob ('e'*40)
    $batch=$input.batch|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
    $environment=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';GITHUB_REPOSITORY=$context.repository;
        GITHUB_EVENT_NAME=$context.event;GITHUB_REF=$context.ref;GITHUB_SHA=$context.commit;
        GITHUB_WORKFLOW_REF=$context.workflowRef;GITHUB_RUN_ID=$context.runId;GITHUB_RUN_ATTEMPT='2'}
    $saved=@{};foreach($name in $environment.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    try{
        foreach($name in $environment.Keys){[Environment]::SetEnvironmentVariable($name,$environment[$name],'Process')}
        Assert-True (Assert-CiCandidateExecutionBatch -Descriptor $batch)
        foreach($field in @('commit','version','runId','engine','unknown','binding-role','binding-attempt','binding-ref','binding-candidate','missing-binding')){
            $changed=$batch|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
            switch($field){
                'commit'{$changed.commit=$f.head};'version'{$changed.version='0.1.65535'};'runId'{$changed.runId='679'}
                'engine'{$changed.engine.ref='f'*40};'unknown'{$changed.passed=$true}
                'binding-role'{$changed.candidateExecution.role='Production'}
                'binding-attempt'{$changed.candidateExecution.context.runAttempt='2'}
                'binding-ref'{$changed.candidateExecution.context.ref='refs/heads/main'}
                'binding-candidate'{$changed.candidateExecution.candidate.headCommit='f'*40}
                'missing-binding'{$changed.Remove('candidateExecution')}
            }
            Assert-Refused {Assert-CiCandidateExecutionBatch -Descriptor $changed}
        }
        $env:GITHUB_RUN_ATTEMPT='3';Assert-Refused {Assert-CiCandidateExecutionBatch -Descriptor $batch};$env:GITHUB_RUN_ATTEMPT='2'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $engineRoot 'Tools/Modules/Ci.Project.psm1'),[ref]$tokens,[ref]$errors)
        Assert-Equal 0 $errors.Count
        $guards=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text -match '^if\(\$batch\.Contains\(''candidateExecution''\)'},$true))
        Assert-Equal 1 $guards.Count
        $guard=[scriptblock]::Create($guards[0].Extent.Text)
        foreach($phase in @('ReleaseTestBuild','ReleaseTest','Production','Qualification')){
            $passed=& {param($Body,$batch,$Phase)try{& $Body;return $true}catch{return $false}} $guard $batch $phase
            Assert-Equal ($phase -in @('ReleaseTestBuild','ReleaseTest')) $passed
        }
        $without=$batch|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable;$without.Remove('candidateExecution')
        Assert-Refused {& {param($Body,$batch)$Phase='ReleaseTestBuild';& $Body} $guard $without}
        $sdkAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $engineRoot 'Tools/Modules/Ci.SdkPreparation.psm1'),[ref]$tokens,[ref]$errors)
        Assert-Equal 0 $errors.Count
        $function=@($sdkAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Initialize-CiPinnedSdkInput'},$true))
        Assert-Equal 1 $function.Count
        $prefix=@($function[0].Body.EndBlock.Statements|Select-Object -First 3)
        Assert-True ($prefix[0].Extent.Text -match '^\$main=')
        Assert-True ($prefix[2].Extent.Text -match '^if\(\$Context.phase')
        # Extracting an AST drops its source-file automatic variables. Bind only
        # the original module directory; the actual authorization statements run.
        $moduleLiteral="'"+(Join-Path $engineRoot 'Tools/Modules').Replace("'","''")+"'"
        $authorize=[scriptblock]::Create((($prefix.Extent.Text -join "`n").Replace('$PSScriptRoot',$moduleLiteral)))
        foreach($phase in @('ReleaseTestBuild','ReleaseTest','Production')){
            $authorized=& {param($Body,$batch,$phase)$Context=@{phase=$phase;batch=$batch};. $Body;return ($main -or $candidate)} $authorize $batch $phase
            Assert-Equal ($phase -ceq 'ReleaseTestBuild') $authorized
        }
        Assert-Refused {& {param($Body,$batch)$Context=@{phase='ReleaseTestBuild';batch=$batch};. $Body} $authorize $without}
        $env:GITHUB_REF='refs/heads/main'
        $mainProduction=& {param($Body)$Context=@{phase='Production';batch=@{}};. $Body;return ($main -and -not $candidate)} $authorize
        Assert-True $mainProduction
    }finally{foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}}
}

function New-MergeGroupFixture([string]$Name,[switch]$Prose){
    $f=New-CandidateFixture $Name -Prose:$Prose
    $f.event=@{action='checks_requested';repository=@{full_name='RedSalamanders/RedMonitor'};
        merge_group=@{base_ref='refs/heads/main';base_sha=$f.base;head_ref='refs/heads/gh-readonly-queue/main/pr-43-fixture';head_sha=$f.merge}}
    return $f
}
Invoke-Case 'Manual candidate shadow execution keeps isolated read-only test roles and original attempt evidence' {
    $workflow=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/integration-execution.yml'))
    $caller=[IO.File]::ReadAllText((Join-Path $engineRoot 'Templates/integration-execution.yml'))
    Assert-True ($caller -match '(?m)^  workflow_dispatch:$')
    Assert-True ($caller -notmatch '(?m)^  (pull_request|pull_request_target|push|merge_group|schedule):')
    Assert-True ($caller -match 'cancel-in-progress: false')
    Assert-True ($caller.Contains('native-shadow-${{ github.ref }}-${{ github.run_id }}'))
    foreach($text in @($caller,$workflow)){
        Assert-True ($text -notmatch '(?m)^\s+(contents|actions|statuses|checks|pull-requests): write')
        Assert-True ($text -notmatch 'secrets:|actions/cache/save@|continue-on-error:')
    }
    Assert-True ($workflow -match 'platform: x64\r?\n\s+runner: windows-2025-vs2026')
    Assert-True ($workflow -match 'platform: ARM64\r?\n\s+runner: windows-11-vs2026-arm')
    Assert-True ($workflow.Contains('ref: ${{ github.sha }}'))
    Assert-True ($workflow.Contains('ref: ${{ needs.freeze.outputs.commit }}'))
    Assert-True ($workflow.Contains('if: needs.freeze.outputs.native_required == ''true'''))
    Assert-True ($workflow.Contains('clear;files,${{ github.workspace }}/.build/ci/vcpkg-cache,read'))
    Assert-True ($workflow -notmatch '-Phase (Production|Qualification)|Invoke-Admission|Complete-PrCheck|Write-CiState|Set-CiQualificationStatus')
    foreach($artifact in @('candidate-inputs-${{ github.run_attempt }}','candidate-regression-${{ matrix.platform }}-${{ github.run_attempt }}','candidate-profile-${{ matrix.platform }}-${{ github.run_attempt }}',
        'candidate-evidence-${{ matrix.platform }}-${{ github.run_attempt }}','candidate-workspace-evidence-${{ matrix.platform }}-${{ github.run_attempt }}')){
        Assert-True ($workflow.Contains($artifact))
    }
    $build=[regex]::Matches($workflow,' -Phase (ReleaseTestBuild|ReleaseTest) ')
    Assert-Equal 2 $build.Count
    Assert-Equal 'ReleaseTestBuild' $build[0].Groups[1].Value
    Assert-Equal 'ReleaseTest' $build[1].Groups[1].Value
    foreach($extension in @('exe','dll','lib')){Assert-True ($workflow.Contains('.build/${{ matrix.platform }}/Release/**/*.'+$extension))}
}
Invoke-Case 'Actual shadow freeze script retains canonical batch data and refuses mismatched engine or failed acquisition before outputs' {
    $text=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/integration-execution.yml'))
    $match=[regex]::Match($text,'(?ms)^      - name: Reacquire exact candidate from the trusted isolated controller\r?\n.*?^        run: \|\r?\n(?<body>.*?)(?=^      - uses:)')
    Assert-True $match.Success
    $body=[scriptblock]::Create([regex]::Replace($match.Groups['body'].Value,'(?m)^          ',''))
    $controller=New-Fixture 'shadow-freeze-controller'
    Write-FixtureFile $controller 'Tools/Get-CandidateExecutionInputs.ps1' @'
param([string]$Root,[int]$PullRequest,[string]$ExpectedIdentity,[string]$IsolationNonce)
if($PullRequest -ne 43 -or $ExpectedIdentity -cne ('a'*64) -or $IsolationNonce -cne ('b'*32)){throw 'Freeze passed changed acquisition inputs.'}
$Root=(Resolve-Path -LiteralPath $Root).Path
[IO.File]::WriteAllText((Join-Path $Root 'gateway-called.txt'),'recording acquisition boundary; not a native result')
if($env:I61_FREEZE_CONTROL -ceq 'gateway-refusal'){throw 'Recording canonical acquisition refusal.'}
Get-Content (Join-Path $Root 'recording-inputs.json') -Raw
'@
    $null=Invoke-CiGit $controller @('add','Tools/Get-CandidateExecutionInputs.ps1')
    $null=Invoke-CiGit $controller @('commit','-qm','Add recording canonical acquisition boundary')
    $ref=Resolve-CiCommit $controller HEAD
    $names=@('CI_ENGINE_REF','CI_PULL_REQUEST','CI_CANDIDATE_IDENTITY','CI_ISOLATION_NONCE','GITHUB_OUTPUT','I61_FREEZE_CONTROL')
    $saved=@{};foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    try{
        foreach($scenario in @('native','prose','bad-pin','gateway-refusal')){
            $root=New-Fixture ('shadow-freeze-'+$scenario)
            $null=Invoke-CiProcess -FilePath git -Arguments @('clone','--no-hardlinks','--',$controller,(Join-Path $root '.ci-engine')) -WorkingDirectory $root
            $project=Read-CiProject $root;$project.engine.ref=$ref
            Write-FixtureFile $root '.ci/project.json' ($project|ConvertTo-Json -Depth 10)
            $batch=[ordered]@{commit=('c'*40);runId='123';candidateExecution=@{recordingOnly=$true}}
            $inputs=[ordered]@{candidate=@{identity=('a'*64);mergeCommit=('c'*40);nativeRequired=($scenario -cne 'prose')};batch=$batch}
            Write-FixtureFile $root 'recording-inputs.json' ($inputs|ConvertTo-Json -Depth 10)
            $env:CI_ENGINE_REF=if($scenario -ceq 'bad-pin'){'d'*40}else{$ref}
            $env:CI_PULL_REQUEST='43';$env:CI_CANDIDATE_IDENTITY='a'*64;$env:CI_ISOLATION_NONCE='b'*32
            $env:GITHUB_OUTPUT=Join-Path $root 'job-output.txt';$env:I61_FREEZE_CONTROL=$scenario
            Push-Location $root
            try{$passed=$true;try{& $body}catch{$passed=$false}}finally{Pop-Location}
            Assert-Equal ($scenario -in @('native','prose')) $passed
            Assert-Equal ($scenario -cne 'bad-pin') (Test-Path (Join-Path $root 'gateway-called.txt'))
            Assert-Equal $passed (Test-Path (Join-Path $root '.build/ci/batch.json'))
            Assert-Equal $passed (Test-Path $env:GITHUB_OUTPUT)
            if($passed){
                $actual=Get-Content (Join-Path $root '.build/ci/batch.json') -Raw|ConvertFrom-Json -AsHashtable
                Assert-Equal ($batch|ConvertTo-Json -Depth 10 -Compress) ($actual|ConvertTo-Json -Depth 10 -Compress)
                $actual=Get-Content (Join-Path $root '.build/ci/candidate-inputs.json') -Raw|ConvertFrom-Json -AsHashtable
                Assert-Equal ($inputs|ConvertTo-Json -Depth 10 -Compress) ($actual|ConvertTo-Json -Depth 10 -Compress)
                $output=Get-Content $env:GITHUB_OUTPUT -Raw
                Assert-True ($output.Contains('commit='+('c'*40)))
                Assert-True ($output.Contains('native_required='+($scenario -ceq 'native').ToString().ToLowerInvariant()))
            }
        }
    }finally{foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}}
}
Invoke-Case 'Trusted shadow admission creates only an exact main ref and dispatch, preserving preview and race journals' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.CandidateAdmission.psm1')
    $admission=Get-Module Ci.CandidateAdmission
    $originalCommands=& $admission {@{GetMain=(Get-Command Get-CiMainHead).ScriptBlock;GetCandidate=(Get-Command Get-CiIntegrationCandidate).ScriptBlock;Api=(Get-Command Invoke-CiApi).ScriptBlock}}
    $controller=Resolve-CiCommit $engineRoot HEAD
    foreach($scenario in @('native','preview','prose','wrong-identity','caller-blob','pre-create-main','pre-dispatch-candidate','pre-dispatch-ref','dispatch-refusal')){
        $root=New-Fixture ('shadow-admission-'+$scenario)
        $project=Read-CiProject $root;$project.engine.ref=$controller
        Write-FixtureFile $root '.ci/project.json' ($project|ConvertTo-Json -Depth 10)
        Write-FixtureFile $root 'Tools/Invoke-ProjectCi.ps1' "throw 'Admission must not execute product code.'"
        foreach($template in Get-CiProjectWorkflowTemplates $project){
            Write-FixtureFile $root ('.github/workflows/'+$template.Name) ([IO.File]::ReadAllText($template.FullName).Replace('@ENGINE@',$controller).Replace('@OPERATIONS@','Prepare, Release, Winget'))
        }
        Save-Fixture $root 'Trusted main callers'
        $base=Resolve-CiCommit $root HEAD
        $null=Invoke-CiGit $root @('checkout','-b','proposal')
        if($scenario -ceq 'prose'){Write-FixtureFile $root 'README.md' 'Prose proposal.'}else{Write-FixtureFile $root 'src/main.cpp' 'int fixture() { return 2; }'}
        Save-Fixture $root 'Proposal'
        $head=Resolve-CiCommit $root HEAD
        $null=Invoke-CiGit $root @('checkout','main')
        $null=Invoke-CiGit $root @('merge','--no-ff','--no-edit','proposal')
        $merge=Resolve-CiCommit $root HEAD
        $null=Invoke-CiGit $root @('checkout','--detach',$base)
        $pr=@{number=43;state='open';draft=$false;merged=$false;mergeable=$true;
            base=@{ref='main';sha=$base;repo=@{full_name=$project.repository}};head=@{sha=$head;repo=@{full_name=$project.repository}}}
        $candidate=New-CiIntegrationCandidate -Root $root -Repository $project.repository -PullRequest $pr -CurrentMainCommit $base -MergeCommit $merge -ControllerEngineRef $controller
        $blob=(Invoke-CiGit $root @('rev-parse',($base+':.github/workflows/integration-execution.yml'))).stdout.Trim()
        & $admission {
            param($Candidate,$Main,$Blob,$Scenario)
            $script:dispatchControl=@{candidate=$Candidate;main=$Main;blob=$Blob;scenario=$Scenario;acquisitions=0;creates=0;dispatches=0;created=$null}
            function script:Get-CiMainHead {
                param($Repository)
                if($script:dispatchControl.scenario -ceq 'pre-create-main' -and $script:dispatchControl.acquisitions -ge 2){return ('e'*40)}
                $script:dispatchControl.main
            }
            function script:Get-CiIntegrationCandidate {
                param($Root,$PullRequest)
                $script:dispatchControl.acquisitions++
                if($script:dispatchControl.scenario -ceq 'pre-dispatch-candidate' -and $script:dispatchControl.acquisitions -ge 3){
                    $changed=$script:dispatchControl.candidate|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable
                    $changed.identity='f'*64
                    return $changed
                }
                $script:dispatchControl.candidate
            }
            function script:Invoke-CiApi {
                param($Route,$Method='GET',$Body)
                if($Method -ceq 'GET' -and $Route.Contains('/contents/.github/workflows/integration-execution.yml?ref=')){
                    return @{path='.github/workflows/integration-execution.yml';sha=$(if($script:dispatchControl.scenario -ceq 'caller-blob'){'d'*40}else{$script:dispatchControl.blob})}
                }
                if($Method -ceq 'POST' -and $Route.EndsWith('/git/refs')){
                    $script:dispatchControl.creates++
                    if($Body.ref -cnotmatch '^refs/heads/ci-native/pr43/[a-f0-9]{64}/[a-f0-9]{32}$' -or $Body.sha -cne $script:dispatchControl.main){throw 'Admission attempted a foreign ref or candidate checkout.'}
                    $script:dispatchControl.created=@{ref=$Body.ref;object=@{type='commit';sha=$Body.sha}}
                    return $script:dispatchControl.created
                }
                if($Method -ceq 'GET' -and $Route.Contains('/git/ref/heads/ci-native/')){
                    if($script:dispatchControl.scenario -ceq 'pre-dispatch-ref'){return @{ref=$script:dispatchControl.created.ref;object=@{type='commit';sha=('d'*40)}}}
                    return $script:dispatchControl.created
                }
                if($Method -ceq 'POST' -and $Route.EndsWith('/actions/workflows/integration-execution.yml/dispatches')){
                    $script:dispatchControl.dispatches++
                    $expected=$script:dispatchControl.created.ref.Substring(11)
                    if($Body.ref -cne $expected -or $Body.inputs.pull_request -cne '43' -or
                        $Body.inputs.identity -cne $script:dispatchControl.candidate.identity -or
                        -not $expected.EndsWith('/'+$Body.inputs.nonce)){throw 'Dispatch lost original candidate or isolation inputs.'}
                    if($script:dispatchControl.scenario -ceq 'dispatch-refusal'){throw 'Recording dispatch service refusal.'}
                    return $null
                }
                throw 'Unexpected remote operation in recording admission boundary.'
            }
        } $candidate $base $blob $scenario
        try{
            $expected=if($scenario -ceq 'wrong-identity'){'0'*64}else{$candidate.identity}
            $result=$null;$failed=$false
            try{$result=Start-CiCandidateShadow -Root $root -PullRequest 43 -ExpectedIdentity $expected -WhatIf:($scenario -ceq 'preview')}catch{$failed=$true}
            Assert-Equal ($scenario -notin @('native','preview','prose')) $failed
            $observed=& $admission {$script:dispatchControl}
            $writes=$scenario -in @('native','pre-dispatch-candidate','pre-dispatch-ref','dispatch-refusal')
            Assert-Equal ([int]$writes) $observed.creates
            Assert-Equal ([int]($scenario -in @('native','dispatch-refusal'))) $observed.dispatches
            $journals=Join-Path $root '.build/ci/candidate-requests'
            $stages=@(if(Test-Path $journals){Get-ChildItem -LiteralPath $journals -Recurse -File|Select-Object -ExpandProperty Name})
            Assert-Equal ($scenario -in @('native','pre-create-main','pre-dispatch-candidate','pre-dispatch-ref','dispatch-refusal')) ($stages -contains '01-frozen.json')
            Assert-Equal $writes ($stages -contains '02-ref-created.json')
            Assert-Equal ($scenario -ceq 'native') ($stages -contains '03-dispatch-requested.json')
            if($scenario -in @('native','preview','prose')){
                Assert-Equal 0 $result.nativeExecutions
                Assert-True (-not $result.suppliesNativeVerdict)
                Assert-Equal $(switch($scenario){native{'DispatchRequested'};preview{'Preview'};prose{'NoNativeRequired'}}) $result.stage
            }
        }finally{
            & $admission {
                param($Original)
                Set-Item function:script:Get-CiMainHead $Original.GetMain
                Set-Item function:script:Get-CiIntegrationCandidate $Original.GetCandidate
                Set-Item function:script:Invoke-CiApi $Original.Api
                Remove-Variable dispatchControl -Scope Script
            } $originalCommands
        }
    }
}
Invoke-Case 'Merge queue input freeze binds the complete integration tree, cumulative inputs and proposed version' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.MergeGroup.psm1')
    $f=New-MergeGroupFixture 'merge-group-native'
    $d=New-CiMergeGroupInputs -Root $f.root -Repository RedSalamanders/RedMonitor -Event $f.event -CurrentMainCommit $f.base -CurrentGroupCommit $f.merge -ControllerEngineRef ('f'*40)
    Assert-Equal 'MergeGroupInputs' $d.role
    Assert-Equal $f.tree $d.groupTree
    Assert-Equal $f.merge $d.input.commit
    Assert-True $d.nativeRequired
    Assert-Equal (New-CiInputDescriptor $f.root -Ref $f.merge).version $d.input.version
    Assert-CiMergeGroupInputsCurrent -Root $f.root -Descriptor $d -Event $f.event -CurrentMainCommit $f.base -CurrentGroupCommit $f.merge -ControllerEngineRef ('f'*40)
    $batch=(Invoke-CiGit $f.root @('commit-tree',$f.tree,'-p',$f.merge,'-p',$f.head,'-m','Second queued integration')).stdout.Trim()
    $f.event.merge_group.head_sha=$batch
    $next=New-CiMergeGroupInputs -Root $f.root -Repository RedSalamanders/RedMonitor -Event $f.event -CurrentMainCommit $f.base -CurrentGroupCommit $batch -ControllerEngineRef ('f'*40)
    Assert-True ($next.identity -cne $d.identity)
    Assert-Equal $batch $next.groupCommit
}
Invoke-Case 'Merge queue inputs refuse other events, repositories, branches, malformed refs and non-descendant heads' {
    $f=New-MergeGroupFixture 'merge-group-invalid'
    foreach($field in @('action','repository','base_ref','base_sha','head_sha','head_ref','double-slash','trailing-slash','ref-option')){
        $eventData=$f.event|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
        switch($field){
            'action'{$eventData.action='destroyed'};'repository'{$eventData.repository.full_name='outside/project'}
            'base_ref'{$eventData.merge_group.base_ref='refs/heads/feature'};'base_sha'{$eventData.merge_group.base_sha='1'*40}
            'head_sha'{$eventData.merge_group.head_sha='2'*40};'head_ref'{$eventData.merge_group.head_ref='refs/pull/43/merge'}
            'double-slash'{$eventData.merge_group.head_ref='refs/heads/gh-readonly-queue/main/a//b'}
            'trailing-slash'{$eventData.merge_group.head_ref='refs/heads/gh-readonly-queue/main/a/'}
            'ref-option'{$eventData.merge_group.head_ref='--upload-pack=unexpected'}
        }
        Assert-Refused {New-CiMergeGroupInputs -Root $f.root -Repository RedSalamanders/RedMonitor -Event $eventData -CurrentMainCommit $f.base -CurrentGroupCommit $f.merge -ControllerEngineRef ('f'*40)}
    }
    $detached=(Invoke-CiGit $f.root @('commit-tree',$f.tree,'-m','Unrelated root')).stdout.Trim()
    foreach($head in @($detached,$f.base)){
        $f.event.merge_group.head_sha=$head
        Assert-Refused {New-CiMergeGroupInputs -Root $f.root -Repository RedSalamanders/RedMonitor -Event $f.event -CurrentMainCommit $f.base -CurrentGroupCommit $head -ControllerEngineRef ('f'*40)}
    }
}
Invoke-Case 'Merge queue recheck refuses advanced main, replaced queue heads and self-rehashed descriptor changes' {
    $f=New-MergeGroupFixture 'merge-group-drift'
    $d=New-CiMergeGroupInputs -Root $f.root -Repository RedSalamanders/RedMonitor -Event $f.event -CurrentMainCommit $f.base -CurrentGroupCommit $f.merge -ControllerEngineRef ('f'*40)
    Assert-Refused {Assert-CiMergeGroupInputsCurrent -Root $f.root -Descriptor $d -Event $f.event -CurrentMainCommit $f.head -CurrentGroupCommit $f.merge -ControllerEngineRef ('f'*40)}
    Assert-Refused {Assert-CiMergeGroupInputsCurrent -Root $f.root -Descriptor $d -Event $f.event -CurrentMainCommit $f.base -CurrentGroupCommit $f.head -ControllerEngineRef ('f'*40)}
    foreach($field in @('groupTree','groupRef','controllerEngineRef','input','nativeRequired','passed','pullRequests')){
        $changed=$d|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable
        switch($field){'groupTree'{$changed.groupTree='1'*40};'groupRef'{$changed.groupRef+='-replaced'};'controllerEngineRef'{$changed.controllerEngineRef='2'*40};
            'input'{$changed.input.buildNumber++};'nativeRequired'{$changed.nativeRequired=$false};'passed'{$changed.passed=$true};'pullRequests'{$changed.pullRequests=@(43)}}
        $changed.Remove('identity');$changed.identity=Get-CiSha256 ($changed|ConvertTo-Json -Depth 15 -Compress)
        Assert-Refused {Assert-CiMergeGroupInputsCurrent -Root $f.root -Descriptor $changed -Event $f.event -CurrentMainCommit $f.base -CurrentGroupCommit $f.merge -ControllerEngineRef ('f'*40)}
    }
}
Invoke-Case 'Merge queue REST ref parsing refuses another ref, a tag and an invalid commit' {
    $module=Get-Module Ci.MergeGroup
    $ref='refs/heads/gh-readonly-queue/main/pr-43-fixture'
    $valid=@{ref=$ref;object=@{type='commit';sha=('b'*40)}}
    Assert-Equal ('b'*40) (& $module {param($v,$r) Get-CiMergeGroupRefCommit $v $r} $valid $ref)
    foreach($field in @('ref','type','sha')){
        $bad=$valid|ConvertTo-Json -Depth 3|ConvertFrom-Json -AsHashtable
        switch($field){'ref'{$bad.ref='refs/heads/main'};'type'{$bad.object.type='tag'};'sha'{$bad.object.sha='not-a-commit'}}
        Assert-Refused {& $module {param($v,$r) Get-CiMergeGroupRefCommit $v $r} $bad $ref}
    }
}
Invoke-Case 'Prose-only merge queue snapshots grant no baseline success, membership, native execution or adoption' {
    $f=New-MergeGroupFixture 'merge-group-prose' -Prose
    $d=New-CiMergeGroupInputs -Root $f.root -Repository RedSalamanders/RedMonitor -Event $f.event -CurrentMainCommit $f.base -CurrentGroupCommit $f.merge -ControllerEngineRef ('f'*40)
    Assert-True (-not $d.nativeRequired)
    Assert-Equal $d.baseNativeDigest $d.input.nativeDigest
    foreach($field in @('passed','qualified','outcome','executed','adopted','pullRequests')){Assert-True (-not $d.Contains($field))}
    Write-FixtureFile $f.root 'src/must-not-execute.ps1' 'throw "source execution is forbidden"'
    $again=New-CiMergeGroupInputs -Root $f.root -Repository RedSalamanders/RedMonitor -Event $f.event -CurrentMainCommit $f.base -CurrentGroupCommit $f.merge -ControllerEngineRef ('f'*40)
    Assert-Equal $d.identity $again.identity
}

Invoke-Case 'Public merge group acquisition cross-checks real fetched objects and refuses API, ref and controller races' {
    $f=New-MergeGroupFixture 'merge-group-acquisition'
    $bare=Join-Path $runRoot 'merge-group-remote.git'
    $null=Invoke-CiGit $f.root @('clone','--bare',$f.root,$bare)
    $null=Invoke-CiGit $bare @('update-ref','refs/heads/main',$f.base)
    $ref=$f.event.merge_group.head_ref
    $null=Invoke-CiGit $bare @('update-ref',$ref,$f.merge)
    $null=Invoke-CiGit $f.root @('remote','add','origin','https://github.com/RedSalamanders/RedMonitor.git')
    $controller=New-Fixture 'merge-group-clean-controller'
    foreach($path in @('Tools/Modules/Ci.Policy.psm1','Tools/Modules/Ci.GitHub.psm1','Tools/Modules/Ci.MergeGroup.psm1','Schemas/project.schema.json','Schemas/merge-group-inputs.schema.json')){
        Write-FixtureFile $controller $path ([IO.File]::ReadAllText((Join-Path $engineRoot $path)))
    }
    $controllerCommit=Save-Fixture $controller 'Commit exact isolated input controller'
    $module=Import-Module (Join-Path $controller 'Tools/Modules/Ci.MergeGroup.psm1') -Force -PassThru
    try {
        & $module {
            param($fixture,$remoteRoot,$controllerRoot)
            $script:groupControl=@{fixture=$fixture;bare=$remoteRoot;controller=$controllerRoot;mode='';calls=[Collections.Generic.List[object]]::new();git=(Get-Command Invoke-CiGit).ScriptBlock}
            function script:Invoke-CiGit {
                param($Root,[string[]]$Arguments,[switch]$AllowFailure)
                # Substitute only this fixture's network transport. Real Git still fetches and
                # resolves all objects; the production origin check reads its unchanged URL.
                if($Arguments[0] -ceq 'fetch'){
                    if($Arguments[2] -cne 'origin'){throw 'Unexpected fetch transport.'}
                    $Arguments=$Arguments.Clone();$Arguments[2]=$script:groupControl.bare
                }
                & $script:groupControl.git -Root $Root -Arguments $Arguments -AllowFailure:$AllowFailure
            }
            function script:Invoke-CiApi {
                param($Route,$Method='GET')
                $s=$script:groupControl;$s.calls.Add(@{route=$Route;method=$Method})
                $call=$s.calls.Count
                if($Method -cne 'GET'){throw 'Mutation is forbidden.'}
                if($call -eq 3 -and $s.mode -ceq 'controller-change'){[IO.File]::WriteAllText((Join-Path $s.controller 'README.md'),'Controller changed during acquisition')}
                if($Route.EndsWith('/heads/main')){
                    return @{object=@{sha=$(if($call -eq 3 -and $s.mode -ceq 'advanced-main'){$s.fixture.head}else{$s.fixture.base})}}
                }
                if($call -eq 4 -and $s.mode -ceq 'deleted-group'){throw 'Queue ref no longer exists.'}
                if($call -eq 2 -and $s.mode -ceq 'fetch-race'){$null=Invoke-CiGit $s.bare @('update-ref',$s.fixture.event.merge_group.head_ref,$s.fixture.head)}
                return @{ref=$s.fixture.event.merge_group.head_ref;object=@{type='commit';sha=$(if($call -eq 4 -and $s.mode -ceq 'replaced-group'){$s.fixture.head}else{$s.fixture.merge})}}
            }
            function script:Get-CiMainHead {param($Repository) return [string](Invoke-CiApi ('repos/'+$Repository+'/git/ref/heads/main') -Method GET).object.sha}
        } $f $bare $controller
        $d=& $module {param($r,$e) Get-CiMergeGroupInputs -Root $r -Event $e} $f.root $f.event
        Assert-Equal $controllerCommit $d.controllerEngineRef
        Assert-Equal $f.merge $d.groupCommit
        Assert-Equal 4 (& $module {$script:groupControl.calls.Count})
        foreach($mode in @('advanced-main','replaced-group','deleted-group','fetch-race','controller-change')){
            $null=Invoke-CiGit $bare @('update-ref',$ref,$f.merge)
            & $module {param($m) $script:groupControl.mode=$m;$script:groupControl.calls.Clear()} $mode
            Assert-Refused {& $module {param($r,$e) Get-CiMergeGroupInputs -Root $r -Event $e} $f.root $f.event}
            Write-FixtureFile $controller 'README.md' 'Initial prose.'
        }
        Assert-Equal '' (Invoke-CiGit $f.root @('status','--porcelain')).stdout.Trim()
        Assert-Equal $f.head (Resolve-CiCommit $f.root HEAD)
        Assert-Equal 'candidate-feature' (Invoke-CiGit $f.root @('branch','--show-current')).stdout.Trim()
        $refs=(Invoke-CiGit $f.root @('for-each-ref','--format=%(refname)','refs/ci/merge-groups/')).stdout.Trim() -split "`n"
        Assert-Equal 12 $refs.Count
    } finally {Remove-Module $module;Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.MergeGroup.psm1') -Force}
}

Invoke-Case 'Hosted SDK envelopes bind the reviewed workflow, engine, selected native job and server archive digest' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkTransport.psm1')
    $transport=Get-Module Ci.SdkTransport
    $transportPolicy=Get-Content (Join-Path $engineRoot 'Policy/sdk-transport.json') -Raw|ConvertFrom-Json
    $source='f2e328a0a26a18ca66bf4b2aea77bf010c9515e1'
    $run=@{id=123;run_attempt=2;status='completed';conclusion='success';event='workflow_dispatch';head_branch='main';path=$transportPolicy.workflowPath;
        repository=@{full_name='RedSalamanders/DxUi';id=456};head_sha=('a'*40);
        referenced_workflows=@(@{sha=$transportPolicy.engineRef;path=('RedSalamanders/.github/.github/workflows/sdk-inputs.yml@'+$transportPolicy.engineRef)})}
    $jobs=@{total_count=1;jobs=@(@{name='inputs / sdk (x64, windows-2025-vs2026)';status='completed';conclusion='success';run_id=123;run_attempt=2;runner_group_name='GitHub Actions';labels=@('windows-2025-vs2026')})}
    $artifact=@{id=789;name="dependency-sdk-$source-x64-2";expired=$false;digest=('sha256:'+('b'*64));size_in_bytes=1024;
        workflow_run=@{id=123;head_sha=('a'*40);head_branch='main';repository_id=456;head_repository_id=456}}
    $artifacts=@{total_count=1;artifacts=@($artifact)}
    $workflow=@{sha=$transportPolicy.workflowBlob;path=$transportPolicy.workflowPath}
    $snapshot=@{run=$run;jobs=$jobs;artifacts=$artifacts;workflow=$workflow}
    $accepted=& $transport {param($s,$pin) Test-CiHostedSdkEnvelope $s.run $s.jobs $s.artifacts $s.workflow $pin x64 123 2} $snapshot $source
    Assert-Equal 'HostedDependencySdkEnvelope' $accepted.role
    Assert-Equal ('b'*64) $accepted.archiveSha256
    Assert-True (-not $accepted.Contains('passed'))
    foreach($failure in @('running','failed','cancelled','event','branch','repository','attempt','caller','engine','reference','missing-job','native-failed','native-attempt','native-label','native-host','truncated-jobs','truncated-artifacts','duplicate','expired','digest','foreign-artifact','source','size')){
        $bad=$snapshot|ConvertTo-Json -Depth 9|ConvertFrom-Json -AsHashtable
        switch($failure){
            'running'{$bad.run.status='in_progress'};'failed'{$bad.run.conclusion='failure'};'cancelled'{$bad.run.conclusion='cancelled'}
            'event'{$bad.run.event='pull_request'};'branch'{$bad.run.head_branch='feature'};'repository'{$bad.run.repository.full_name='outside/DxUi'}
            'attempt'{$bad.run.run_attempt=3};'caller'{$bad.workflow.sha='0'*40};'engine'{$bad.run.referenced_workflows[0].sha='0'*40}
            'reference'{$bad.run.referenced_workflows[0].path='outside/untrusted.yml@main'};'missing-job'{$bad.jobs.jobs=@();$bad.jobs.total_count=0}
            'native-failed'{$bad.jobs.jobs[0].conclusion='failure'};'native-attempt'{$bad.jobs.jobs[0].run_attempt=1}
            'native-label'{$bad.jobs.jobs[0].labels=@('windows-latest')};'native-host'{$bad.jobs.jobs[0].runner_group_name='foreign'}
            'truncated-jobs'{$bad.jobs.total_count=101};'truncated-artifacts'{$bad.artifacts.total_count=101}
            'duplicate'{$bad.artifacts.artifacts+=@($bad.artifacts.artifacts[0]);$bad.artifacts.total_count=2}
            'expired'{$bad.artifacts.artifacts[0].expired=$true};'digest'{$bad.artifacts.artifacts[0].digest='sha256:not-a-digest'}
            'foreign-artifact'{$bad.artifacts.artifacts[0].workflow_run.head_repository_id=457}
            'source'{$bad.artifacts.artifacts[0].name='dependency-sdk-other-x64-2'};'size'{$bad.artifacts.artifacts[0].size_in_bytes=1GB+1}
        }
        Assert-Refused {& $transport {param($s,$pin) Test-CiHostedSdkEnvelope $s.run $s.jobs $s.artifacts $s.workflow $pin x64 123 2} $bad $source}
    }
}
Invoke-Case 'SDK archive validation refuses traversal, links and case collisions before any extraction' {
    $transport=Get-Module Ci.SdkTransport
    $validRoot=Join-Path $runRoot 'archive-valid';[void][IO.Directory]::CreateDirectory($validRoot)
    $validZip=Join-Path $validRoot 'valid.zip';$zip=[IO.Compression.ZipFile]::Open($validZip,[IO.Compression.ZipArchiveMode]::Create)
    try{
        $entry=$zip.CreateEntry('include/fixture.h');$writer=[IO.StreamWriter]::new($entry.Open())
        try{$writer.Write('verified fixture bytes')}finally{$writer.Dispose()}
    }finally{$zip.Dispose()}
    $destination=Join-Path $validRoot 'out'
    & $transport {param($z,$d) Expand-CiSdkArchive $z $d} $validZip $destination
    Assert-Equal 'verified fixture bytes' ([IO.File]::ReadAllText((Join-Path $destination 'include/fixture.h')))
    Assert-Refused {& $transport {param($z,$d) Expand-CiSdkArchive $z $d} $validZip $destination}
    $envelope=@{archiveBytes=(Get-Item $validZip).Length;archiveSha256=(Get-FileHash $validZip).Hash.ToLowerInvariant()}
    & $transport {param($e,$p) Assert-CiSdkArchiveBytes $e $p} $envelope $validZip
    $bytes=[IO.File]::ReadAllBytes($validZip);$bytes[0]=$bytes[0] -bxor 1;[IO.File]::WriteAllBytes($validZip,$bytes)
    Assert-Refused {& $transport {param($e,$p) Assert-CiSdkArchiveBytes $e $p} $envelope $validZip}
    foreach($badName in @('../escape','/absolute','a\\file','CON.h','A.h')){
        $directory=Join-Path $runRoot ('archive-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
        $zipPath=Join-Path $directory 'bad.zip';$zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
        try{
            [void]$zip.CreateEntry('a.h')
            [void]$zip.CreateEntry($badName)
        }finally{$zip.Dispose()}
        $destination=Join-Path $directory 'extracted'
        Assert-Refused {& $transport {param($z,$d) Expand-CiSdkArchive $z $d} $zipPath $destination}
        Assert-True (-not(Test-Path -LiteralPath $destination))
    }
    $directory=Join-Path $runRoot ('archive-link-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
    $zipPath=Join-Path $directory 'link.zip';$zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
    try{$entry=$zip.CreateEntry('link.h');$entry.ExternalAttributes=([int]0xA000 -shl 16)}finally{$zip.Dispose()}
    Assert-Refused {& $transport {param($z,$d) Expand-CiSdkArchive $z $d} $zipPath (Join-Path $directory 'out')}
}

Invoke-Case 'SDK compatibility misses retain source fallback while source, ABI policy and corruption cannot become hits' {
    $transport=Get-Module Ci.SdkTransport
    $expected=[ordered]@{schemaVersion=1;role='DependencySdkInputs';sourceRepository='RedSalamanders/DxUi';sourceCommit=('a'*40);sourceBytes=('b'*64);apiRevision=4;
        platform='x64';configuration='Release';runtimeFamily='MD';annotationPolicy='enabled';languageStandard='stdcpplatest';optimizationPolicy='GL-LTCG-full';
        toolchainIdentity=('c'*64);compilerProfileIdentity=('d'*64);dependencyIdentity=('e'*64);integrationPolicyIdentity=('f'*64);environmentIdentity=('0'*64)}
    Assert-True (& $transport {param($e,$a) Test-CiSdkTransportRecipe $e $a} $expected $expected)
    foreach($field in @('toolchainIdentity','compilerProfileIdentity','dependencyIdentity','environmentIdentity')){
        $changed=$expected|ConvertTo-Json|ConvertFrom-Json -AsHashtable;$changed[$field]='1'*64
        Assert-True (-not (& $transport {param($e,$a) Test-CiSdkTransportRecipe $e $a} $expected $changed))
    }
    foreach($field in @('sourceCommit','sourceBytes','apiRevision','platform','annotationPolicy','integrationPolicyIdentity')){
        $changed=$expected|ConvertTo-Json|ConvertFrom-Json -AsHashtable
        $changed[$field]=switch($field){sourceCommit{'1'*40};apiRevision{5};platform{'ARM64'};annotationPolicy{'disabled'};default{'1'*64}}
        Assert-Refused {& $transport {param($e,$a) Test-CiSdkTransportRecipe $e $a} $expected $changed}
    }
}
Invoke-Case 'SDK main preparation has explicit distribution and refuses local or compiler-free execution before side effects' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkPreparation.psm1')
    $preparation=Get-Module Ci.SdkPreparation
    $known=& $preparation {Get-CiDistributedSdkRequest f2e328a0a26a18ca66bf4b2aea77bf010c9515e1 4}
    Assert-Equal '42866937316' $known.runId
    Assert-Equal QualifiedAbiV2 $known.contract
    Assert-Equal '42866944166' (& $preparation {Get-CiDistributedSdkRequest 4cdf1ce52c7785446698e346b8aec058ed6a9283 4}).runId
    Assert-Equal '42866951701' (& $preparation {Get-CiDistributedSdkRequest 21fae0dc66000b04504ba7862169533ac2943be8 5}).runId
    Assert-True ($null -eq (& $preparation {Get-CiDistributedSdkRequest 21fae0dc66000b04504ba7862169533ac2943be8 4}))
    $saved=[Environment]::GetEnvironmentVariable('CI_NATIVE_BUILDS_DISABLED','Process')
    try{
        $env:CI_NATIVE_BUILDS_DISABLED='true'
        Assert-Refused {Initialize-CiPinnedSdkInput -Context @{} -SourceCommit f2e328a0a26a18ca66bf4b2aea77bf010c9515e1 -ApiRevision 4}
    }finally{[Environment]::SetEnvironmentVariable('CI_NATIVE_BUILDS_DISABLED',$saved,'Process')}
}

Invoke-Case 'SDK preparation diagnostics retain separate exact requests and outcomes without replacing earlier evidence' {
    $preparation=Get-Module Ci.SdkPreparation
    $fixture=New-Fixture 'sdk-preparation-evidence'
    $context=@{root=$fixture;phase='ReleaseTestBuild';platform='x64'}
    & $preparation {param($c) Write-CiSdkPreparationEvidence $c @{status='Requested';expectedIdentity=@{toolchainIdentity=('a'*64)}}} $context
    & $preparation {param($c) Write-CiSdkPreparationEvidence $c @{status='ExactInputMiss';elapsedMs=123}} $context
    $records=@(Get-ChildItem (Join-Path $fixture '.build/evidence/sdk-input-preparation') -File|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json})
    Assert-Equal 2 $records.Count
    Assert-Equal ('a'*64) @($records|Where-Object {$_.record.status -ceq 'Requested'})[0].record.expectedIdentity.toolchainIdentity
    Assert-Equal 123 @($records|Where-Object {$_.record.status -ceq 'ExactInputMiss'})[0].record.elapsedMs
    foreach($record in $records){Assert-Equal 'ReleaseTestBuild' $record.phase;Assert-Equal 'x64' $record.platform}
}

Invoke-Case 'A successful SDK preparation constructs a complete descriptor accepted by the real reader schema' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkPreparation.psm1')
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkConsumer.psm1')
    $preparation=Get-Module Ci.SdkPreparation;$consumer=Get-Module Ci.SdkConsumer
    $fixture=New-Fixture 'sdk-prepared-descriptor'
    $build=Join-Path $fixture '.build';[void][IO.Directory]::CreateDirectory($build)
    $record=& $preparation {param($b) New-CiPinnedSdkInputDescriptor -SourceCommit ('a'*40) -ApiRevision 4 -Platform x64 `
        -SourceRoot (Join-Path $b 'source') -ToolingRoot (Join-Path $b 'tooling') -StorageEngineRoot (Join-Path $b 'storage') `
        -StoreRoot (Join-Path $b 'store') -ManifestSha256 ('b'*64)} $build
    $path=Join-Path $build 'descriptor.json'
    [IO.File]::WriteAllText($path,($record|ConvertTo-Json))
    $read=& $consumer {param($r,$d) Read-CiLocalSdkDescriptor $r $d} $fixture $path
    Assert-Equal 'LocalPinnedDependencyInput' $read.Value.role
    Assert-Equal ('a'*40) $read.Value.sourceCommit
    Assert-Equal ('b'*64) $read.Value.manifestSha256
    $record.Remove('role')
    [IO.File]::WriteAllText($path,($record|ConvertTo-Json))
    Assert-Refused {& $consumer {param($r,$d) Read-CiLocalSdkDescriptor $r $d} $fixture $path}
}

Invoke-Case 'Portable SDK file references bind complete bytes and roles while surviving relocation and metadata-only changes' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkAbi.psm1')
    $fixture=New-Fixture 'sdk-portable-byte-reference'
    $first=Join-Path $fixture 'first';$second=Join-Path $fixture 'relocated'
    foreach($root in @($first,$second)){
        Write-FixtureFile $root 'include/nested/header.h' 'header A'
        Write-FixtureFile $root 'lib/fixture.lib' 'library A'
    }
    $a=Get-CiPortableSdkFileReference @{Headers=(Join-Path $first 'include');Libraries=(Join-Path $first 'lib')}
    $b=Get-CiPortableSdkFileReference @{Libraries=(Join-Path $second 'lib');Headers=(Join-Path $second 'include')}
    Assert-Equal $a.digest $b.digest
    Assert-Equal 2 $a.files.Count
    Assert-True (-not (($a|ConvertTo-Json -Depth 8).Contains($fixture)))
    $file=Join-Path $second 'include/nested/header.h';$stamp=[IO.File]::GetLastWriteTimeUtc($file)
    [IO.File]::SetLastWriteTimeUtc($file,$stamp.AddDays(-1))
    Assert-Equal $a.digest (Get-CiPortableSdkFileReference @{Headers=(Join-Path $second 'include');Libraries=(Join-Path $second 'lib')}).digest
    [IO.File]::WriteAllText($file,'header B');[IO.File]::SetLastWriteTimeUtc($file,$stamp)
    Assert-True ($a.digest -cne (Get-CiPortableSdkFileReference @{Headers=(Join-Path $second 'include');Libraries=(Join-Path $second 'lib')}).digest)
    Assert-True ($a.digest -cne (Get-CiPortableSdkFileReference @{OtherHeaders=(Join-Path $first 'include');Libraries=(Join-Path $first 'lib')}).digest)
    Write-FixtureFile $second 'include/added.h' 'new input'
    Assert-Equal 3 (Get-CiPortableSdkFileReference @{Headers=(Join-Path $second 'include');Libraries=(Join-Path $second 'lib')}).files.Count
    Assert-Refused {Get-CiPortableSdkFileReference @{Missing=(Join-Path $fixture 'missing')}}
    $empty=Join-Path $fixture 'empty';[void][IO.Directory]::CreateDirectory($empty)
    Assert-Refused {Get-CiPortableSdkFileReference @{Empty=$empty}}
    Assert-Refused {Get-CiPortableSdkFileReference @{Relative='relative'}}
    Assert-Refused {Get-CiPortableSdkFileReference @{Drive=([IO.Path]::GetPathRoot($fixture))}}
    if(-not $IsWindows){
        Write-FixtureFile $second 'include/ADDED.h' 'case collision'
        Assert-Refused {Get-CiPortableSdkFileReference @{Headers=(Join-Path $second 'include')}}
    }
    $link=Join-Path $first 'include/link'
    $kind=if($IsWindows){'Junction'}else{'SymbolicLink'}
    $null=New-Item -ItemType $kind -Path $link -Target (Join-Path $second 'lib')
    Assert-Refused {Get-CiPortableSdkFileReference @{Headers=(Join-Path $first 'include')}}
    Assert-Refused {Get-CiPortableSdkFileReference @{LinkedRoot=$link}}
}

Invoke-Case 'Portable SDK references reject incomplete, duplicate, inconsistent and tampered records without granting admission' {
    $abi=Get-Module Ci.SdkAbi
    $fixture=New-Fixture 'sdk-portable-reference-schema'
    Write-FixtureFile $fixture 'inputs/fixture.h' 'synthetic reference bytes, not a native toolchain'
    $roots=[ordered]@{}
    foreach($role in @('MSBuild','VCTargets','MSVCHeaders','MSVCLibraries','MSVCTools','WindowsHeaders','WindowsLibraries','CRuntimeLibraries','WindowsTools')){$roots[$role]=Join-Path $fixture 'inputs'}
    $files=Get-CiPortableSdkFileReference $roots
    $compiler=[ordered]@{platform='x64';configuration='Release';toolset='v145';vcToolsVersion='14.52.37025';windowsSdkVersion='10.0.26100.0';
        preferredToolArchitecture='x64';vcToolArchitecture='Native64Bit';windowsSdkToolArchitecture='Native64Bit'}
    $reference=& $abi {param($c,$f) New-CiSdkAbiReference -Compiler $c -FileReference $f} $compiler $files
    Assert-CiSdkAbiReference $reference
    $otherStorage=New-Module -Name Ci.SdkCache -ScriptBlock {
        function Test-CiSdkRelativePath {param($Path) throw 'Another pinned storage implementation must not be selected by name.'}
        Export-ModuleMember -Function Test-CiSdkRelativePath
    }
    Import-Module $otherStorage
    try{Assert-CiSdkAbiReference $reference}finally{Remove-Module -ModuleInfo $otherStorage}
    $reordered=$reference|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
    [Array]::Reverse($reordered.fileReference.files)
    Assert-CiSdkAbiReference $reordered
    foreach($mutation in @('missing-role','duplicate-path','header-bytes','compiler','host','unsafe-path','verdict')){
        $changed=$reference|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
        switch($mutation){
            missing-role {$changed.fileReference.files=@($changed.fileReference.files|Select-Object -Skip 1)}
            duplicate-path {$changed.fileReference.files+=@($changed.fileReference.files[0])}
            header-bytes {$changed.fileReference.files[0].sha256='0'*64}
            compiler {$changed.compiler.vcToolsVersion='14.52.99999'}
            host {$changed.compiler.vcToolArchitecture='Native32Bit'}
            unsafe-path {$changed.fileReference.files[0].path='../foreign.h'}
            verdict {$changed.passed=$true}
        }
        Assert-Refused {Assert-CiSdkAbiReference $changed}
    }
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkQualifiedProducer.psm1')
    $sdkReference=[ordered]@{schemaVersion=2;role='QualifiedSdkAbiReference';sourceCommit=('a'*40);sourceBytes=('b'*64);publicHeadersGitTree=('4'*40);apiRevision=4;platform='x64';
        inputKey=('c'*64);manifestSha256=('d'*64);producerTooling=@{commit=('e'*40);contentIdentity=('f'*64)};
        producerStorageEngine=@{commit=('1'*40);contentIdentity=('2'*64)};sdkReceiptSha256=('3'*64);toolchainReference=$reference}
    Assert-CiQualifiedSdkAbiReference $sdkReference
    foreach($mutation in @('architecture','unknown-verdict','invalid-source','nested-verdict')){
        $changed=$sdkReference|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable
        switch($mutation){
            architecture {$changed.platform='ARM64'}
            unknown-verdict {$changed.productPassed=$true}
            invalid-source {$changed.sourceCommit='0'*40}
            nested-verdict {$changed.toolchainReference.passed=$true}
        }
        Assert-Refused {Assert-CiQualifiedSdkAbiReference $changed}
    }
}

Invoke-Case 'Portable SDK ABI evaluation refuses compiler overrides and compiler-free execution before native evaluation' {
    $abi=Get-Module Ci.SdkAbi
    $names=@('CL','_CL_','INCLUDE','LIB','LIBPATH','CI_NATIVE_BUILDS_DISABLED');$original=@{}
    foreach($name in $names){$original[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    try{
        foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
        & $abi {Assert-CiSdkAbiCompilerEnvironment}
        foreach($name in $names){
            [Environment]::SetEnvironmentVariable($name,$(if($name -ceq 'CI_NATIVE_BUILDS_DISABLED'){'true'}else{'controlled unsupported override'}),'Process')
            $message=''
            try{& $abi {Assert-CiSdkAbiCompilerEnvironment}}catch{$message=$_.Exception.Message}
            if($name -ceq 'CI_NATIVE_BUILDS_DISABLED'){Assert-True ($message.Contains('compiler-free'))}else{Assert-True ($message.Contains("the $name compiler environment override"))}
            [Environment]::SetEnvironmentVariable($name,$null,'Process')
        }
    }finally{foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$original[$name],'Process')}}
}

Invoke-Case 'Qualified SDK transport stays disabled before API calls and filesystem side effects' {
    $fixture=New-Fixture 'qualified-sdk-disabled'
    # Keep the disabled-policy control after deployment enables the reviewed path.
    # Run actual copied module bytes in a child; no parent module cache is replaced.
    $controller=Join-Path $fixture 'controller'
    [void][IO.Directory]::CreateDirectory((Join-Path $controller 'Tools'))
    foreach($directory in @('Policy','Schemas')){Copy-Item -LiteralPath (Join-Path $engineRoot $directory) -Destination (Join-Path $controller $directory) -Recurse}
    Copy-Item -LiteralPath (Join-Path $engineRoot 'Tools/Modules') -Destination (Join-Path $controller 'Tools/Modules') -Recurse
    $policyPath=Join-Path $controller 'Policy/sdk-qualified-transport.json'
    $policy=Get-Content $policyPath -Raw|ConvertFrom-Json
    $policy.enabled=$false
    [IO.File]::WriteAllText($policyPath,($policy|ConvertTo-Json))
    $script=Join-Path $fixture 'disabled-child.ps1'
    Write-FixtureFile $fixture 'disabled-child.ps1' @'
param($Fixture,$Controller)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $Controller 'Tools/Modules/Ci.SdkQualifiedTransport.psm1')
Import-Module (Join-Path $Controller 'Tools/Modules/Ci.SdkProducer.psm1')
$transport=Import-Module (Join-Path $Controller 'Tools/Modules/Ci.SdkTransport.psm1') -PassThru
& $transport {function script:Invoke-CiApi {throw 'Unexpected API call before disabled-policy refusal'}}
$producer=Read-CiSdkProducerPolicy;$source=$producer.sources[0]
$message=''
try{Import-CiQualifiedHostedSdkArtifact -RepositoryRoot $Fixture -StoreRoot (Join-Path $Fixture '.build/store') -DownloadRoot (Join-Path $Fixture '.build/downloads') -SourceCommit $source.commit -ApiRevision $source.apiRevision -Platform x64 -RunId 123 -Attempt 1|Out-Null}catch{$message=$_.Exception.Message}
if($message -cne 'Qualified SDK transport is not enabled before its caller and engine are reviewed.'){throw "Unexpected disabled-policy result: $message"}
if(Test-Path (Join-Path $Fixture '.build')){throw 'Disabled policy created SDK output.'}
'@
    $result=Invoke-CiProcess -FilePath (Get-Process -Id $PID).Path -Arguments @('-NoProfile','-NonInteractive','-File',$script,'-Fixture',$fixture,'-Controller',$controller) -WorkingDirectory $fixture -AllowFailure
    Assert-Equal 0 $result.exitCode
    Assert-True (-not(Test-Path -LiteralPath (Join-Path $fixture '.build')))
}

Invoke-Case 'Qualified SDK preparation constructs the actual strict archive-bound reader descriptor' {
    $preparation=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkPreparation.psm1') -PassThru
    $consumer=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkConsumer.psm1') -PassThru
    $fixture=New-Fixture 'qualified-sdk-descriptor-schema'
    $build=Join-Path $fixture '.build';[void][IO.Directory]::CreateDirectory($build)
    $imported=[pscustomobject]@{Entry=[pscustomobject]@{ManifestSha256=('b'*64)};ArchivePath=(Join-Path $build 'artifact.zip');EntryPath='entries/input/version/entry.json';
        ReferencePath='qualified-sdk/abi-reference.json';ReceiptPath='receipts/DxUi-SDK-0.1.123-x64.zip.receipt.json'}
    $record=& $preparation {param($b,$i) New-CiQualifiedSdkInputDescriptor -SourceCommit ('a'*40) -ApiRevision 4 -Platform x64 -SourceRoot (Join-Path $b 'source') `
        -ToolingRoot (Join-Path $b 'tooling') -StorageEngineRoot (Join-Path $b 'storage') -StoreRoot (Join-Path $b 'store') -ProducerRun 123 -Attempt 1 -Imported $i} $build $imported
    $path=Join-Path $build 'descriptor.json';[IO.File]::WriteAllText($path,($record|ConvertTo-Json))
    $read=& $consumer {param($r,$p) Read-CiLocalSdkDescriptor $r $p} $fixture $path
    Assert-Equal HostedQualifiedDependencyInput $read.Value.role
    Assert-Equal $imported.ArchivePath $read.Value.archivePath
    foreach($mutation in @('unknown-verdict','missing-receipt','zero-attempt','wrong-role')){
        $changed=$record|ConvertTo-Json|ConvertFrom-Json -AsHashtable
        switch($mutation){unknown-verdict{$changed.passed=$true};missing-receipt{$changed.Remove('receiptPath')};zero-attempt{$changed.attempt=0};wrong-role{$changed.role='LocalPinnedDependencyInput'}}
        [IO.File]::WriteAllText($path,($changed|ConvertTo-Json))
        Assert-Refused {& $consumer {param($r,$p) Read-CiLocalSdkDescriptor $r $p} $fixture $path}
    }
}

Invoke-Case 'Qualified SDK witnesses bind actual compiler roots and reject downgrade, changed tools, missing metadata and closed owners' {
    $consumer=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkConsumer.psm1') -PassThru
    $fixture=New-Fixture 'qualified-sdk-actual-tool-binding'
    $build=Join-Path $fixture '.build';[void][IO.Directory]::CreateDirectory($build)
    $expected=[ordered]@{PlatformToolset='v145';VCToolsVersion='14.52.37025';WindowsTargetPlatformVersion='10.0.26100.0';
        PreferredToolArchitecture='x64';VCToolArchitecture='Native64Bit';WindowsSDKToolArchitecture='Native64Bit';
        VCToolsInstallDir=(Join-Path $build 'msvc');WindowsSdkDir=(Join-Path $build 'windows');VCTargetsPath=(Join-Path $build 'targets');MSBuildBinPath=(Join-Path $build 'msbuild');
        IncludePath=((Join-Path $build "msvc/include's")+';'+(Join-Path $build 'windows/include')+';');LibraryPath=((Join-Path $build 'msvc/lib')+';');ReferencePath=((Join-Path $build 'msvc/references')+';');
        CL=(Join-Path $build 'msvc/bin/cl.exe');Link=(Join-Path $build 'msvc/bin/link.exe');Lib=(Join-Path $build 'msvc/bin/lib.exe');FXC=(Join-Path $build 'windows/bin/fxc.exe')}
    $actual=@{};foreach($name in @('PlatformToolset','VCToolsInstallDir','VCToolsVersion','WindowsSdkDir','WindowsTargetPlatformVersion','PreferredToolArchitecture','VCTargetsPath','VCToolArchitecture','WindowsSDKToolArchitecture','MSBuildBinPath')){$actual[$name]=$expected[$name]}
    foreach($name in @('IncludePath','LibraryPath','ReferencePath')){$actual[$name]=$expected[$name].Replace(';','|')}
    foreach($name in @('CLToolPath','CLToolExe','CLToolArchitecture','LinkToolPath','LinkToolExe','LinkToolArchitecture','LibToolPath','LibToolExe','LibToolArchitecture','FXCToolPath','FxCompileToolExe','FxCompileToolArchitecture','MultiProcFXC')){$actual[$name]=''}
    $propertyPath=Join-Path $build 'actual-tools.txt'
    $payload=Join-Path $build 'sdk'
    $witness=& $consumer {param($r,$s,$b) New-CiSdkConsumerWitness $r $s x64 $b} $fixture $payload $expected
    $names=@('CI_NATIVE_BUILDS_DISABLED','CL','_CL_','INCLUDE','LIB','LIBPATH');$saved=@{}
    foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process');[Environment]::SetEnvironmentVariable($name,$null,'Process')}
    try{
        [IO.File]::WriteAllLines($propertyPath,[string[]]@($actual.Keys|Sort-Object|ForEach-Object {$_+'='+$actual[$_]}),[Text.UTF8Encoding]::new($false))
        Assert-CiSdkConsumerLease -ProjectRoot $fixture -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release -SdkContract QualifiedAbiV2 -ToolPropertyFile $propertyPath
        $environmentPaths=@{INCLUDE='IncludePath';LIB='LibraryPath';LIBPATH='ReferencePath'}
        foreach($name in $environmentPaths.Keys){[Environment]::SetEnvironmentVariable($name,$expected[$environmentPaths[$name]],'Process')}
        Assert-CiSdkConsumerLease -ProjectRoot $fixture -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release -SdkContract QualifiedAbiV2 -ToolPropertyFile $propertyPath
        $command=Join-Path $engineRoot 'Tools/Test-SdkConsumerLease.ps1'
        $arguments=@('-NoProfile','-NonInteractive','-File',$command,'-ProjectRoot',$fixture,'-LeasePath',$witness.Path,'-SdkRoot',$payload,'-Platform','x64','-Configuration','Release','-SdkContract','QualifiedAbiV2','-ToolPropertyFile',$propertyPath)
        $child=Invoke-CiProcess (Get-Process -Id $PID).Path $arguments $engineRoot -AllowFailure
        Assert-True ($child.exitCode -eq 0) $child.stderr
        $ownedInclude=Join-Path $build "source header's"
        [void][IO.Directory]::CreateDirectory($ownedInclude)
        $changed=$actual|ConvertTo-Json|ConvertFrom-Json -AsHashtable
        $changed.IncludePath+='|'+$ownedInclude
        [IO.File]::WriteAllLines($propertyPath,[string[]]@($changed.Keys|Sort-Object|ForEach-Object {$_+'='+$changed[$_]}))
        $env:INCLUDE=$changed.IncludePath.Replace('|',';')
        Assert-CiSdkConsumerLease -ProjectRoot $fixture -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release -SdkContract QualifiedAbiV2 -ToolPropertyFile $propertyPath
        foreach($bad in @(($ownedInclude+'|'+$actual.IncludePath),($actual.IncludePath+'|'+$engineRoot))){
            $changed.IncludePath=$bad
            [IO.File]::WriteAllLines($propertyPath,[string[]]@($changed.Keys|Sort-Object|ForEach-Object {$_+'='+$changed[$_]}))
            $env:INCLUDE=$bad.Replace('|',';')
            Assert-Refused {Assert-CiSdkConsumerLease -ProjectRoot $fixture -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release -SdkContract QualifiedAbiV2 -ToolPropertyFile $propertyPath}
        }
        $env:INCLUDE=$expected.IncludePath
        [IO.File]::WriteAllLines($propertyPath,[string[]]@($actual.Keys|Sort-Object|ForEach-Object {$_+'='+$actual[$_]}))
        Assert-Refused {Assert-CiSdkConsumerLease -ProjectRoot $fixture -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release}
        foreach($field in @('VCToolsVersion','VCToolsInstallDir','WindowsTargetPlatformVersion','WindowsSdkDir','VCTargetsPath','MSBuildBinPath','CLToolPath','CLToolExe','LinkToolExe','LibToolPath','FXCToolPath','FxCompileToolArchitecture','IncludePath','LibraryPath','ReferencePath')){
            $changed=$actual|ConvertTo-Json|ConvertFrom-Json -AsHashtable;$changed[$field]='controlled-incompatible-value'
            [IO.File]::WriteAllLines($propertyPath,[string[]]@($changed.Keys|Sort-Object|ForEach-Object {$_+'='+$changed[$_]}))
            Assert-Refused {Assert-CiSdkConsumerLease -ProjectRoot $fixture -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release -SdkContract QualifiedAbiV2 -ToolPropertyFile $propertyPath}
        }
        $changed=$actual|ConvertTo-Json|ConvertFrom-Json -AsHashtable;$changed.Remove('CLToolPath')
        [IO.File]::WriteAllLines($propertyPath,[string[]]@($changed.Keys|Sort-Object|ForEach-Object {$_+'='+$changed[$_]}))
        Assert-Refused {Assert-CiSdkConsumerLease -ProjectRoot $fixture -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release -SdkContract QualifiedAbiV2 -ToolPropertyFile $propertyPath}
        [IO.File]::WriteAllLines($propertyPath,[string[]]@($actual.Keys|Sort-Object|ForEach-Object {$_+'='+$actual[$_]}))
        foreach($name in $environmentPaths.Keys){
            [Environment]::SetEnvironmentVariable($name,(Join-Path $build 'unqualified-search-override'),'Process')
            Assert-Refused {Assert-CiSdkConsumerLease -ProjectRoot $fixture -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release -SdkContract QualifiedAbiV2 -ToolPropertyFile $propertyPath}
            [Environment]::SetEnvironmentVariable($name,$expected[$environmentPaths[$name]],'Process')
        }
        $env:CL='/controlled-backend-override'
        Assert-Refused {Assert-CiSdkConsumerLease -ProjectRoot $fixture -LeasePath $witness.Path -SdkRoot $payload -Platform x64 -Configuration Release -SdkContract QualifiedAbiV2 -ToolPropertyFile $propertyPath}
    }finally{
        $witness.Stream.Dispose()
        foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
    }
    $child=Invoke-CiProcess (Get-Process -Id $PID).Path $arguments $engineRoot -AllowFailure
    Assert-True ($child.exitCode -ne 0)
}

Invoke-Case 'Qualified SDK import binds original entry and reference from held archive bytes and preserves all v1 identities' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkCache.psm1')
    $qualified=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkQualifiedTransport.psm1') -PassThru
    $transport=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkTransport.psm1') -PassThru
    $abi=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkAbi.psm1') -PassThru
    $fixture=New-Fixture 'qualified-sdk-archive-binding';$policy=Read-CiSdkProducerPolicy;$source=$policy.sources[0]
    $tooling=[ordered]@{repository='RedSalamanders/DxUi';commit=$policy.toolingRef;contentIdentity=$policy.toolingContentIdentity}
    $identity=[ordered]@{schemaVersion=1;role='DependencySdkInputs';sourceRepository='RedSalamanders/DxUi';sourceCommit=$source.commit;sourceBytes=$source.contentIdentity;apiRevision=$source.apiRevision;
        platform='x64';configuration='Release';runtimeFamily='MD';annotationPolicy='enabled';languageStandard='stdcpplatest';optimizationPolicy='GL-LTCG-full';
        toolchainIdentity=('c'*64);compilerProfileIdentity=('d'*64);dependencyIdentity=('e'*64);environmentIdentity=('0'*64);
        integrationPolicyIdentity=(Get-CiSha256 ('dxui-sdk-input-policy-v1'+"`n"+($tooling|ConvertTo-Json -Compress)))}
    Write-FixtureFile $fixture '.build/payload/fixture.lib' 'synthetic input bytes, not a native SDK'
    $sourceStore=Join-Path $fixture '.build/source-store';Initialize-CiSdkStore $fixture $sourceStore
    $published=Publish-CiSdkCacheEntry $sourceStore $identity (Join-Path $fixture '.build/payload')
    $entryPath=Join-Path $sourceStore ("entries/$($published.Key.Substring(0,16))/$($published.ManifestSha256.Substring(0,16))/entry.json")
    $entry=Get-Content $entryPath -Raw|ConvertFrom-Json -AsHashtable
    Write-FixtureFile $fixture '.build/tool-reference/fixture.h' 'synthetic reference data, not a compiler'
    $roots=[ordered]@{}
    foreach($role in @('MSBuild','VCTargets','MSVCHeaders','MSVCLibraries','MSVCTools','WindowsHeaders','WindowsLibraries','CRuntimeLibraries','WindowsTools')){$roots[$role]=Join-Path $fixture '.build/tool-reference'}
    $files=Get-CiPortableSdkFileReference $roots
    $compiler=[ordered]@{platform='x64';configuration='Release';toolset='v145';vcToolsVersion='14.52.37025';windowsSdkVersion='10.0.26100.0';
        preferredToolArchitecture='x64';vcToolArchitecture='Native64Bit';windowsSdkToolArchitecture='Native64Bit'}
    $toolReference=& $abi {param($c,$f) New-CiSdkAbiReference $c $f} $compiler $files
    $receipt=[ordered]@{schemaVersion=1;kind='sdk';version='0.1.123';source=$source.commit;apiRevision=$source.apiRevision;platform='x64';configuration='Release';runtime='MD';testsIncluded=$false;
        smokePassed=$true;producerPdbIsolationPassed=$true;missingPackagedPdbControlPassed=$true;licenseClosurePassed=$true;firstPartyWarningControlPassed=$true;headerClosurePassed=$true;
        sdkStoreInputKey=$published.Key;sdkStoreManifestSha256=$published.ManifestSha256}
    $receiptJson=$receipt|ConvertTo-Json
    $receiptSha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($receiptJson))).ToLowerInvariant()
    Assert-CiQualifiedSdkReceipt $receipt $source.commit $source.apiRevision x64 0.1.123
    foreach($gate in @('smokePassed','producerPdbIsolationPassed','missingPackagedPdbControlPassed','licenseClosurePassed','firstPartyWarningControlPassed','headerClosurePassed')){
        $badReceipt=$receipt|ConvertTo-Json|ConvertFrom-Json -AsHashtable;$badReceipt[$gate]=$false
        Assert-Refused {Assert-CiQualifiedSdkReceipt $badReceipt $source.commit $source.apiRevision x64 0.1.123}
    }
    $reference=[ordered]@{schemaVersion=2;role='QualifiedSdkAbiReference';sourceCommit=$source.commit;sourceBytes=$source.contentIdentity;publicHeadersGitTree=('4'*40);apiRevision=$source.apiRevision;platform='x64';
        inputKey=$published.Key;manifestSha256=$published.ManifestSha256;producerTooling=@{commit=$policy.toolingRef;contentIdentity=$policy.toolingContentIdentity};
        producerStorageEngine=@{commit=$policy.storageEngineRef;contentIdentity=$policy.storageEngineContentIdentity};sdkReceiptSha256=$receiptSha;toolchainReference=$toolReference}
    & $qualified {param($e,$r,$h,$s,$a) Assert-CiQualifiedSdkBinding $e $r $h $s $a x64} $entry $reference $published.ManifestSha256 $source.commit $source.apiRevision
    foreach($change in @('entry-key','reference-key','reference-manifest','tooling','source-bytes','integration')){
        $e=$entry|ConvertTo-Json -Depth 10|ConvertFrom-Json -AsHashtable;$r=$reference|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable
        switch($change){
            entry-key {$e.key='1'*64}
            reference-key {$r.inputKey='1'*64}
            reference-manifest {$r.manifestSha256='1'*64}
            tooling {$r.producerTooling.commit='1'*40}
            source-bytes {$e.identity.sourceBytes='1'*64;$r.sourceBytes='1'*64;$e.key=Get-CiSdkCacheKey $e.identity;$r.inputKey=$e.key}
            integration {$e.identity.integrationPolicyIdentity='1'*64;$e.key=Get-CiSdkCacheKey $e.identity;$r.inputKey=$e.key}
        }
        Assert-Refused {& $qualified {param($e,$r,$h,$s,$a) Assert-CiQualifiedSdkBinding $e $r $h $s $a x64} $e $r $published.ManifestSha256 $source.commit $source.apiRevision}
    }
    $package=Join-Path $fixture '.build/package';[void][IO.Directory]::CreateDirectory($package)
    Copy-Item -LiteralPath (Join-Path $sourceStore 'entries') -Destination (Join-Path $package 'entries') -Recurse
    Write-FixtureFile $package 'qualified-sdk/abi-reference.json' ($reference|ConvertTo-Json -Depth 12)
    Write-FixtureFile $package 'receipts/DxUi-SDK-0.1.123-x64.zip.receipt.json' $receiptJson
    $zip=Join-Path $fixture '.build/qualified.zip';[IO.Compression.ZipFile]::CreateFromDirectory($package,$zip)
    $probe=@{zip=$zip;mutation='';calls=0;envelope=[ordered]@{schemaVersion=2;role='HostedQualifiedSdkEnvelope';contract='QualifiedAbiV2';sourceCommit=$source.commit;
        platform='x64';runId='123';archiveBytes=(Get-Item $zip).Length;archiveSha256=(Get-FileHash $zip).Hash.ToLowerInvariant()}}
    $resolve=& $qualified {(Get-Command Resolve-CiQualifiedSdkArtifactEnvelope).ScriptBlock}
    $receive=& $transport {(Get-Command Receive-CiSdkArchive).ScriptBlock};$expand=& $transport {(Get-Command Expand-CiSdkArchive).ScriptBlock}
    try{
        & $qualified {param($p) $script:qualifiedProbe=$p;function script:Resolve-CiQualifiedSdkArtifactEnvelope {
            param($RunId,$Attempt,$SourceCommit,$Platform)
            $script:qualifiedProbe.calls++
            $result=$script:qualifiedProbe.envelope|ConvertTo-Json|ConvertFrom-Json -AsHashtable
            if($script:qualifiedProbe.mutation -ceq 'provenance' -and $script:qualifiedProbe.calls -gt 1){$result.archiveSha256='0'*64}
            return $result
        }} $probe
        & $transport {param($p,$x) $script:qualifiedProbe=$p;$script:qualifiedExpand=$x
            function script:Receive-CiSdkArchive {param($Envelope,$Destination)
                [IO.File]::Copy($script:qualifiedProbe.zip,$Destination,$false)
                if($script:qualifiedProbe.mutation -ceq 'archive'){$bytes=[IO.File]::ReadAllBytes($Destination);$bytes[0]=$bytes[0] -bxor 1;[IO.File]::WriteAllBytes($Destination,$bytes)}
            }
            function script:Expand-CiSdkArchive {param($Archive,$Destination,$Envelope)
                $catalog=& $script:qualifiedExpand @PSBoundParameters
                $name=switch($script:qualifiedProbe.mutation){entry{'entry.json'};reference{'abi-reference.json'};receipt{'DxUi-SDK-0.1.123-x64.zip.receipt.json'};default{''}}
                if($name){$file=Get-ChildItem $Destination -Recurse -File -Filter $name;[IO.File]::WriteAllText($file.FullName,'{}')}
                return $catalog
            }
        } $probe $expand
        $imported=Import-CiQualifiedHostedSdkArtifact $fixture (Join-Path $fixture '.build/destination') (Join-Path $fixture '.build/downloads') $source.commit $source.apiRevision x64 123 1
        Assert-Equal $published.Key $imported.Entry.Key;Assert-Equal $published.ManifestSha256 $imported.Entry.ManifestSha256
        foreach($mutation in @('archive','entry','reference','receipt','provenance')){
            $probe.mutation=$mutation;$probe.calls=0;$store=Join-Path $fixture ('.build/refused-'+$mutation);$message=''
            try{Import-CiQualifiedHostedSdkArtifact $fixture $store (Join-Path $fixture '.build/downloads') $source.commit $source.apiRevision x64 123 1|Out-Null}catch{$message=$_.Exception.Message}
            $expected=switch($mutation){archive{'SDK archive changed before extraction.'};provenance{'Qualified SDK artifact provenance changed during transport.'};default{'Extracted qualified SDK binding changed after authenticated acquisition.'}}
            Assert-Equal $expected $message;Assert-True (-not(Test-Path -LiteralPath $store))
        }
    }finally{
        & $qualified {param($s) Set-Item function:script:Resolve-CiQualifiedSdkArtifactEnvelope $s} $resolve
        & $transport {param($r,$x) Set-Item function:script:Receive-CiSdkArchive $r;Set-Item function:script:Expand-CiSdkArchive $x} $receive $expand
    }
}

Invoke-Case 'Public SDK import binds the held authenticated archive and refuses post-transfer or extracted-manifest substitution' {
    Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.SdkCache.psm1')
    $transport=Get-Module Ci.SdkTransport
    $fixture=New-Fixture 'sdk-transport-boundary'
    $payload=Join-Path $fixture '.build/payload';[void][IO.Directory]::CreateDirectory($payload)
    [IO.File]::WriteAllText((Join-Path $payload 'fixture.lib'),'synthetic input bytes, not a native SDK')
    $identity=[ordered]@{schemaVersion=1;role='DependencySdkInputs';sourceRepository='RedSalamanders/DxUi';sourceCommit=('a'*40);sourceBytes=('b'*64);apiRevision=4;
        platform='x64';configuration='Release';runtimeFamily='MD';annotationPolicy='enabled';languageStandard='stdcpplatest';optimizationPolicy='GL-LTCG-full';
        toolchainIdentity=('c'*64);compilerProfileIdentity=('d'*64);dependencyIdentity=('e'*64);integrationPolicyIdentity=('f'*64);environmentIdentity=('0'*64)}
    $store=Join-Path $fixture '.build/source-store';Initialize-CiSdkStore $fixture $store
    $published=Publish-CiSdkCacheEntry $store $identity $payload
    $zip=Join-Path $fixture '.build/source.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $store 'entries'),$zip)
    $envelope=[ordered]@{archiveBytes=(Get-Item $zip).Length;archiveSha256=(Get-FileHash $zip).Hash.ToLowerInvariant()}
    $originals=@{};foreach($name in @('Resolve-CiHostedSdkArtifact','Receive-CiSdkArchive','Expand-CiSdkArchive')){
        $originals[$name]=& $transport {param($n) (Get-Command $n).ScriptBlock} $name
    }
    try{
        & $transport {
            param($z,$e,$expand)
            $script:transportControl=@{zip=$z;envelope=$e;corrupt='';expand=$expand}
            function script:Resolve-CiHostedSdkArtifact {param($RunId,$Attempt,$SourceCommit,$Platform) return $script:transportControl.envelope}
            function script:Receive-CiSdkArchive {
                param($Envelope,$Destination)
                [IO.File]::Copy($script:transportControl.zip,$Destination,$false)
                if($script:transportControl.corrupt -ceq 'archive'){
                    $b=[IO.File]::ReadAllBytes($Destination);$b[0]=$b[0] -bxor 1;[IO.File]::WriteAllBytes($Destination,$b)
                }
            }
            function script:Expand-CiSdkArchive {
                param($Archive,$Destination,$Envelope)
                $catalog=& $script:transportControl.expand @PSBoundParameters
                if($script:transportControl.corrupt -ceq 'manifest'){
                    $manifest=Get-ChildItem $Destination -Recurse -File -Filter entry.json
                    [IO.File]::WriteAllText($manifest.FullName,'{}')
                }
                return $catalog
            }
        } $zip $envelope $originals['Expand-CiSdkArchive']
        $destination=Join-Path $fixture '.build/destination-store'
        $imported=Import-CiHostedSdkArtifact $fixture $destination (Join-Path $fixture '.build/downloads') $identity 123 1
        Assert-Equal $published.ManifestSha256 $imported.ManifestSha256
        foreach($failure in @('archive','manifest')){
            & $transport {param($f) $script:transportControl.corrupt=$f} $failure
            $message=''
            try{Import-CiHostedSdkArtifact $fixture $destination (Join-Path $fixture '.build/downloads') $identity 123 1|Out-Null}catch{$message=$_.Exception.Message}
            $expected=if($failure -ceq 'archive'){'SDK archive changed before extraction.'}else{'Extracted SDK manifest changed after authenticated acquisition.'}
            Assert-Equal $expected $message
        }
        & $transport {$script:transportControl.corrupt=''}
        $other=$identity|ConvertTo-Json|ConvertFrom-Json -AsHashtable;$other.environmentIdentity='1'*64
        $missStore=Join-Path $fixture '.build/miss-store'
        $miss=Import-CiHostedSdkArtifact $fixture $missStore (Join-Path $fixture '.build/downloads') $other 123 1
        Assert-True ($null -eq $miss)
        Assert-True (-not(Test-Path $missStore))
        $reports=@(Get-ChildItem (Join-Path $fixture '.build/evidence/sdk-recipe-misses') -File)
        Assert-Equal 1 $reports.Count
        $diagnostic=Get-Content $reports[0].FullName -Raw|ConvertFrom-Json
        Assert-Equal 'environmentIdentity' ($diagnostic.differentFields -join ',')
        Assert-Equal ('1'*64) $diagnostic.expected.environmentIdentity
        Assert-Equal ('0'*64) $diagnostic.observed.environmentIdentity
        Assert-True (-not $diagnostic.suppliesDependencyBytes)
    }finally{
        & $transport {param($saved) foreach($name in $saved.Keys){Set-Item ("Function:script:"+$name) -Value $saved[$name]};Remove-Variable transportControl -Scope Script} $originals
    }
}

Invoke-Case 'Branch cache diagnostic permits only its frozen isolated writer and independent main reader' {
    $text=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/integration-branch-capability.yml'))
    $match=[regex]::Match($text,'(?ms)^      - name: Validate the exact owned branch and immutable controller\r?\n.*?^        run: \|\r?\n(?<body>.*?)(?=^      - name:)')
    Assert-True $match.Success
    $body=[scriptblock]::Create([regex]::Replace($match.Groups['body'].Value,'(?m)^          ',''))
    $baseline=@{PROBE_MODE='write';ISOLATION_REF=('refs/heads/ci-integration-probe/'+('a'*32));
        PROBE_PLATFORM='linux';PROBE_KEY=('integration-branch-'+('a'*32)+'-linux');EXPECTED_COMMIT=('b'*40);ACTUAL_COMMIT=('b'*40);
        ACTUAL_REF=('refs/heads/ci-integration-probe/'+('a'*32))}
    $saved=@{};foreach($name in $baseline.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    try{
        $controls=@(
            @{change=@{};pass=$true},
            @{change=@{PROBE_MODE='read';ACTUAL_REF='refs/heads/main'};pass=$true},
            @{change=@{ACTUAL_REF='refs/heads/main'};pass=$false},
            @{change=@{PROBE_MODE='read'};pass=$false},
            @{change=@{ACTUAL_COMMIT=('c'*40)};pass=$false},
            @{change=@{EXPECTED_COMMIT=('B'*40);ACTUAL_COMMIT=('B'*40)};pass=$false},
            @{change=@{PROBE_KEY=('integration-branch-'+('c'*32)+'-linux')};pass=$false},
            @{change=@{PROBE_PLATFORM='x64';PROBE_KEY=('integration-branch-'+('a'*32)+'-x64')};pass=$true},
            @{change=@{PROBE_PLATFORM='ARM64';PROBE_KEY=('integration-branch-'+('a'*32)+'-ARM64')};pass=$true},
            @{change=@{PROBE_PLATFORM='arm64'};pass=$false},
            @{change=@{PROBE_PLATFORM='self-hosted'};pass=$false},
            @{change=@{PROBE_MODE='WRITE'};pass=$false},
            @{change=@{ISOLATION_REF='refs/heads/main';ACTUAL_REF='refs/heads/main'};pass=$false},
            @{change=@{ISOLATION_REF=('refs/heads/ci-integration-probe/'+('A'*32))};pass=$false}
        )
        foreach($control in $controls){
            foreach($name in $baseline.Keys){[Environment]::SetEnvironmentVariable($name,$baseline[$name],'Process')}
            foreach($name in $control.change.Keys){[Environment]::SetEnvironmentVariable($name,$control.change[$name],'Process')}
            $passed=$true;try{& $body}catch{$passed=$false}
            Assert-Equal $control.pass $passed
        }
    }finally{foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}}
    Assert-True ($text -notmatch '(?m)^\s+(contents|actions|statuses|checks): write')
    Assert-True ($text -notmatch 'actions/checkout|Invoke-ProjectCi|build\.ps1')
}

Invoke-Case 'Actual branch cache observer retains refusals for failed saves, foreign scopes and leaked restores' {
    $text=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/integration-branch-capability.yml'))
    $match=[regex]::Match($text,'(?ms)^      - name: Independently observe repository cache scope and actual restore\r?\n.*?^        run: \|\r?\n(?<body>.*?)(?=^      - name:)')
    Assert-True $match.Success
    $body=[scriptblock]::Create([regex]::Replace($match.Groups['body'].Value,'(?m)^          ',''))
    $fixture=New-Fixture 'branch-cache-observer'
    $baseline=@{PROBE_MODE='write';ISOLATION_REF=('refs/heads/ci-integration-probe/'+('a'*32));
        PROBE_PLATFORM='linux';PROBE_KEY=('integration-branch-'+('a'*32)+'-linux');EXPECTED_COMMIT=('b'*40);ACTUAL_COMMIT=('b'*40);
        ACTUAL_REF=('refs/heads/ci-integration-probe/'+('a'*32));SAVE_OUTCOME='success';RESTORE_OUTCOME='success';
        CACHE_HIT='true';MATCHED_KEY=('integration-branch-'+('a'*32)+'-linux');RUNNER_TEMP='';RUNNER_OS='Linux';RUNNER_ARCH='X64';
        GITHUB_REPOSITORY='RedSalamanders/.github';GITHUB_RUN_ID='123';GITHUB_RUN_ATTEMPT='1'}
    $saved=@{};foreach($name in $baseline.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    try{
        foreach($scenario in @('writer','reader','save-skipped','restore-failed','foreign-scope','bad-bytes','reader-hit','reader-file')){
            foreach($name in $baseline.Keys){[Environment]::SetEnvironmentVariable($name,$baseline[$name],'Process')}
            $env:RUNNER_TEMP=Join-Path $fixture $scenario
            $folder=Join-Path $env:RUNNER_TEMP 'integration-branch-capability'
            [void][IO.Directory]::CreateDirectory($folder)
            $path=Join-Path $folder 'synthetic.txt'
            $entry=@{id=321;key=$env:PROBE_KEY;ref=$env:ISOLATION_REF;version=('c'*64);size_in_bytes=100}
            if($scenario.StartsWith('reader')){
                $env:PROBE_MODE='read';$env:ACTUAL_REF='refs/heads/main';$env:SAVE_OUTCOME='skipped';$env:CACHE_HIT='';$env:MATCHED_KEY=''
            }else{[IO.File]::WriteAllText($path,'Synthetic branch-scoped cache capability; no product inputs.')}
            switch($scenario){
                'save-skipped' {$env:SAVE_OUTCOME='skipped'}
                'restore-failed' {$env:RESTORE_OUTCOME='failure'}
                'foreign-scope' {$entry.ref='refs/heads/main'}
                'bad-bytes' {[IO.File]::WriteAllText($path,'altered')}
                'reader-hit' {$env:CACHE_HIT='true';$env:MATCHED_KEY=$env:PROBE_KEY}
                'reader-file' {[IO.File]::WriteAllText($path,'leaked')}
            }
            $catalogJson=@{actions_caches=@($entry)}|ConvertTo-Json -Depth 5
            $passed=& {
                param($Observer,$Catalog)
                function gh {$global:LASTEXITCODE=0;return $Catalog}
                try{& $Observer;return $true}catch{return $false}
            } $body $catalogJson
            Assert-Equal ($scenario -in @('writer','reader')) $passed
            $report=Get-Content (Join-Path $folder 'capability.json') -Raw|ConvertFrom-Json
            Assert-Equal $passed $report.confirmed
            Assert-Equal 0 $report.nativeExecutions
            Assert-True (-not $report.suppliesNativeVerdict)
            Assert-Equal $env:SAVE_OUTCOME $report.saveOutcome
        }
    }finally{foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}}
}

. (Join-Path $PSScriptRoot 'ExecutionBinding.Cases.ps1')
. (Join-Path $PSScriptRoot 'CandidateResults.Cases.ps1')
. (Join-Path $PSScriptRoot 'CandidateArchives.Cases.ps1')

Invoke-Case 'Read-only cache syntax admits scoped capabilities and refuses write, dynamic and misplaced authority' {
    $lf=[string][char]10
    $valid=@('cache-mode: read','jobs:','  native:','    cache-mode: none','    steps:','      - run: |','          cache-mode: write') -join $lf
    Assert-True (Test-CiWorkflowCacheModes $valid)
    foreach($invalid in @(
        'cache-mode: write','cache-mode: write-only','cache-mode: Read','cache-mode: ${{ inputs.mode }}',
        'jobs: { native: { cache-mode: read } }',
        (@('jobs:','  native:','    steps:','      cache-mode: read') -join $lf),
        (@('permissions:','  child:','    cache-mode: read') -join $lf),
        (@('cache-mode: read','cache-mode: none') -join $lf),
        (@('jobs:','  native:','    cache-mode: read','    cache-mode: none') -join $lf)
    )){Assert-Refused {Test-CiWorkflowCacheModes $invalid}}
    $probe=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/integration-capabilities.yml'))
    Assert-True (Test-CiWorkflowCacheModes $probe)
    Assert-True ($probe -match 'nativeExecutions=0;suppliesNativeVerdict=\$false;requiresSaveLogReview=\$true')
    Assert-True ($probe -notmatch '(?m)^\s+(contents|actions|statuses|checks): write')
}

Invoke-Case 'Cache capability refusal retains its actual early report before any save attempt' {
    $text=[IO.File]::ReadAllText((Join-Path $engineRoot '.github/workflows/integration-capabilities.yml'))
    $match=[regex]::Match($text,'(?ms)^      - name: Retain the effective server-issued cache mode\r?\n.*?^        run: \|\r?\n(?<body>.*?)(?=^      - name:)')
    Assert-True $match.Success
    $body=[scriptblock]::Create([regex]::Replace($match.Groups['body'].Value,'(?m)^          ',''))
    $root=New-Fixture 'cache-capability-early-evidence'
    $oldTemp=$env:RUNNER_TEMP;$oldMode=$env:ACTIONS_CACHE_MODE
    try{
        foreach($mode in @('','write','none','read')){
            $env:RUNNER_TEMP=Join-Path $root ([guid]::NewGuid().ToString('N'))
            $env:ACTIONS_CACHE_MODE=$mode
            $threw=$false
            try{& $body}catch{$threw=$true}
            Assert-Equal ($mode -cne 'read') $threw
            $evidence=Join-Path $env:RUNNER_TEMP 'integration-cache-capability'
            $record=Get-Content (Join-Path $evidence 'capability.json') -Raw|ConvertFrom-Json
            Assert-Equal $mode $record.effectiveMode
            Assert-Equal 'mode-observed' $record.phase
            Assert-Equal 'not-attempted' $record.saveStepOutcome
            Assert-True (-not $record.confirmed -and -not $record.suppliesNativeVerdict)
            Assert-Equal 0 $record.nativeExecutions
            Assert-Equal ($mode -ceq 'read') (Test-Path (Join-Path $evidence 'synthetic.txt'))
        }
    }finally{$env:RUNNER_TEMP=$oldTemp;$env:ACTIONS_CACHE_MODE=$oldMode}
}

$failed = @($script:rows | Where-Object { -not $_.passed }).Count
$summary = [ordered]@{ schemaVersion = 1; passed = $failed -eq 0; executed = $script:rows.Count; failed = $failed; cases = $script:rows.ToArray() }
$resultPath = Join-Path $runRoot 'results.json'
[IO.File]::WriteAllText($resultPath, ($summary | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
Write-Host "Engine results: $resultPath"
if ($failed) { throw "$failed engine behavior case(s) failed; preserve $runRoot." }
