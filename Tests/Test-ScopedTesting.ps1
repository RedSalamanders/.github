<#
.SYNOPSIS
Tests scoped testing (Tools/Test-Changes.ps1, Ci.ScopedTesting, Ci.TestRunEvidence) and its product shims without
compilation.
.DESCRIPTION
Builds fixture products: Git repositories with stub build.ps1, test.ps1, validate.ps1 and format.ps1 that record their
calls and never compile, and runs the runner against them in child processes. Covers the contract of
Specs/ProjectCommands.md (Scoped testing): plans and reasons for prose, native, unmapped, unscoped and exclusive changes;
reuse and its refusal; input mutation; the changelog gate and the dirty-changelog refusal; Explain without side effects;
the four status tokens; the iteration baseline; the lease, its refusal and its re-entry; host architecture; interactive
obligations; PrePush profiles; data validation; project bindings; evidence capture (Windows); and every shim refusal.
.PARAMETER TestRoot
Existing marked RedSalamander.Perf root, or a hosted RUNNER_TEMP descendant. Creates one unique child only.
.OUTPUTS
Case results, runner.log (every runner invocation's output) and results.json beneath the created child, which is
retained. Nonzero exit on a failed case.
.NOTES
Requires PowerShell 7.4 and Git. No credentials, compiler, network or desktop input; Windows-only cases report SKIP
elsewhere.
.EXAMPLE
./Tests/Test-ScopedTesting.ps1 -TestRoot Z:/RedSalamander.Perf
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TestRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$engineRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$selected = [IO.Path]::GetFullPath($TestRoot).TrimEnd('\', '/')
$hosted = $env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted' -and $env:RUNNER_TEMP
if ($hosted) {
    $prefix = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $selected.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Hosted scoped-testing fixtures must remain under RUNNER_TEMP.' }
} elseif ($selected -notmatch '^[A-Za-z]:[\\/]RedSalamander\.Perf$' -or
    -not (Test-Path -LiteralPath (Join-Path $selected '.red-salamander-test-root')) -or
    [IO.File]::ReadAllText((Join-Path $selected '.red-salamander-test-root')).Trim() -cne 'red-salamander.test-sandbox-root.v1') {
    throw 'Scoped-testing fixtures require the existing marked test root.'
}
$runRoot = Join-Path $selected ('unified-ci/scoped-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($runRoot)
$rows = [Collections.Generic.List[object]]::new()
$runner = Join-Path $engineRoot 'Tools/Test-Changes.ps1'
$engineModule = Join-Path $engineRoot 'Tools/Modules/Ci.ScopedTesting.psm1'
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
Import-Module $engineModule -Force
$hostArchitecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
$hostPlatform = if ($hostArchitecture -ceq 'Arm64') { 'ARM64' } else { 'x64' }
$otherPlatform = if ($hostPlatform -ceq 'x64') { 'ARM64' } else { 'x64' }

function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Refuses([scriptblock]$Body, [string]$Pattern) {
    $message = ''
    try { & $Body | Out-Null } catch { $message = $_.Exception.Message }
    Require ($message -and $message -match $Pattern) "Expected a refusal matching '$Pattern', received '$message'."
    return $message
}
function Case([string]$Name, [scriptblock]$Body) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try { & $Body; $rows.Add([ordered]@{ name = $Name; passed = $true; seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1) }); Write-Host "PASS $Name ($([math]::Round($watch.Elapsed.TotalSeconds))s)" }
    catch { $rows.Add([ordered]@{ name = $Name; passed = $false; error = $_.Exception.Message }); Write-Host "FAIL $Name : $($_.Exception.Message)" -ForegroundColor Red }
}
function Skip([string]$Name, [string]$Reason) { $rows.Add([ordered]@{ name = $Name; passed = $true; skipped = $Reason }); Write-Host "SKIP $Name ($Reason)" }
function Put([string]$Root, [string]$Path, [string]$Text) {
    $target = Join-Path $Root $Path
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    [IO.File]::WriteAllText($target, $Text, [Text.UTF8Encoding]::new($false))
}
function Invoke-FixtureGit([string]$Root, [string[]]$Arguments) {
    $output = @(& git -C $Root @Arguments 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE) { throw "git $($Arguments -join ' ') failed in ${Root}: $($output -join ' ')" }
    return , $output
}
function New-Repository([string]$Root) {
    [void][IO.Directory]::CreateDirectory($Root)
    [void](Invoke-FixtureGit $Root @('init', '-q', '-b', 'main'))
    foreach ($setting in @(@('user.name', 'Scoped fixture'), @('user.email', 'scoped@fixture.invalid'), @('commit.gpgsign', 'false'),
            @('core.autocrlf', 'false'), @('core.longpaths', 'true'), @('core.hooksPath', (Join-Path $Root '.no-hooks')))) {
        [void](Invoke-FixtureGit $Root (@('config') + $setting))
    }
}
function Save-Commit([string]$Root, [string]$Message) {
    [void](Invoke-FixtureGit $Root @('add', '--all'))
    [void](Invoke-FixtureGit $Root @('commit', '-q', '-m', $Message))
}

$stubs = [ordered]@{
    'build.ps1' = @'
param([string]$Platform = 'x64', [string]$Configuration = 'Debug', [int]$BuildNumber = 0)
$ErrorActionPreference = 'Stop'
[IO.File]::AppendAllText($env:FIXTURE_CALL_LOG, "build $Platform $Configuration $BuildNumber`n")
$output = Join-Path $PSScriptRoot ".build/$Platform/$Configuration"
[void][IO.Directory]::CreateDirectory($output)
$text = (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -File -Recurse | Sort-Object FullName | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
# A text file with an executable name: the fixture never runs it.
[IO.File]::WriteAllText((Join-Path $output 'app.exe'), "A fixture artifact that is never run.`n$text`n$BuildNumber")
if ([IO.File]::Exists((Join-Path $PSScriptRoot '.fixture-control/build-fail'))) { exit 3 }
'@
    'test.ps1' = @'
param([string]$Platform = 'x64', [string]$Configuration = 'Debug', [string[]]$Suites = @(), [switch]$SkipBuild, [switch]$SkipTooling, [int]$ParallelSuites = 1)
$ErrorActionPreference = 'Stop'
[IO.File]::AppendAllText($env:FIXTURE_CALL_LOG, "test $Platform $Configuration $($Suites -join ',') skipBuild=$SkipBuild skipTooling=$SkipTooling parallel=$ParallelSuites`n")
if ($env:FIXTURE_SCOPED_MODULE) {
    Import-Module $env:FIXTURE_SCOPED_MODULE -Force
    $lease = Enter-ScopedProfileLease -Root $PSScriptRoot -Platform $Platform -Configuration $Configuration
    Exit-ScopedProfileLease $lease
    [IO.File]::AppendAllText($env:FIXTURE_CALL_LOG, "lease re-entered nested=$($lease.Nested)`n")
}
$control = Join-Path $PSScriptRoot '.fixture-control'
$skipped = if ([IO.File]::Exists((Join-Path $control 'skips'))) { @([IO.File]::ReadAllLines((Join-Path $control 'skips'))) } else { @() }
$reports = Join-Path $PSScriptRoot '.build/reports'
[void][IO.Directory]::CreateDirectory($reports)
$suffix = if ($env:FIXTURE_INSTRUMENT) { '.instrumented' } else { '' }
if (-not [IO.File]::Exists((Join-Path $control 'no-report'))) {
    foreach ($suite in $Suites) {
        $skips = @(if ($suite -in $skipped) { "SKIPPED: $suite needs a capability this host lacks" })
        [IO.File]::WriteAllText((Join-Path $reports "$suite-$Platform-$Configuration$suffix.json"), (ConvertTo-Json -InputObject ([ordered]@{ exitCode = 0; skips = $skips })))
    }
}
if ([IO.File]::Exists((Join-Path $control 'test-fail'))) { exit 4 }
'@
    'validate.ps1' = @'
$ErrorActionPreference = 'Stop'
[IO.File]::AppendAllText($env:FIXTURE_CALL_LOG, "validate`n")
if ([IO.File]::Exists((Join-Path $PSScriptRoot '.fixture-control/mutate'))) { [IO.File]::AppendAllText((Join-Path $PSScriptRoot 'src/app.cpp'), "// changed while validating`n") }
if ([IO.File]::Exists((Join-Path $PSScriptRoot '.fixture-control/validate-fail'))) { exit 2 }
'@
    'format.ps1' = @'
param([switch]$Check)
[IO.File]::AppendAllText($env:FIXTURE_CALL_LOG, "format check=$Check`n")
'@
}

function New-FixtureData {
    # The fixture's data, as a product writes it: two native and two independent scopes.
    return [ordered]@{
        version = 2; defaultBranch = 'main'; buildNumber = 'mergeBaseCount'
        nativeInventory = [ordered]@{ path = 'Tests/native-test-files.json'; exclude = @('Specs/**', 'Measurements/**'); testFolders = @('Tests/**') }
        runtimeFiles = @()
        prose = @('README.md', 'CHANGELOG.md', '**/AGENTS.md', 'docs/**/*.md', 'Changes/**/*.md')
        unscoped = @('docs/**', 'Measurements/**')
        scopes = @(
            [ordered]@{ name = 'Core'; native = $true; reuse = $true },
            [ordered]@{ name = 'Sanitizer'; native = $true; reuse = $false; configurations = @('ASan Debug') },
            [ordered]@{ name = 'Tooling'; native = $false; reuse = $true; commands = @([ordered]@{ path = 'validate.ps1'; arguments = @() }) },
            [ordered]@{ name = 'Format'; native = $false; reuse = $true; commands = @([ordered]@{ path = 'format.ps1'; arguments = @('-Check') }) })
        rules = @(
            [ordered]@{ pattern = 'src/**'; scopes = @('Core'); reason = 'product source' },
            [ordered]@{ pattern = 'Tests/Core/**'; scopes = @('Core', 'Sanitizer'); reason = 'core suite and its sanitizer run' },
            [ordered]@{ pattern = '**/*.cpp'; scopes = @('Format'); reason = 'native source formatting'; additive = $true },
            [ordered]@{ pattern = '**/*.h'; scopes = @('Format'); reason = 'native header formatting'; additive = $true },
            [ordered]@{ pattern = 'validate.ps1'; scopes = @('Tooling'); reason = 'repository validator' },
            [ordered]@{ pattern = 'format.ps1'; scopes = @('Format', 'Tooling'); reason = 'formatter contract' },
            [ordered]@{ pattern = 'Tools/SkillCheck.psm1'; scopes = @('Tooling'); reason = 'independent skill validator'; exclusive = $true },
            [ordered]@{ pattern = 'Tools/**'; scopes = @('*'); reason = 'shared build and runner policy' },
            [ordered]@{ pattern = 'build.ps1'; scopes = @('*'); reason = 'shared build policy' },
            [ordered]@{ pattern = 'test.ps1'; scopes = @('*'); reason = 'shared runner policy' },
            [ordered]@{ pattern = 'Tests/test-scopes.json'; scopes = @('*'); reason = 'scope policy' },
            [ordered]@{ pattern = 'docs/runtime/*.md'; scopes = @('Core'); reason = 'help text the core suite reads' })
        interactiveObligations = @([ordered]@{ pattern = 'src/ui/**'; suites = @('Menu'); reason = 'menu scenarios need the interactive desktop' })
        watchedProcesses = @('fixture-probe.exe')
        prePushProfiles = @([ordered]@{ platform = $hostPlatform; configuration = 'Debug' }, [ordered]@{ platform = $hostPlatform; configuration = 'Release' },
            [ordered]@{ platform = $otherPlatform; configuration = 'Debug'; buildOnly = $true })
        instrumentationVariables = @('FIXTURE_INSTRUMENT')
    }
}

function Write-FixtureTree([string]$Root, [Collections.IDictionary]$Data) {
    Put $Root '.gitignore' ".build/`n.fixture-control/`n.ci-engine/`n"
    Put $Root 'README.md' "# Fixture product`n"
    Put $Root 'AGENTS.md' "Fixture guidance.`n"
    Put $Root 'CHANGELOG.md' "# Changelog`n`n## Unreleased`n"
    Put $Root 'Changes/README.md' "# Changes`n`nOne fragment per change, folded after merge.`n"
    Put $Root 'docs/guide.md' "# Guide`n"
    Put $Root 'docs/diagram.txt' "a picture`n"
    Put $Root 'docs/runtime/help.md' "# Help the core suite reads`n"
    Put $Root 'Measurements/run.json' "{`"elapsed`": 1}`n"
    Put $Root 'src/app.cpp' "int app() { return 1; }`n"
    Put $Root 'src/app.h' "int app();`n"
    Put $Root 'src/ui/menu.cpp' "int menu() { return 2; }`n"
    Put $Root 'Tests/Core/Core.Tests.Main.cpp' "int core_test() { return 0; }`n"
    Put $Root 'Tests/native-test-files.json' "[`"Tests/Core/Core.Tests.Main.cpp`"]`n"
    Put $Root 'Tools/SkillCheck.psm1' "# skill validator`n"
    Put $Root 'Tools/Shared.psm1' "# shared runner policy`n"
    foreach ($name in $stubs.Keys) { Put $Root $name $stubs[$name] }
    Put $Root 'Tests/test-scopes.json' (ConvertTo-Json -InputObject $Data -Depth 10)
}

function New-Product([string]$Name, [scriptblock]$Customize = $null) {
    $root = Join-Path $runRoot $Name
    New-Repository $root
    $data = New-FixtureData
    if ($Customize) { & $Customize $data }
    Write-FixtureTree $root $data
    Save-Commit $root 'Fixture product'
    [void](Invoke-FixtureGit $root @('update-ref', 'refs/remotes/origin/main', 'HEAD'))
    return [pscustomobject]@{ Name = $Name; Root = $root; Log = Join-Path $runRoot "$Name.calls.log"; Module = $engineModule; Command = $runner; Shim = $false }
}

function Set-Control([object]$Product, [string]$Name, [string]$Text = '') { Put $Product.Root ".fixture-control/$Name" $Text }
function Clear-Control([object]$Product, [string]$Name) { $path = Join-Path $Product.Root ".fixture-control/$Name"; if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
function Edit-File([object]$Product, [string]$Path, [string]$Text = "// edited`n") { [IO.File]::AppendAllText((Join-Path $Product.Root $Path), $Text) }

function Invoke-Runner([object]$Product, [string[]]$Arguments = @(), [hashtable]$Environment = @{}) {
    if ([IO.File]::Exists($Product.Log)) { [IO.File]::Delete($Product.Log) }
    $start = [Diagnostics.ProcessStartInfo]::new($pwsh)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $start.WorkingDirectory = $Product.Root
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $Product.Command)) { $start.ArgumentList.Add($argument) }
    if (-not $Product.Shim) { $start.ArgumentList.Add('-Root'); $start.ArgumentList.Add($Product.Root) }
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    # Each run sees only the environment its case names: no CI, inherited lease or instrumentation.
    foreach ($name in @('CI', 'GITHUB_ACTIONS', 'CI_SCOPED_TESTING_LEASE', 'FIXTURE_INSTRUMENT')) { [void]$start.Environment.Remove($name) }
    $start.Environment['NO_COLOR'] = '1'
    $start.Environment['FIXTURE_CALL_LOG'] = $Product.Log
    $start.Environment['FIXTURE_SCOPED_MODULE'] = $Product.Module
    foreach ($key in $Environment.Keys) { $start.Environment[$key] = [string]$Environment[$key] }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(900000)) { $process.Kill($true); $process.WaitForExit(); throw "The runner timed out in $($Product.Name)." }
        $process.WaitForExit()
        $raw = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::AppendAllText((Join-Path $runRoot 'runner.log'), "### $($Product.Name): $($Arguments -join ' ') (exit $($process.ExitCode))`n$raw`n")
        # Error views wrap long messages at the console width: match on single-spaced text without escapes.
        # The error view continues a wrapped message on "| " lines.
        $plain = [regex]::Replace($raw, '\x1b\[[0-9;?]*[ -/]*[@-~]', '')
        $text = [regex]::Replace([regex]::Replace($plain, '\r?\n\s*\|\s?', ' '), '[ \t]*\r?\n[ \t]*(?=\S)', ' ')
        $calls = if ([IO.File]::Exists($Product.Log)) { @([IO.File]::ReadAllLines($Product.Log)) } else { @() }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $text; Calls = $calls }
    } finally { $process.Dispose() }
}

function Assert-Run([object]$Result, [int]$ExitCode = 0, [string[]]$Output = @(), [string[]]$Absent = @(), [string]$Token = '') {
    $tail = if ($Result.Output.Length -gt 1500) { $Result.Output.Substring($Result.Output.Length - 1500) } else { $Result.Output }
    if ($ExitCode -eq 0) { Require ($Result.ExitCode -eq 0) "The runner failed ($($Result.ExitCode)): $tail" }
    else { Require ($Result.ExitCode -ne 0) "The runner succeeded where it must refuse: $tail" }
    foreach ($pattern in $Output) { Require ($Result.Output -match $pattern) "The runner output lacks '$pattern': $tail" }
    foreach ($pattern in $Absent) { Require ($Result.Output -notmatch $pattern) "The runner output holds '$pattern': $tail" }
    if ($Token) { Require ($Result.Output -match ([regex]::Escape("$Token; repository NOT_EVALUATED"))) "The runner did not end with ${Token}: $tail" }
}
function Assert-Calls([object]$Result, [string[]]$Expected) {
    $actual = @($Result.Calls | Where-Object { $_ -notlike 'lease re-entered*' })
    Require (($actual -join ' | ') -ceq ($Expected -join ' | ')) "Expected the calls '$($Expected -join ' | ')', recorded '$($actual -join ' | ')'."
}
function Get-Plan([object]$Manifest, [string[]]$Paths, [string]$Configuration = 'Debug') {
    return Get-ScopedTestPlan -Manifest $Manifest -ChangedPaths $Paths -Configuration $Configuration
}

$base = New-Product 'planning'
$manifest = Read-ScopedTestManifest -Root $base.Root

Case 'plans and reasons for prose, native, unscoped, unmapped and exclusive changes' {
    $plan = Get-Plan $manifest @('README.md')
    Require (($plan.scopes -join ',') -ceq 'Tooling,Format' -and $plan.prose -and -not $plan.full) "Prose selects every non-native scope: $($plan.scopes -join ',')"
    Require ($plan.reasons[0].kind -ceq 'prose' -and $plan.reasons[0].reason -like 'prose:*') 'The prose reason is missing.'
    $plan = Get-Plan $manifest @('src/app.cpp')
    Require (($plan.scopes -join ',') -ceq 'Core,Format' -and -not $plan.prose) "A native change selects its rules: $($plan.scopes -join ',')"
    Require (@($plan.reasons | ForEach-Object { $_.reason }) -join '|' -ceq 'product source|native source formatting') 'Each matched rule gives its reason.'
    $plan = Get-Plan $manifest @('Measurements/run.json', 'docs/diagram.txt')
    Require ($plan.scopes.Count -eq 0 -and @($plan.reasons | Where-Object { $_.kind -ceq 'unscoped' }).Count -eq 2) 'Unscoped paths select nothing.'
    $plan = Get-Plan $manifest @('other/new.cpp')
    Require ($plan.full -and ($plan.scopes -join ',') -ceq 'Core,Tooling,Format' -and ($plan.notApplicable -join ',') -ceq 'Sanitizer' -and
        $plan.reasons[0].reason -like 'unmapped input*') 'An input that only an additive rule matches takes the full fallback.'
    $plan = Get-Plan $manifest @('Tools/SkillCheck.psm1')
    Require (($plan.scopes -join ',') -ceq 'Tooling' -and $plan.reasons[0].kind -ceq 'exclusive') 'An exclusive rule replaces the broader Tools/** rule.'
    $plan = Get-Plan $manifest @('Tools/Shared.psm1')
    Require $plan.full 'The broad rule still selects every scope for other files.'
    $plan = Get-Plan $manifest @('docs/runtime/help.md')
    Require (($plan.scopes -join ',') -ceq 'Core,Tooling,Format' -and -not $plan.prose) 'A rule naming Markdown makes prose a runtime input.'
    $plan = Get-Plan $manifest @('src/AGENTS.md')
    Require (($plan.scopes -join ',') -ceq 'Tooling,Format' -and $plan.prose) 'A broad folder rule does not make guidance a runtime input.'
    $plan = Get-Plan $manifest @('Tests/Core/Core.Tests.Main.cpp') 'ASan Debug'
    Require (($plan.scopes -join ',') -ceq 'Core,Sanitizer,Format') 'A configuration-bound scope runs in its configuration.'
    $plan = Get-ScopedTestPlan -Manifest $manifest -Scopes @('core', 'Tooling') -Configuration 'Debug'
    Require (($plan.scopes -join ',') -ceq 'Core,Tooling' -and $plan.reasons[0].kind -ceq 'explicit') 'Explicit scopes are matched without case.'
    [void](Refuses { Get-ScopedTestPlan -Manifest $manifest -Scopes @('Sanitizer') -Configuration 'Debug' } 'does not run in Debug')
    [void](Refuses { Get-ScopedTestPlan -Manifest $manifest -Scopes @('Nope') } 'Unknown test scope')
    [void](Refuses { Get-Plan $manifest @('../outside.cpp') } 'repository-relative')
    $plan = Get-Plan $manifest @()
    Require ($plan.scopes.Count -eq 0 -and -not $plan.full -and -not $plan.prose) 'No change selects nothing.'
    # Identities classify whole trees with a compiled form of the same rules; both must agree on every kind of path.
    $module = Get-Module Ci.ScopedTesting
    $disagreements = & $module {
        param($Manifest, [string[]]$Paths)
        $names = [string[]]@($Manifest.scopes | ForEach-Object { $_.name })
        $nonNative = [string[]]@($Manifest.scopes | Where-Object { -not $_.native } | ForEach-Object { $_.name })
        $nativeNames = @($Manifest.scopes | Where-Object { $_.native } | ForEach-Object { $_.name })
        $matcher = New-ScopedRuleMatcher $Manifest
        $classifier = New-ScopedPathClassifier $Manifest
        foreach ($path in $Paths) {
            $resolved = Resolve-ScopedPath $Manifest $matcher $path $names $nonNative
            $expected = $resolved.kind
            if ($expected -ceq 'prose' -and @($resolved.reasons | ForEach-Object { $_.scopes } | Where-Object { $_ -cin $nativeNames }).Count) { $expected = 'native prose' }
            $actual = Get-ScopedPathKind $classifier $path
            if ($actual -cne $expected) { "${path}: $actual instead of $expected" }
        }
    } $manifest @('README.md', 'src/AGENTS.md', 'docs/runtime/help.md', 'docs/guide.md', 'docs/diagram.txt', 'Measurements/run.json', 'src/app.cpp',
        'other/new.cpp', 'other/new.h', 'Tools/SkillCheck.psm1', 'Tools/Shared.psm1', 'validate.ps1', 'format.ps1', 'Tests/Core/x.cpp', 'Changes/a.md', 'x.txt')
    Require (-not @($disagreements).Count) "The identity classifier disagrees with planning: $(@($disagreements) -join '; ')"
}

Case 'RedMonitor''s three outcomes (none, prose, native) are data rules (O3)' {
    $root = Join-Path $runRoot 'three-kinds'
    New-Repository $root
    $data = [ordered]@{ version = 2; defaultBranch = 'main'; buildNumber = 'none'
        nativeInventory = [ordered]@{ path = 'Tests/native-test-files.json'; exclude = @(); testFolders = @('Tests/**') }
        prose = @('README.md', 'AGENTS.md', 'CLAUDE.md', 'CHANGELOG.md', 'Tests/README.md', 'Specs/**/*.md', 'docs/**/*.md', 'Changes/**/*.md', '.agents/**/*.md', '.github/skills/**/*.md')
        unscoped = @(); rules = @()
        scopes = @([ordered]@{ name = 'Validation'; native = $false; reuse = $true; commands = @([ordered]@{ path = 'validate.ps1'; arguments = @() }) },
            [ordered]@{ name = 'Format'; native = $false; reuse = $true; commands = @([ordered]@{ path = 'format.ps1'; arguments = @('-Check') }) },
            [ordered]@{ name = 'Tooling'; native = $false; reuse = $true; commands = @([ordered]@{ path = 'Tests/Tooling.Tests.ps1'; arguments = @() }) },
            [ordered]@{ name = 'Native'; native = $true; reuse = $false })
        watchedProcesses = @('MonitorTest.exe'); prePushProfiles = @([ordered]@{ platform = 'x64'; configuration = 'Debug' }) }
    Put $root 'Tests/test-scopes.json' (ConvertTo-Json -InputObject $data -Depth 10)
    Put $root 'Tests/native-test-files.json' '[]'
    $three = Read-ScopedTestManifest -Root $root
    Require ((Get-Plan $three @()).scopes.Count -eq 0) 'None: no change selects nothing.'
    $plan = Get-Plan $three @('README.md', 'Specs/Plan.md')
    Require ($plan.prose -and ($plan.scopes -join ',') -ceq 'Validation,Format,Tooling') 'Prose: only the independent checks.'
    $plan = Get-Plan $three @('README.md', 'src/Monitor.cpp')
    Require ($plan.full -and -not $plan.prose -and 'Native' -cin $plan.scopes) 'Native: an unmapped input selects every scope.'
}

Case 'project bindings become exact-path rules with overrides and a conservative fallback' {
    $root = Join-Path $runRoot 'bindings'
    New-Repository $root
    Put $root 'src/App.vcxproj' '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><ItemGroup><ClCompile Include="main.cpp" /><ClCompile Include="..\Tests\App.Tests.Main.cpp" /></ItemGroup></Project>'
    Put $root 'src/main.cpp' "#include `"util.h`"`nint main() { return 0; }`n"
    Put $root 'src/util.h' "#include <shared.h>`n"
    Put $root 'Common/shared.h' "// shared`n"
    Put $root 'legacy/shared.h' "// an oracle copy`n"
    Put $root 'Tests/App.Tests.Main.cpp' "#include `"util.h`"`n"
    Save-Commit $root 'Bindings'
    $bindings = [pscustomobject]@{ includeRoots = @('Common'); exclude = @('legacy/**')
        projects = @([pscustomobject]@{ path = 'src/App.vcxproj'; scopes = @('App', 'Perf'); overrides = @([pscustomobject]@{ pattern = '**/*.Tests.*.cpp'; scopes = @('App') }) }) }
    $rules = @(Get-ScopedProjectRules -Root $root -Bindings $bindings)
    $text = @($rules | ForEach-Object { "$($_.pattern)=$($_.scopes -join '+')" }) -join ' '
    Require ($text -ceq 'Common/shared.h=App+Perf Tests/App.Tests.Main.cpp=App src/main.cpp=App+Perf src/util.h=App+Perf') "Unexpected derived rules: $text"
    Put $root 'src/App.vcxproj' '<Project><ItemGroup><ClCompile Include="$(Generated)\x.cpp" /><ClCompile Include="main.cpp" /></ItemGroup></Project>'
    $rules = @(Get-ScopedProjectRules -Root $root -Bindings $bindings)
    Require (@($rules | Where-Object { $_.pattern -ceq '**' -and $_.scopes -ceq '*' }).Count -eq 1) 'A macro item adds the conservative full fallback.'
}

Case 'invalid data, inventories and reserved names are refused' {
    $root = Join-Path $runRoot 'invalid-data'
    New-Repository $root
    $write = { param($Data) Put $root 'Tests/test-scopes.json' (ConvertTo-Json -InputObject $Data -Depth 10) }
    Put $root 'Tests/test-scopes.json' '{"version":1,"scopes":[{"name":"A","native":false,"reuse":true}],"rules":[]}'
    [void](Refuses { Read-ScopedTestManifest -Root $root } 'not valid scoped testing data')
    $data = New-FixtureData; $data['repository'] = 'RedSalamanders/Fixture'; & $write $data
    [void](Refuses { Read-ScopedTestManifest -Root $root } 'not valid scoped testing data')
    $data = New-FixtureData; $data.rules[6].pattern = 'Tools/*.psm1'; & $write $data
    [void](Refuses { Read-ScopedTestManifest -Root $root } 'must name one exact path')
    $data = New-FixtureData; $data.rules[0].scopes = @('Missing'); & $write $data
    [void](Refuses { Read-ScopedTestManifest -Root $root } "unknown scope 'Missing'")
    $data = New-FixtureData; $data.Remove('nativeInventory'); & $write $data
    [void](Refuses { Read-ScopedTestManifest -Root $root } 'without a nativeInventory')
    $data = New-FixtureData; $data.scopes[2].Remove('commands'); & $write $data
    [void](Refuses { Read-ScopedTestManifest -Root $root } 'not valid scoped testing data')
    $data = New-FixtureData; $data.scopes[0].name = 'build'; foreach ($rule in $data.rules) { $rule.scopes = @($rule.scopes | ForEach-Object { if ($_ -ceq 'Core') { 'build' } else { $_ } }) }; & $write $data
    [void](Refuses { Read-ScopedTestManifest -Root $root } 'reserved')
    $data = New-FixtureData; $data.scopes += [ordered]@{ name = 'core'; native = $false; reuse = $true; commands = @([ordered]@{ path = 'x.ps1'; arguments = @() }) }; & $write $data
    [void](Refuses { Read-ScopedTestManifest -Root $root } 'twice')
    $data = New-FixtureData; $data.rules[0]['exclusive'] = $true; $data.rules[0]['additive'] = $true; $data.rules[0].pattern = 'src/app.cpp'; & $write $data
    [void](Refuses { Read-ScopedTestManifest -Root $root } 'not valid scoped testing data')
    $product = New-Product 'inventory'
    Put $product.Root 'Tests/Core/Extra.cpp' "int extra() { return 0; }`n"
    [void](Refuses { Assert-ScopedTestNames -Root $product.Root } 'absent from Tests/native-test-files.json: Tests/Core/Extra.cpp')
    [IO.File]::Delete((Join-Path $product.Root 'Tests/Core/Extra.cpp'))
    Put $product.Root 'src/FakeClock.h' "// a fake`n"
    [void](Refuses { Assert-ScopedTestNames -Root $product.Root } 'absent from .*src/FakeClock.h')
    [IO.File]::Delete((Join-Path $product.Root 'src/FakeClock.h'))
    Put $product.Root 'src/Attestation.h' "// not a test`n"
    Require ((Assert-ScopedTestNames -Root $product.Root) -eq 1) 'A word containing Test is not a test source.'
}

Case 'Explain prints the plan with no changelog gate, lease, build, test or write' {
    $product = New-Product 'explain'
    Edit-File $product 'src/app.cpp'
    Put $product.Root 'Changes/Bad Name.md' "not a fragment`n"
    $before = (Invoke-FixtureGit $product.Root @('status', '--porcelain', '--untracked-files=all')) -join "`n"
    $lease = Enter-ScopedProfileLease -Root $product.Root -Platform $hostPlatform -Configuration 'Debug'
    try { $result = Invoke-Runner $product @('-Explain', '-Platform', $hostPlatform) } finally { Exit-ScopedProfileLease $lease }
    Assert-Run $result -Output @('Test plan: Affected', 'src/app.cpp: product source => Core', 'native source formatting => Format') -Absent @('NOT_EVALUATED', 'Changelog')
    Assert-Calls $result @()
    Require (-not [IO.Directory]::Exists((Join-Path $product.Root '.build'))) 'Explain created .build.'
    Require (((Invoke-FixtureGit $product.Root @('status', '--porcelain', '--untracked-files=all')) -join "`n") -ceq $before) 'Explain changed the checkout.'
}

Case 'the changelog gate runs before any build or test' {
    $product = New-Product 'changelog-first'
    Edit-File $product 'src/app.cpp'
    Put $product.Root 'Changes/Bad Name.md' "not a fragment`n"
    $result = Invoke-Runner $product @('-Platform', $hostPlatform)
    Assert-Run $result -ExitCode 1 -Output @('Changelog validation failed')
    Assert-Calls $result @()
    Require (-not [IO.Directory]::Exists((Join-Path $product.Root '.build'))) 'A refused changelog still started work.'
}

Case 'status tokens, independent commands, whole-profile builds, reuse across modes and nested leases' {
    $product = New-Product 'tokens'
    Edit-File $product 'Measurements/run.json' "`n"
    Assert-Run ($result = Invoke-Runner $product @('-Platform', $hostPlatform)) -Token 'NOTHING_SELECTED' -Output @('Measurements/run.json: unscoped')
    Assert-Calls $result @()
    Edit-File $product 'README.md' "More prose.`n"
    Assert-Run ($result = Invoke-Runner $product @('-Platform', $hostPlatform)) -Token 'PROSE_CHECKS_PASSED' -Output @('PASSED Tooling', 'PASSED Format')
    Assert-Calls $result @('validate', 'format check=True')
    Edit-File $product 'src/app.cpp'
    $result = Invoke-Runner $product @('-Platform', $hostPlatform)
    Assert-Run $result -Token 'SELECTED_PASSED' -Output @('baseline: the last successful affected run', 'PASSED Core \(native suite\)', 'PASSED Format')
    Assert-Calls $result @("build $hostPlatform Debug 1", 'format check=True', "test $hostPlatform Debug Core skipBuild=True skipTooling=True parallel=1")
    Require ($result.Calls -ccontains 'lease re-entered nested=True') "test.ps1 did not re-enter the runner's lease: $($result.Calls -join ' | ')"
    $result = Invoke-Runner $product @('-Mode', 'Full', '-Platform', $hostPlatform)
    Assert-Run $result -Token 'FULL_PASSED' -Output @('REUSED Core', 'REUSED Format', 'PASSED Tooling')
    Assert-Calls $result @("build $hostPlatform Debug 1", 'validate')
    $result = Invoke-Runner $product @('-Mode', 'Full', '-Platform', $hostPlatform, '-Configuration', 'ASan Debug')
    Assert-Run $result -Token 'FULL_PASSED' -Output @('REUSED Tooling', 'REUSED Format')
    Assert-Calls $result @("build $hostPlatform ASan Debug 1", "test $hostPlatform ASan Debug Core,Sanitizer skipBuild=True skipTooling=True parallel=1")
    $result = Invoke-Runner $product @('-Mode', 'Full', '-Platform', $hostPlatform, '-Configuration', 'ASan Debug')
    Assert-Run $result -Token 'FULL_PASSED' -Output @('REUSED Core')
    Assert-Calls $result @("build $hostPlatform ASan Debug 1", "test $hostPlatform ASan Debug Sanitizer skipBuild=True skipTooling=True parallel=1")
}

Case 'the iteration baseline is local, recent, exact and revoked before execution (B4)' {
    $product = New-Product 'baseline'
    Edit-File $product 'src/app.cpp'
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform)) -Token 'SELECTED_PASSED' -Output @('baseline: merge base with origin/main \(no iteration baseline\)')
    $result = Invoke-Runner $product @('-Platform', $hostPlatform)
    Assert-Run $result -Token 'NOTHING_SELECTED' -Output @('baseline: the last successful affected run of this profile')
    Assert-Calls $result @()
    $result = Invoke-Runner $product @('-Platform', $hostPlatform, '-BaseRef', 'origin/main')
    Assert-Run $result -Token 'SELECTED_PASSED' -Output @('iteration baseline off: explicit -BaseRef', 'REUSED Core', 'REUSED Format')
    Assert-Calls $result @("build $hostPlatform Debug 1")
    $iteration = Join-Path (Get-ScopedReportRoot -Root $product.Root -Platform $hostPlatform -Configuration 'Debug') 'iteration.json'
    Require (-not [IO.File]::Exists($iteration)) 'A run that does not advance the baseline must revoke it.'
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform)) -Token 'SELECTED_PASSED' -Output @('\(no iteration baseline\)', 'REUSED Core')
    Require ([IO.File]::Exists($iteration)) 'An ordinary affected run writes the baseline.'
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform) -Environment @{ CI = 'true' }) -Token 'SELECTED_PASSED' -Output @('iteration baseline off: CI')
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform)) -Token 'SELECTED_PASSED' -Output @('\(no iteration baseline\)')
    $state = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($iteration)) -AsHashtable
    $state.completedUtc = [DateTime]::UtcNow.AddHours(-25).ToString('o')
    $module = Get-Module Ci.ScopedTesting
    $state.digest = & $module { param($State) Get-ScopedIterationDigest $State } $state
    [IO.File]::WriteAllText($iteration, (ConvertTo-Json -InputObject $state -Depth 8))
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform)) -Token 'SELECTED_PASSED' -Output @('\(no iteration baseline\)')
    $result = Invoke-Runner $product @('-Platform', $hostPlatform) -Environment @{ FIXTURE_INSTRUMENT = '1' }
    Assert-Run $result -Token 'SELECTED_PASSED' -Output @('iteration baseline off: instrumentation', 'INSTRUMENTED RUN', 'PASSED Core')
}

Case 'reuse needs an exact receipt and a clean suite report; Force, skips and missing reports refuse it (B5)' {
    $product = New-Product 'reuse'
    Edit-File $product 'src/app.cpp'
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform)) -Token 'SELECTED_PASSED'
    $again = @('-Platform', $hostPlatform, '-BaseRef', 'origin/main')
    $result = Invoke-Runner $product ($again + '-Force')
    Assert-Run $result -Token 'SELECTED_PASSED' -Absent @('REUSED')
    Assert-Calls $result @("build $hostPlatform Debug 1", 'format check=True', "test $hostPlatform Debug Core skipBuild=True skipTooling=True parallel=1")
    Set-Control $product 'skips' 'Core'
    Assert-Run (Invoke-Runner $product ($again + '-Force')) -Token 'SELECTED_PASSED' -Output @('PASSED_WITH_CAPABILITY_SKIPS Core \(not reusable\)')
    Clear-Control $product 'skips'
    $result = Invoke-Runner $product $again
    Assert-Run $result -Output @('REUSED Format', 'PASSED Core \(native suite\)') -Absent @('REUSED Core')
    [IO.File]::Delete((Join-Path $product.Root ".build/reports/Core-$hostPlatform-Debug.json"))
    $result = Invoke-Runner $product $again
    Assert-Run $result -Output @('PASSED Core \(native suite\)') -Absent @('REUSED Core')
    $reportFile = "Core-$hostPlatform-Debug.json"
    $currentReport = Join-Path $product.Root ".build/reports/$reportFile"
    $priorReportHash = (Get-FileHash -LiteralPath $currentReport).Hash
    $archive = Join-Path (Get-ScopedReportRoot -Root $product.Root -Platform $hostPlatform -Configuration 'Debug') 'prior-suite-reports'
    $previousPaths = @(Get-ChildItem -LiteralPath $archive -File -Filter $reportFile -Recurse | ForEach-Object FullName)
    Set-Control $product 'no-report'
    Assert-Run (Invoke-Runner $product ($again + '-Force')) -ExitCode 1 -Output @('wrote no current suite report')
    Require (-not [IO.File]::Exists($currentReport)) 'A missing result left a prior report in the current slot.'
    $retained = @(Get-ChildItem -LiteralPath $archive -File -Filter $reportFile -Recurse | Where-Object FullName -cnotin $previousPaths)
    Require ($retained.Count -eq 1 -and (Get-FileHash -LiteralPath $retained[0].FullName).Hash -ceq $priorReportHash) 'The prior report was not retained byte for byte.'
    Clear-Control $product 'no-report'
    Set-Control $product 'test-fail'
    Assert-Run (Invoke-Runner $product ($again + '-Force')) -ExitCode 1 -Output @('Selected runtime tests .* failed with exit 4')
    Clear-Control $product 'test-fail'
    $result = Invoke-Runner $product $again
    Assert-Run $result -Absent @('REUSED Core')
    $result = Invoke-Runner $product ($again + @('-ParallelSuites', '3', '-Force'))
    Assert-Calls $result @("build $hostPlatform Debug 1", 'format check=True', "test $hostPlatform Debug Core skipBuild=True skipTooling=True parallel=3")
}

Case 'inputs that change while a scope runs refuse its success (B6)' {
    $product = New-Product 'mutation'
    Edit-File $product 'README.md' "Prose.`n"
    Set-Control $product 'mutate'
    $result = Invoke-Runner $product @('-Platform', $hostPlatform)
    Assert-Run $result -ExitCode 1 -Output @('Inputs changed during Tooling; no reusable success was published')
    Require (-not [IO.File]::Exists((Join-Path $product.Root '.build/reports/scoped-tests/independent/Tooling.json'))) 'A mutated scope published a receipt.'
    Assert-Calls $result @('validate')
    Clear-Control $product 'mutate'
    Set-Control $product 'validate-fail'
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform)) -ExitCode 1 -Output @('Independent scope failed: Tooling')
}

Case 'PrePush refuses an uncommitted changelog, checks it against the base and runs every data profile (B3, O1)' {
    $product = New-Product 'prepush'
    Edit-File $product 'src/app.cpp'
    Save-Commit $product.Root 'A change'
    Assert-Run (Invoke-Runner $product @('-Mode', 'PrePush', '-Platform', 'x64')) -ExitCode 1 -Output @('PrePush runs every profile in prePushProfiles')
    Edit-File $product 'CHANGELOG.md' "`n"
    $result = Invoke-Runner $product @('-Mode', 'PrePush')
    Assert-Run $result -ExitCode 1 -Output @('PrePush requires committed CHANGELOG.md and Changes/ state')
    Assert-Calls $result @()
    [void](Invoke-FixtureGit $product.Root @('checkout', '--', 'CHANGELOG.md'))
    Put $product.Root 'Changes/2026-11-19-fixture.md' "- A pending fragment.`n"
    Assert-Run (Invoke-Runner $product @('-Mode', 'PrePush')) -ExitCode 1 -Output @('PrePush requires committed CHANGELOG.md')
    Save-Commit $product.Root 'Fragment'
    Edit-File $product 'CHANGELOG.md' "- A hand edit.`n"
    Save-Commit $product.Root 'Hand edit'
    $result = Invoke-Runner $product @('-Mode', 'PrePush')
    Assert-Run $result -ExitCode 1 -Output @('Changelog validation failed', 'added by hand')
    Assert-Calls $result @()
    [void](Invoke-FixtureGit $product.Root @('reset', '-q', '--hard', 'HEAD~1'))
    $result = Invoke-Runner $product @('-Mode', 'PrePush', '-Explain')
    Assert-Run $result -Output @("== PrePush profile $hostPlatform Debug", "== PrePush profile $hostPlatform Release", "Build only: build.ps1 -Platform $otherPlatform") -Absent @('NOT_EVALUATED')
    Assert-Calls $result @()
    $result = Invoke-Runner $product @('-Mode', 'PrePush')
    Assert-Run $result -Token 'FULL_PASSED' -Output @('Changelog valid', 'REUSED Tooling', 'REUSED Format', "BUILT $otherPlatform Debug")
    # The build number is the merge base's commit count, so the branch's own commits never relink it.
    Assert-Calls $result @("build $hostPlatform Debug 1", 'validate', 'format check=True', "test $hostPlatform Debug Core skipBuild=True skipTooling=True parallel=1",
        "build $hostPlatform Release 1", "test $hostPlatform Release Core skipBuild=True skipTooling=True parallel=1", "build $otherPlatform Debug 1")
}

Case 'the profile lease refuses a concurrent run and lets Explain plan (B8)' {
    $product = New-Product 'lease'
    Edit-File $product 'src/app.cpp'
    $lease = Enter-ScopedProfileLease -Root $product.Root -Platform $hostPlatform -Configuration 'Debug'
    try {
        $result = Invoke-Runner $product @('-Platform', $hostPlatform)
        Assert-Run $result -ExitCode 1 -Output @('Another test operation owns this checkout and profile')
        Assert-Calls $result @()
        Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform, '-Explain')) -Output @('Test plan')
        Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform, '-Configuration', 'Release', '-Scopes', 'Tooling')) -Token 'SELECTED_PASSED'
    } finally { Exit-ScopedProfileLease $lease }
    Require (-not [Environment]::GetEnvironmentVariable('CI_SCOPED_TESTING_LEASE')) 'Leaving the lease kept its handoff.'
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform)) -Token 'SELECTED_PASSED'
}

Case 'runtime tests need a matching host, interactive suites are listed and never run (B9, B10)' {
    [void](Refuses { Assert-ScopedRuntimePlatform -Platform 'x64' -HostArchitecture 'Arm64' } 'matching x64 host')
    [void](Refuses { Assert-ScopedRuntimePlatform -Platform 'ARM64' -HostArchitecture 'X64' } 'matching ARM64 host')
    Assert-ScopedRuntimePlatform -Platform 'ARM64' -HostArchitecture 'Arm64'
    Assert-ScopedRuntimePlatform -Platform 'x64' -HostArchitecture 'X64'
    $product = New-Product 'host-and-interactive'
    Edit-File $product 'src/ui/menu.cpp'
    $result = Invoke-Runner $product @('-Platform', $otherPlatform)
    Assert-Run $result -ExitCode 1 -Output @("requires a matching $otherPlatform host")
    Assert-Calls $result @()
    $result = Invoke-Runner $product @('-Platform', $hostPlatform)
    Assert-Run $result -Token 'SELECTED_PASSED' -Output @('INTERACTIVE_NOT_RUN: Menu - menu scenarios need the interactive desktop \[src/ui/\*\*\]')
    Require (-not @($result.Calls | Where-Object { $_ -match 'Menu' }).Count) "An interactive suite ran: $($result.Calls -join ' | ')"
    Assert-Run (Invoke-Runner $product @('-Platform', $otherPlatform, '-Scopes', 'Tooling')) -Token 'SELECTED_PASSED'
}

Case 'the base, explicit scopes, SkipBuild and the parameter set refuse what they cannot honor (B1, B2, O2)' {
    $product = New-Product 'refusals'
    Edit-File $product 'src/app.cpp'
    Assert-Run (Invoke-Runner $product @('-Explain', '-BaseRef', 'refs/heads/missing')) -ExitCode 1 -Output @("'refs/heads/missing', which does not resolve here: fetch it, pass -BaseRef")
    $orphan = Join-Path $runRoot 'refusals-orphan'
    New-Repository $orphan
    Put $orphan 'other.txt' "unrelated`n"
    Save-Commit $orphan 'Unrelated'
    [void](Invoke-FixtureGit $product.Root @('fetch', '-q', $orphan, '+main:refs/remotes/origin/unrelated'))
    Assert-Run (Invoke-Runner $product @('-Explain', '-BaseRef', 'origin/unrelated')) -ExitCode 1 -Output @('shares no history with')
    Assert-Run (Invoke-Runner $product @('-Explain', '-Scopes', 'Core,Tooling', '-Platform', $hostPlatform)) -Output @('scopes: Core, Tooling', '\(explicit\): explicit scope')
    Assert-Run (Invoke-Runner $product @('-Explain', '-Scopes', 'Sanitizer')) -ExitCode 1 -Output @('does not run in Debug')
    Assert-Run (Invoke-Runner $product @('-Mode', 'Full', '-Scopes', 'Core')) -ExitCode 1 -Output @('-Scopes selects the scopes of an Affected run')
    $result = Invoke-Runner $product @('-Platform', $hostPlatform, '-SkipBuild')
    Assert-Run $result -ExitCode 1 -Output @('SkipBuild refused')
    Assert-Calls $result @()
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform)) -Token 'SELECTED_PASSED'
    $result = Invoke-Runner $product @('-Platform', $hostPlatform, '-BaseRef', 'origin/main', '-SkipBuild', '-Force')
    Assert-Run $result -Token 'SELECTED_PASSED'
    Assert-Calls $result @('format check=True', "test $hostPlatform Debug Core skipBuild=True skipTooling=True parallel=1")
    Set-Control $product 'build-fail'
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform, '-Force')) -ExitCode 1 -Output @("Build \($hostPlatform Debug\) failed with exit 3")
}

function New-ShimProduct([string]$Name) {
    # A product with this engine's shims and a .ci-engine checkout of this engine's files at its pin.
    $product = New-Product $Name
    $engine = Join-Path $product.Root '.ci-engine'
    New-Repository $engine
    foreach ($relative in @('Schemas/project.schema.json', 'Schemas/test-scopes.schema.json', 'Tools/Modules/Ci.Policy.psm1', 'Tools/Modules/Ci.EngineBinding.psm1',
            'Tools/Modules/Ci.ScopedTesting.psm1', 'Tools/Modules/Ci.TestRunEvidence.psm1', 'Tools/Modules/Ci.SourceInputs.psm1', 'Tools/Modules/Ci.Changelog.psm1',
            'Tools/Test-Changes.ps1', 'Tools/Test-Changelog.ps1', 'Tools/Invoke-ScopedScript.ps1')) {
        Put $engine $relative ([IO.File]::ReadAllText((Join-Path $engineRoot $relative)))
    }
    Save-Commit $engine 'Fixture engine'
    $pin = (Invoke-FixtureGit $engine @('rev-parse', 'HEAD'))[0].Trim()
    $project = [ordered]@{ schemaVersion = 1; policyVersion = '1'; repository = 'RedSalamanders/RedMonitor'
        engine = [ordered]@{ repository = 'RedSalamanders/.github'; ref = $pin }; kind = 'application'
        adapter = 'Tools/Invoke-ProjectCi.ps1'; include = @('src/**'); exclude = @('CHANGELOG.md', 'Changes/**')
        formatRoots = @('src'); versionBase = '0.1'
        winget = [ordered]@{ identifier = 'RedSalamanders.RedMonitor'; executable = 'RedMonitor.exe'; alias = 'redmonitor' } }
    Put $product.Root '.ci/project.json' (ConvertTo-Json -InputObject $project -Depth 8)
    foreach ($relative in @('Test-Changes.ps1', 'Build/ScopedTesting.psm1', 'Build/TestRunEvidence.psm1')) {
        Put $product.Root $relative ([IO.File]::ReadAllText((Join-Path $engineRoot "Templates/Project/$relative")))
    }
    Save-Commit $product.Root 'Adopt the engine shims'
    [void](Invoke-FixtureGit $product.Root @('update-ref', 'refs/remotes/origin/main', 'HEAD'))
    $product.Command = Join-Path $product.Root 'Test-Changes.ps1'
    $product.Shim = $true
    $product.Module = Join-Path $product.Root 'Build/ScopedTesting.psm1'
    $product | Add-Member -NotePropertyName Engine -NotePropertyValue $engine
    $product | Add-Member -NotePropertyName Pin -NotePropertyValue $pin
    return $product
}

Case 'the root shim runs the pinned engine with its own root, and the module shims export the engine modules' {
    $product = New-ShimProduct 'shim-run'
    Edit-File $product 'src/app.cpp'
    Assert-Run (Invoke-Runner $product @('-Explain', '-Platform', $hostPlatform)) -Output @('src/app.cpp: product source => Core')
    $result = Invoke-Runner $product @('-Platform', $hostPlatform)
    Assert-Run $result -Token 'SELECTED_PASSED' -Output @('PASSED Core')
    Require ($result.Calls -ccontains 'lease re-entered nested=True') "test.ps1 did not re-enter the lease through the module shim: $($result.Calls -join ' | ')"
    Assert-Run (Invoke-Runner $product @('-Platform', $hostPlatform)) -Token 'NOTHING_SELECTED' -Output @('the last successful affected run')
    foreach ($name in @('ScopedTesting', 'TestRunEvidence')) {
        Remove-Module -Name $name -Force -ErrorAction SilentlyContinue
        $shim = Import-Module (Join-Path $product.Root "Build/$name.psm1") -Force -PassThru -Global
        $reference = Import-Module (Join-Path $engineRoot "Tools/Modules/Ci.$name.psm1") -Force -PassThru -Scope Local
        $expected = @($reference.ExportedFunctions.Keys | Sort-Object) -join ','
        Require ((@($shim.ExportedFunctions.Keys | Sort-Object) -join ',') -ceq $expected) "The $name shim exports $(@($shim.ExportedFunctions.Keys) -join ',') instead of $expected."
        Remove-Module $shim.Name -Force -ErrorAction SilentlyContinue
    }
    Import-Module $engineModule -Force
}

Case 'the shims refuse a missing, other-commit or changed engine and a nested copy without its manifest' {
    $product = New-ShimProduct 'shim-refusals'
    Put $product.Engine 'README.md' 'A later engine commit.'
    Save-Commit $product.Engine 'Later'
    $later = (Invoke-FixtureGit $product.Engine @('rev-parse', 'HEAD'))[0].Trim()
    $result = Invoke-Runner $product @('-Explain')
    Assert-Run $result -ExitCode 1 -Output @([regex]::Escape("pins ($($product.Pin))"), "it is at $later", [regex]::Escape("checkout --detach $($product.Pin)"))
    [void](Refuses { Import-Module (Join-Path $product.Root 'Build/ScopedTesting.psm1') -Force } 'runs the shared CI engine')
    [void](Invoke-FixtureGit $product.Engine @('checkout', '-q', '--detach', $product.Pin))
    Assert-Run (Invoke-Runner $product @('-Explain')) -Output @('Test plan')
    Add-Content -LiteralPath (Join-Path $product.Engine 'Tools/Test-Changes.ps1') -Value '# local edit'
    Assert-Run (Invoke-Runner $product @('-Explain')) -ExitCode 1 -Output @('changes to tracked files')
    [void](Invoke-FixtureGit $product.Engine @('checkout', '-q', '--', 'Tools/Test-Changes.ps1'))
    Move-Item -LiteralPath $product.Engine -Destination (Join-Path $product.Root 'engine-away')
    Assert-Run (Invoke-Runner $product @('-Explain')) -ExitCode 1 -Output @('is missing or predates engine shims')
    [void](Refuses { Import-Module (Join-Path $product.Root 'Build/TestRunEvidence.psm1') -Force } 'is missing or predates engine shims')
    Move-Item -LiteralPath (Join-Path $product.Root 'engine-away') -Destination $product.Engine
    $nested = Join-Path $product.Root 'fixture'
    New-Repository $nested
    Put $nested 'Test-Changes.ps1' ([IO.File]::ReadAllText((Join-Path $product.Root 'Test-Changes.ps1')))
    $copy = [pscustomobject]@{ Name = 'shim-nested'; Root = $nested; Log = Join-Path $runRoot 'shim-nested.calls.log'; Module = ''; Command = (Join-Path $nested 'Test-Changes.ps1'); Shim = $true }
    Assert-Run (Invoke-Runner $copy @('-Explain')) -ExitCode 1 -Output @('is missing or predates engine shims')
    Import-Module $engineModule -Force
}

if ($IsWindows) {
    Case 'evidence capture refuses while a watched test executable runs from .build, and records a run otherwise' {
        $product = New-Product 'evidence'
        Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.TestRunEvidence.psm1') -Force
        $artifacts = Join-Path $product.Root '.build/test-artifacts'
        Put $product.Root '.build/test-artifacts/result.txt' 'first'
        $run = Start-TestRunEvidence -Repository $product.Root -Context @{ fixture = 'scoped' } -CaptureNativeArtifacts
        Require ($run.State -ceq 'Active' -and -not $run.Closed) 'New run did not open in Active state.'
        Publish-TestRunEvidenceReceipt -Run $run -Name 'fixture-suites.json' -Receipt ([ordered]@{ passed = $true })
        Complete-TestRunEvidence -Run $run -Passed $true
        Require ($run.State -ceq 'Completed' -and $run.Closed) 'Verified pass did not close as Completed.'
        [void](Refuses { Complete-TestRunEvidence -Run $run -Passed $true } 'already been closed')
        [void](Refuses { Publish-TestRunEvidenceReceipt -Run $run -Name 'second.json' -Receipt @{} } 'Invalid receipt publication')

        $failedRun = Start-TestRunEvidence -Repository $product.Root -Context @{ fixture = 'failed' }
        Complete-TestRunEvidence -Run $failedRun -Passed $false
        Require ($failedRun.State -ceq 'Failed' -and $failedRun.Closed) 'Verified failure did not close as Failed.'

        $interrupted = Start-TestRunEvidence -Repository $product.Root -Context @{ fixture = 'interrupted' }
        $path = Join-Path $interrupted.Path 'still-writing.log'
        $writer = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            [void](Refuses { Complete-TestRunEvidence -Run $interrupted -Passed $true } '')
            Require ($interrupted.State -ceq 'Interrupted' -and $interrupted.Closed) 'Failed verification did not close as Interrupted.'
            Require (-not [IO.File]::Exists((Join-Path $interrupted.Directory 'completed.json'))) 'Interrupted verification wrote completion evidence.'
        } finally { $writer.Dispose() }
        Require ([IO.File]::Exists((Join-Path $run.Path 'previous-native-artifacts/result.txt'))) 'Earlier native artifacts were not preserved in the run.'
        Require ([IO.File]::Exists((Join-Path $run.Directory 'completed.json')) -and [IO.File]::Exists((Join-Path $product.Root '.build/reports/fixture-suites.json'))) 'The run or its receipt is missing.'
        Put $product.Root '.build/test-artifacts/result.txt' 'second'
        $probe = Join-Path $product.Root '.build/x64/Debug/fixture-probe.exe'
        [void][IO.Directory]::CreateDirectory((Split-Path $probe))
        [IO.File]::Copy((Join-Path $env:SystemRoot 'System32/PING.EXE'), $probe)
        $start = [Diagnostics.ProcessStartInfo]::new($probe)
        foreach ($argument in @('-n', '60', '127.0.0.1')) { $start.ArgumentList.Add($argument) }
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $process = [Diagnostics.Process]::Start($start)
        try {
            [void](Refuses { Start-TestRunEvidence -Repository $product.Root -Context @{} -CaptureNativeArtifacts } 'Native artifact output is in use')
        } finally { if (-not $process.HasExited) { $process.Kill() }; $process.WaitForExit(); $process.Dispose() }
        Require ([IO.File]::ReadAllText((Join-Path $artifacts 'result.txt')) -ceq 'second') 'A refused capture moved the artifacts.'
        Put $product.Root 'Tests/test-scopes.json' '{"version":1}'
        [void](Refuses { Start-TestRunEvidence -Repository $product.Root -Context @{} -CaptureNativeArtifacts } 'needs valid scoped testing data')
    }
} else { Skip 'evidence capture refuses while a watched test executable runs from .build, and records a run otherwise' 'Windows file identity APIs' }

$failed = @($rows | Where-Object { -not $_.passed }).Count
[IO.File]::WriteAllText((Join-Path $runRoot 'results.json'), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; passed = $failed -eq 0; executed = $rows.Count; failed = $failed; cases = $rows.ToArray() }) -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Host "Scoped testing: $($rows.Count - $failed) passed, $failed failed. Results: $runRoot"
if ($failed) { throw "$failed scoped-testing case(s) failed; preserve $runRoot." }
