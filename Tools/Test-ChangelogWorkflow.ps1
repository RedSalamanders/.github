<#
.SYNOPSIS
Runs the shared Changes behavior fixtures without a native build or external test framework.
.DESCRIPTION
Creates uniquely owned fixture directories beneath an existing caller-owned scratch root.
Never reads or changes the application's changelog. Removes only its own direct fixture children.
Covers this engine's changelog commands and the product shims of Templates/Project/Tools, including their refusal of
a missing, other-commit or changed engine checkout. With ProjectRoot, which the product's own
Tools/Test-ChangelogWorkflow.ps1 shim supplies, it also proves that product's shims equal those templates and that its
PrePush runner validates the changelog first (Specs/ProjectCommands.md).
.PARAMETER ScratchRoot
Existing test scratch parent supplied by the repository's test harness.
.PARAMETER ProjectRoot
Optional product checkout whose shims and PrePush runner are checked as well. Read only; its changelog is never read.
.OUTPUTS
Console case results; throws if any assertion fails. Fixture files are removed on completion.
.NOTES
Requires PowerShell 7 and Git for its local fixture repositories, which use a fixed identity and none of the
person's hooks or signing. No network, native code, application processes or desktop input.
.EXAMPLE
./Tools/Test-ChangelogWorkflow.ps1 -ScratchRoot <existing-test-scratch-directory>
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string] $ScratchRoot, [string] $ProjectRoot = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$engine = Split-Path $PSScriptRoot -Parent
$changelogModule = Import-Module (Join-Path $engine 'Tools/Modules/Ci.Changelog.psm1') -PassThru
$fold = Join-Path $engine 'Tools/Fold-Changelog.ps1'
$validate = Join-Path $engine 'Tools/Test-Changelog.ps1'
$submit = Join-Path $engine 'Tools/Submit-ChangelogFold.ps1'
$release = Join-Path $engine 'Tools/Release-Changelog.ps1'
# What a product's .ci-engine needs for its changelog shims, and the shims themselves.
$engineFiles = @('Schemas/project.schema.json', 'Tools/Modules/Ci.Policy.psm1', 'Tools/Modules/Ci.EngineBinding.psm1',
    'Tools/Modules/Ci.Changelog.psm1', 'Tools/Fold-Changelog.ps1', 'Tools/Test-Changelog.ps1', 'Tools/Submit-ChangelogFold.ps1',
    'Tools/Release-Changelog.ps1')
$shims = @('Tools/Fold-Changelog.ps1', 'Tools/Test-Changelog.ps1', 'Tools/Submit-ChangelogFold.ps1', 'Tools/Release-Changelog.ps1',
    'Tools/Test-ChangelogWorkflow.ps1')
$parent = [IO.Path]::GetFullPath($ScratchRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
if (-not [IO.Directory]::Exists($parent)) { throw "Scratch root must already exist: $parent" }
if ($ProjectRoot) {
    $ProjectRoot = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProjectRoot))
    if (-not [IO.File]::Exists((Join-Path $ProjectRoot '.ci/project.json'))) { throw "ProjectRoot is not a product checkout with .ci/project.json: $ProjectRoot" }
    # A repository adapter supplies its existing scratch root. Honor the stricter marked-sandbox policy where installed.
    $sandboxModule = Join-Path $ProjectRoot 'Tools/Modules/Testing/TestSandbox.psm1'
    if ([IO.File]::Exists($sandboxModule)) {
        Import-Module $sandboxModule
        $testRoot = Get-RSTestSandboxRoot -RepoRoot $ProjectRoot
        [void](Assert-RSTestSandboxContainedPath -TestRoot $testRoot -Path $parent -RequireDescendant)
    }
}
$results = [Collections.Generic.List[string]]::new()
$failures = [Collections.Generic.List[string]]::new()

function Assert([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Refuses([scriptblock] $Body) {
    $refused = $false
    try { & $Body | Out-Null } catch { $refused = $true }
    Assert $refused 'Expected the operation to refuse'
}
function Put([string] $Root, [string] $Name, [string] $Text) {
    $path = Join-Path $Root $Name
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
}
function Snapshot([string] $Root) {
    return (@(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Name -ne '.changelog-fold.lock' -and $_.FullName -notmatch '[\\/]\.git([\\/]|$)' } | Sort-Object FullName | ForEach-Object {
        [IO.Path]::GetRelativePath($Root, $_.FullName) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}
function Invoke-FixtureGit([string] $Root, [string[]] $Arguments) {
    $output = @(& git -C $Root @Arguments 2>&1 | ForEach-Object { "$_" })
    Assert ($LASTEXITCODE -eq 0) "git $($Arguments -join ' ') failed in ${Root}: $($output -join ' ')"
    return , $output
}
function Get-FixtureGitLines([string] $Root, [string[]] $Arguments, [string] $Like = '*') {
    # Nonempty output lines as an array. Assigned first: piping the comma-wrapped array would make it one item.
    $lines = Invoke-FixtureGit $Root $Arguments
    return , [string[]]@($lines | Where-Object { $_ -and $_ -like $Like })
}
function New-FixtureRepository([string] $Path, [switch] $Bare) {
    # A throwaway repository: a fixed identity, exact bytes, and none of the person's global hooks or signing.
    [void][IO.Directory]::CreateDirectory($Path)
    [void](Invoke-FixtureGit $Path @(@('init', '-q') + $(if ($Bare) { @('--bare') } else { @() }) + @('-b', 'main')))
    foreach ($setting in @(@('user.name', 'Changelog fixture'), @('user.email', 'changelog@fixture.invalid'), @('commit.gpgsign', 'false'),
            @('tag.gpgsign', 'false'), @('core.autocrlf', 'false'), @('core.longpaths', 'true'), @('core.hooksPath', (Join-Path $Path '.no-hooks')))) {
        [void](Invoke-FixtureGit $Path (@('config') + $setting))
    }
}
function New-FixtureJunction([string] $Path, [string] $Target) {
    # Through the governed link creator where the repository has one, so its sandbox policy sees every test link.
    if (Get-Command New-RSTestSandboxLink -ErrorAction SilentlyContinue) { [void](New-RSTestSandboxLink -Path $Path -Target $Target -ItemType Junction) }
    else { [void](New-Item -ItemType Junction -Path $Path -Target $Target) }
}
function New-FoldFixture([string] $Root) {
    # A bare origin and a clone whose default branch holds two merged fragments. The submission folds with this
    # engine's own commands, so the default branch needs no tooling of its own.
    $origin = Join-Path $Root 'origin.git'
    $clone = Join-Path $Root 'clone'
    New-FixtureRepository $origin -Bare
    New-FixtureRepository $clone
    foreach ($relative in @('Changes/README.md', 'CHANGELOG.md')) { Put $clone $relative ([IO.File]::ReadAllText((Join-Path $Root $relative))) }
    Put $clone 'Changes/2026-10-20-first.md' '- First.'
    Put $clone 'Changes/2026-10-21-second.md' "- Second.`n  Detail."
    [void](Invoke-FixtureGit $clone @('add', '--all'))
    [void](Invoke-FixtureGit $clone @('commit', '-q', '-m', 'Merged changes'))
    # Relative, so the receiving repository path stays short however deep the scratch root is: Git for Windows refuses
    # a $GIT_DIR near 260 characters.
    [void](Invoke-FixtureGit $clone @('remote', 'add', 'origin', '../origin.git'))
    [void](Invoke-FixtureGit $clone @('push', '-q', 'origin', 'main'))
    $head = (Invoke-FixtureGit $clone @('rev-parse', 'HEAD'))[0].Trim()
    # The submission's temporary worktrees stay inside this fixture, never in the person's temporary folder. A short
    # name and long-path support keep a deep scratch root within Windows path limits.
    $worktrees = Join-Path $Root 'wt'
    [void][IO.Directory]::CreateDirectory($worktrees)
    return [pscustomobject]@{ Origin = $origin; Clone = $clone; Head = $head; FoldBranch = 'changelog/fold-' + $head.Substring(0, 12); WorktreeParent = $worktrees }
}
function New-ShimProduct([string] $Root) {
    # A product checkout holding the changelog shims (the product's own with ProjectRoot, else this engine's templates)
    # and an independent .ci-engine checkout of this engine's changelog files, committed and pinned by its manifest
    # (the product's own manifest with ProjectRoot). Returns the pin.
    New-FixtureRepository $Root
    $engineCheckout = Join-Path $Root '.ci-engine'
    New-FixtureRepository $engineCheckout
    foreach ($relative in $engineFiles) { Put $engineCheckout $relative ([IO.File]::ReadAllText((Join-Path $engine $relative))) }
    [void](Invoke-FixtureGit $engineCheckout @('add', '--all'))
    [void](Invoke-FixtureGit $engineCheckout @('commit', '-q', '-m', 'Fixture engine'))
    $pin = (Invoke-FixtureGit $engineCheckout @('rev-parse', 'HEAD'))[0].Trim()
    $project = if ($ProjectRoot) { [IO.File]::ReadAllText((Join-Path $ProjectRoot '.ci/project.json')) | ConvertFrom-Json -AsHashtable }
        else {
            [ordered]@{ schemaVersion = 1; policyVersion = '1'; repository = 'RedSalamanders/RedMonitor';
                engine = [ordered]@{ repository = 'RedSalamanders/.github'; ref = ('a' * 40) }; kind = 'application';
                adapter = 'Tools/Invoke-ProjectCi.ps1'; include = @('Tests/fixtures/**'); exclude = @('CHANGELOG.md', 'Changes/**');
                formatRoots = @('src'); versionBase = '0.1';
                winget = [ordered]@{ identifier = 'RedSalamanders.RedMonitor'; executable = 'RedMonitor.exe'; alias = 'redmonitor' } }
        }
    $project.engine.ref = $pin
    Put $Root '.ci/project.json' ($project | ConvertTo-Json -Depth 10)
    foreach ($relative in $shims) {
        $source = if ($ProjectRoot) { Join-Path $ProjectRoot $relative } else { Join-Path $engine "Templates/Project/$relative" }
        Put $Root $relative ([IO.File]::ReadAllText($source))
    }
    Put $Root '.gitignore' ".ci-engine/`n"
    return $pin
}
function Assert-NoFoldWorktree($Fixture) {
    $left = @(Get-ChildItem -LiteralPath $Fixture.WorktreeParent -Force | ForEach-Object { $_.Name })
    Assert ($left.Count -eq 0) "A temporary fold worktree was left behind: $($left -join ', ')"
}
function Save-FixtureBase([string] $Root) {
    # Commit everything as the default branch the comparisons and the runner read as origin/main.
    [void](Invoke-FixtureGit $Root @('add', '--all'))
    [void](Invoke-FixtureGit $Root @('commit', '-q', '-m', 'Fixture base'))
    [void](Invoke-FixtureGit $Root @('update-ref', 'refs/remotes/origin/main', 'HEAD'))
}
function Reset-FixtureBase([string] $Root) {
    [void](Invoke-FixtureGit $Root @('reset', '-q', '--hard', 'refs/remotes/origin/main'))
    [void](Invoke-FixtureGit $Root @('clean', '-q', '-f', '-d'))
}
function Edit-Fixture([string] $Root, [string] $Name, [string] $Old, [string] $New) {
    $path = Join-Path $Root $Name
    $text = [IO.File]::ReadAllText($path)
    Assert ($text.Contains($Old)) "Fixture $Name lacks '$Old'"
    [IO.File]::WriteAllText($path, $text.Replace($Old, $New), [Text.UTF8Encoding]::new($false))
}
function Invoke-FixtureProcess([Diagnostics.ProcessStartInfo] $Start,
    [ValidateRange(1,180000)][int] $TimeoutMilliseconds = 30000, [ref] $ProcessIdentity) {
    # This standalone cross-project suite owns this synthetic child; repository-specific native runners are not dependencies.
    $process = [Diagnostics.Process]::Start($Start)
    try {
        if ($ProcessIdentity) {
            $ProcessIdentity.Value = @{ Id = $process.Id; StartTicks = $process.StartTime.ToUniversalTime().Ticks }
        }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        Assert ($process.WaitForExit($TimeoutMilliseconds)) 'Fixture child did not exit within its budget'
        $drain = [Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout, $stderr))
        Assert ($drain.Wait(5000)) 'Fixture child pipes did not close within their drain budget'
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult() }
    } finally {
        try {
            if (-not $process.HasExited) {
                $process.Kill($true)
                Assert ($process.WaitForExit(5000)) 'Owned fixture child did not terminate within its cleanup budget'
            }
        } finally { $process.Dispose() }
    }
}
function Case([string] $Name, [scriptblock] $Body) {
    $root = Join-Path $parent ('changelog-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    try {
        Put $root 'Changes/README.md' "# Changelog fragments`n"
        Put $root 'CHANGELOG.md' "# Changelog`n`n## Unreleased`n`n- Existing.`n`n## 1.0`n`n- Released.`n"
        & $Body $root
        $results.Add($Name)
        Write-Host "PASS changelog: $Name"
    } catch { $failures.Add("${Name}: $($_.Exception.Message)"); Write-Host "FAIL changelog: $($failures[-1])" }
    finally {
        $resolved = [IO.Path]::GetFullPath($root)
        if ([IO.Path]::GetDirectoryName($resolved) -cne $parent -or [IO.Path]::GetFileName($resolved) -notmatch '^changelog-[0-9a-f]{32}$') {
            throw "Refusing fixture cleanup outside its exact scratch parent: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

Case 'editing permits one valid dated Unicode change' {
    param($r)
    Put $r 'Changes/2026-10-21-unicode.md' "- Preserve café and 日本語.`n  Validation remains explicit.`n  - Pending native gates.`n"
    & $validate -Root $r
    Assert ((Get-ChangelogProblems $r).Count -eq 0) 'Valid change was rejected'
}
foreach ($bad in @(
    @{Name='notes.md'; Text='- Fine.'}, @{Name='2026-02-30-invalid.md'; Text='- Fine.'},
    @{Name='2026-10-21-Upper.md'; Text='- Fine.'}, @{Name='2026-10-21-empty.md'; Text=''},
    @{Name='2026-10-21-blank-bullet.md'; Text='- '}, @{Name='2026-10-21-paragraph.md'; Text='No bullet'},
    @{Name='2026-10-21-two.md'; Text="- One.`n- Two."}, @{Name='2026-10-21-margin.md'; Text="- One.`nAt margin."}
)) {
    Case "reject $($bad.Name) without mutation" {
        param($r)
        Put $r ('Changes/' + $bad.Name) $bad.Text
        $before = Snapshot $r
        Refuses { & $fold -Root $r }
        Refuses { & $validate -Root $r }
        Assert ((Snapshot $r) -ceq $before) 'Invalid input mutated files'
    }
}
Case 'single-fragment final gate is read-only and requires folding' {
    param($r)
    Put $r 'Changes/2026-10-21-single.md' '- Single.'
    $before = Snapshot $r
    Refuses { & $fold -Root $r -Check }
    Refuses { & $validate -Root $r -RequireFolded }
    Assert ((Snapshot $r) -ceq $before) 'Read-only gate mutated files'
    & $fold -Root $r
    & $fold -Root $r -Check
    Assert ([IO.File]::ReadAllText((Join-Path $r 'CHANGELOG.md')).Contains('- Single.')) 'Single entry was lost'
}
Case 'preview writes nothing' {
    param($r)
    Put $r 'Changes/2026-10-21-preview.md' '- Preview.'
    $before = Snapshot $r
    & $fold -Root $r -WhatIf
    Assert ((Snapshot $r) -ceq $before) 'WhatIf mutated files'
}
Case 'relative roots follow PowerShell location without touching the process directory' {
    param($r)
    $processRoot = Join-Path $r 'process-checkout'
    $requestedRoot = Join-Path $r 'requested-checkout'
    foreach ($checkout in @($processRoot, $requestedRoot)) {
        Put $checkout 'Changes/README.md' '# Fragments'
        Put $checkout 'CHANGELOG.md' "# Changelog`n`n## Unreleased`n`n- Existing.`n"
    }
    Put $requestedRoot 'Changes/2026-10-21-relative.md' '- Requested checkout only.'
    $processBefore = Snapshot $processRoot
    $requestedBefore = Snapshot $requestedRoot
    $previousDirectory = [Environment]::CurrentDirectory
    Push-Location -LiteralPath $requestedRoot
    try {
        [Environment]::CurrentDirectory = $processRoot
        Refuses { & $validate -Root . -RequireFolded }
        Refuses { & $fold -Root . -Check }
        & $fold -Root . -WhatIf
        Assert ((Snapshot $requestedRoot) -ceq $requestedBefore) 'Relative preview mutated the requested checkout'
        & $fold -Root .
        & $validate -Root . -RequireFolded
        Assert ([IO.File]::ReadAllText((Join-Path $requestedRoot 'CHANGELOG.md')).Contains('- Requested checkout only.')) 'Relative fold did not publish to the requested checkout'
        Assert ((Snapshot $processRoot) -ceq $processBefore) 'Relative command touched the process-directory checkout'
    } finally {
        [Environment]::CurrentDirectory = $previousDirectory
        Pop-Location
    }
}
Case 'newest first, stable topic order, preserve released history and README' {
    param($r)
    Put $r 'Changes/2026-10-20-old.md' '- Older.'
    Put $r 'Changes/2026-10-21-a.md' '- A.'
    Put $r 'Changes/2026-10-21-b.md' "- B.`n  Detail."
    & $fold -Root $r
    $text = [IO.File]::ReadAllText((Join-Path $r 'CHANGELOG.md'))
    Assert ($text -ceq "# Changelog`n`n## Unreleased`n`n- B.`n  Detail.`n- A.`n- Older.`n- Existing.`n`n## 1.0`n`n- Released.`n") 'Fold order/history differs'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $r 'Changes') -Force).Count -eq 1) 'Fold left fragments or removed README'
    $before = Snapshot $r
    & $fold -Root $r
    Assert ((Snapshot $r) -ceq $before) 'Empty repeat mutated files'
}
Case 'preserve BOM, CRLF and Unicode bytes' {
    param($r)
    $path = Join-Path $r 'CHANGELOG.md'
    [IO.File]::WriteAllText($path, "# Changelog`r`n`r`n## Unreleased`r`n`r`n", [Text.UTF8Encoding]::new($true))
    Put $r 'Changes/2026-10-21-encoding.md' "- café 日本語.`n  More.`n"
    & $fold -Root $r
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'BOM was lost'
    Assert ([IO.File]::ReadAllText($path) -ceq "# Changelog`r`n`r`n## Unreleased`r`n`r`n- café 日本語.`r`n  More.`r`n") 'Encoding or EOL changed'
}
Case 'retry after publication cleans fragments without duplicate entries' {
    param($r)
    Put $r 'Changes/2026-10-21-retry.md' "- Existing.`n"
    $warnings = @(& $fold -Root $r 3>&1 | Where-Object { $_ -is [Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
    Assert (($warnings -join ' ').Contains('skipping Changes/2026-10-21-retry.md')) "The skipped fragment was not named: $($warnings -join ' | ')"
    $text = [IO.File]::ReadAllText((Join-Path $r 'CHANGELOG.md'))
    Assert ([regex]::Matches($text, '(?m)^- Existing\.$').Count -eq 1) 'Retry duplicated a published entry'
}
Case 'identical pending fragments are refused before publishing or removing either input' {
    param($r)
    Put $r 'Changes/2026-10-21-first.md' "- Shared entry.`n  Same details.`n"
    Put $r 'Changes/2026-10-22-second.md' "- Shared entry.`n  Same details.`n"
    $before = Snapshot $r
    Refuses { & $fold -Root $r }
    Assert ((Snapshot $r) -ceq $before) 'Ambiguous duplicate fragments changed the changelog or removed an input'
    Assert ([IO.File]::Exists((Join-Path $r 'Changes/2026-10-21-first.md'))) 'First duplicate fragment was removed'
    Assert ([IO.File]::Exists((Join-Path $r 'Changes/2026-10-22-second.md'))) 'Second duplicate fragment was removed'
}
foreach ($separator in @(@{Name='space'; Text=' '}, @{Name='tab'; Text="`t"})) {
    Case "released heading with $($separator.Name) does not suppress a new entry" {
        param($r)
        Put $r 'CHANGELOG.md' ("# Changelog`n`n## Unreleased`n`n- Existing.`n`n##" + $separator.Text + "1.0`n`n- Released.`n")
        Put $r 'Changes/2026-10-21-again.md' '- Released.'
        & $fold -Root $r
        Assert ([regex]::Matches([IO.File]::ReadAllText((Join-Path $r 'CHANGELOG.md')), '(?m)^- Released\.$').Count -eq 2) 'Released history suppressed a new entry'
    }
}
Case 'missing README, invalid headings, unexpected files and directories fail' {
    param($r)
    Remove-Item -LiteralPath (Join-Path $r 'Changes/README.md')
    Assert ((Get-ChangelogProblems $r).Count -gt 0) 'Missing README passed'
    Put $r 'Changes/README.md' '# Restored'
    foreach ($text in @('# No heading', "## Unreleased`n`n## Unreleased`n")) {
        Put $r 'CHANGELOG.md' $text
        Refuses { & $fold -Root $r }
    }
    Put $r 'CHANGELOG.md' "# Changelog`n`n## Unreleased`n"
    Put $r 'Changes/notes.txt' 'Unsupported'
    Assert ((Get-ChangelogProblems $r).Count -gt 0) 'Unexpected file passed'
    Remove-Item -LiteralPath (Join-Path $r 'Changes/notes.txt')
    [void][IO.Directory]::CreateDirectory((Join-Path $r 'Changes/nested'))
    Assert ((Get-ChangelogProblems $r).Count -gt 0) 'Nested directory passed'
}
Case 'overlapping fold fails without touching inputs' {
    param($r)
    Put $r 'Changes/2026-10-21-lock.md' '- Locked.'
    $lease = [IO.File]::Open((Join-Path $r '.changelog-fold.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        $before = Snapshot $r
        Refuses { & $fold -Root $r }
        Assert ((Snapshot $r) -ceq $before) 'Contended fold changed input'
    } finally { $lease.Dispose() }
}
Case 'Unreleased heading at EOF is supported' {
    param($r)
    Put $r 'CHANGELOG.md' "# Changelog`n`n## Unreleased"
    Put $r 'Changes/2026-10-21-eof.md' '- EOF.'
    & $fold -Root $r
    Assert ([IO.File]::ReadAllText((Join-Path $r 'CHANGELOG.md')) -ceq "# Changelog`n`n## Unreleased`n`n- EOF.`n") 'EOF heading merged incorrectly'
}
Case 'CHANGELOG.md changes only by an exact fold of fragments the merge base holds' {
    param($r)
    New-FixtureRepository $r
    Put $r 'CHANGELOG.md' "# Changelog`n`n## Unreleased`n`n- Existing.`n- Second existing.`n`n## 1.0`n`n- Released.`n"
    Put $r 'Changes/2026-10-20-merged.md' "- Merged earlier.`n  With detail.`n"
    Save-FixtureBase $r
    # A feature change adds a fragment and leaves CHANGELOG.md alone.
    Put $r 'Changes/2026-10-21-feature.md' '- Feature.'
    Assert ((Get-ChangelogFoldProblems $r 'origin/main').Count -eq 0) 'An added fragment was refused'
    & $validate -Root $r -Base origin/main
    # The fold on the default branch: the merged fragment leaves, its entry arrives; line endings never count.
    Reset-FixtureBase $r
    & $fold -Root $r
    Assert ((Get-ChangelogFoldProblems $r 'origin/main').Count -eq 0) 'An exact fold was refused'
    $folded = Join-Path $r 'CHANGELOG.md'
    [IO.File]::WriteAllText($folded, ([IO.File]::ReadAllText($folded) -replace '\r?\n', "`r`n"))
    Assert ((Get-ChangelogFoldProblems $r 'origin/main').Count -eq 0) 'A line-ending-only difference was refused'
    # A renamed pending fragment keeps its text.
    Reset-FixtureBase $r
    Move-Item -LiteralPath (Join-Path $r 'Changes/2026-10-20-merged.md') -Destination (Join-Path $r 'Changes/2026-10-20-renamed.md')
    Assert ((Get-ChangelogFoldProblems $r 'origin/main').Count -eq 0) 'A renamed fragment was refused'
    foreach ($bad in @(
        @{ Name = 'a hand edit'; Expect = 'added by hand'; Change = { param($c) Edit-Fixture $c 'CHANGELOG.md' '- Existing.' "- Hand edit.`n- Existing." } },
        @{ Name = 'a fold of a fragment this change adds'; Expect = 'added by hand or folded from a fragment this change adds'; Change = { param($c) Put $c 'Changes/2026-10-21-new.md' '- New.'; & $fold -Root $c } },
        @{ Name = 'an edited entry'; Expect = 'was edited or removed'; Change = { param($c) Edit-Fixture $c 'CHANGELOG.md' '- Existing.' '- Existing, edited.' } },
        @{ Name = 'a released-history edit'; Expect = 'changed outside its Unreleased entries'; Change = { param($c) Edit-Fixture $c 'CHANGELOG.md' '- Released.' '- Released, edited.' } },
        @{ Name = 'an Unreleased paragraph'; Expect = 'changed outside its Unreleased entries'; Change = { param($c) Edit-Fixture $c 'CHANGELOG.md' "## Unreleased`n`n" "## Unreleased`n`nA note.`n`n" } },
        @{ Name = 'an unfolded removal'; Expect = 'was removed since origin/main without its entry'; Change = { param($c) Remove-Item -LiteralPath (Join-Path $c 'Changes/2026-10-20-merged.md') } },
        @{ Name = 'a duplicated folded entry'; Expect = 'is not the exact fold'; Change = { param($c) & $fold -Root $c; Edit-Fixture $c 'CHANGELOG.md' "- Merged earlier.`n  With detail.`n" "- Merged earlier.`n  With detail.`n- Merged earlier.`n  With detail.`n" } },
        @{ Name = 'reordered entries'; Expect = 'is not the exact fold'; Change = { param($c) Edit-Fixture $c 'CHANGELOG.md' "- Existing.`n- Second existing.`n" "- Second existing.`n- Existing.`n" } })) {
        Reset-FixtureBase $r
        & $bad.Change $r
        $problems = Get-ChangelogFoldProblems $r 'origin/main'
        Assert (@($problems | Where-Object { $_.Contains($bad.Expect) }).Count -eq 1) "$($bad.Name) was not refused as expected: $($problems -join ' | ')"
        Refuses { & $validate -Root $r -Base origin/main }
    }
    Reset-FixtureBase $r
    Refuses { & $validate -Root $r -Base refs/heads/no-such-base }
}
Case 'an unreadable base changelog fails closed instead of reading as absent' {
    param($r)
    New-FixtureRepository $r
    Save-FixtureBase $r
    # The base's CHANGELOG.md blob is missing from the object store, as after a failed promisor fetch.
    $blob = (Invoke-FixtureGit $r @('rev-parse', 'HEAD:CHANGELOG.md'))[0].Trim()
    Put $r 'CHANGELOG.md' "# Changelog`n`n## Unreleased`n`n- Hand edit.`n"
    [void](Invoke-FixtureGit $r @('commit', '-q', '-a', '-m', 'Different head blob'))
    Remove-Item -LiteralPath (Join-Path $r ".git/objects/$($blob.Substring(0, 2))/$($blob.Substring(2))") -Force
    $problems = Get-ChangelogFoldProblems $r 'origin/main'
    Assert (@($problems | Where-Object { $_.Contains('cat-file') }).Count -eq 1) "A missing base object was read as no changelog: $($problems -join ' | ')"
    Refuses { & $validate -Root $r -Base origin/main }
    # A base without CHANGELOG.md is still the adoption case.
    $fresh = Join-Path $r 'fresh'
    New-FixtureRepository $fresh
    Put $fresh 'README.md' 'Before adoption.'
    Save-FixtureBase $fresh
    Put $fresh 'Changes/README.md' '# Fragments'
    Put $fresh 'CHANGELOG.md' "# Changelog`n`n## Unreleased`n"
    Assert ((Get-ChangelogFoldProblems $fresh 'origin/main').Count -eq 0) 'Adopting the changelog was refused'
}
Case 'a release cut is generated exactly and preserves prior history' {
    param($r)
    New-FixtureRepository $r
    Put $r 'CHANGELOG.md' "# Changelog`n`n## Unreleased`n`n- First.`n- Second.`n`n## 1.0.0 - 2026-10-01`n`n- Previous.`n"
    Save-FixtureBase $r
    $before = Snapshot $r
    & $release -Root $r -Version '1.1.0' -Date '2026-11-01' -WhatIf
    Assert ((Snapshot $r) -ceq $before) 'Release WhatIf changed inputs'
    Refuses { & $release -Root $r -Version '1.01.0' -Date '2026-11-01' }
    Refuses { & $release -Root $r -Version '1.1.0-01' -Date '2026-11-01' }
    Refuses { & $release -Root $r -Version '1.0.0' -Date '2026-11-01' }
    Refuses { & $release -Root $r -Version '1.1.0' -Date '2026-02-30' }
    Put $r 'Changes/2026-10-31-pending.md' '- Pending.'
    Refuses { & $release -Root $r -Version '1.1.0' -Date '2026-11-01' }
    Remove-Item -LiteralPath (Join-Path $r 'Changes/2026-10-31-pending.md')
    & $release -Root $r -Version '1.1.0' -Date '2026-11-01'
    $text = [IO.File]::ReadAllText((Join-Path $r 'CHANGELOG.md'))
    Assert ($text -ceq "# Changelog`n`n## Unreleased`n`n## 1.1.0 - 2026-11-01`n`n- First.`n- Second.`n`n## 1.0.0 - 2026-10-01`n`n- Previous.`n") 'Release did not preserve exact content and history'
    Assert ((Get-ChangelogFoldProblems $r 'origin/main').Count -eq 0) 'The exact generated release was refused'
    [void](Invoke-FixtureGit $r @('add', 'CHANGELOG.md'))
    [void](Invoke-FixtureGit $r @('commit', '-q', '-m', 'generated release'))
    [void](Invoke-FixtureGit $r @('update-ref', 'refs/remotes/origin/main', 'HEAD'))
    Put $r 'Changes/2026-11-01-next.md' '- Next feature.'
    Assert ((Get-ChangelogFoldProblems $r 'origin/main').Count -eq 0) 'A later feature after a release was refused'
    Remove-Item -LiteralPath (Join-Path $r 'Changes/2026-11-01-next.md')
    Edit-Fixture $r 'CHANGELOG.md' '- Previous.' '- Changed previous.'
    Refuses { & $validate -Root $r -Base origin/main }
}
Case 'a fold stays exact when the default branch meanwhile gains a fragment with the same text' {
    param($r)
    New-FixtureRepository $r
    Put $r 'Changes/2026-10-20-first.md' '- Same text.'
    Put $r 'Changes/2026-10-21-second.md' '- Same text.'
    Save-FixtureBase $r
    # The fold of the first fragment, merged after the second one reached the default branch: the survivor is not a
    # rename, so the published entry is the exact fold.
    Remove-Item -LiteralPath (Join-Path $r 'Changes/2026-10-20-first.md')
    Edit-Fixture $r 'CHANGELOG.md' "## Unreleased`n`n" "## Unreleased`n`n- Same text.`n"
    $problems = Get-ChangelogFoldProblems $r 'origin/main'
    Assert ($problems.Count -eq 0) "A valid fold was refused because another fragment has the same text: $($problems -join ' | ')"
    # Without the entry the same removal is still a rename.
    Reset-FixtureBase $r
    Remove-Item -LiteralPath (Join-Path $r 'Changes/2026-10-20-first.md')
    $problems = Get-ChangelogFoldProblems $r 'origin/main'
    Assert ($problems.Count -eq 0) "A rename beside an identical fragment was refused: $($problems -join ' | ')"
}
Case 'fold submission pushes one exact fold branch and leaves the caller checkout untouched' {
    param($r)
    $fixture = New-FoldFixture $r
    $origin = $fixture.Origin
    $clone = $fixture.Clone
    # A registered worktree whose folder is unavailable (an offline drive) must keep its registration.
    $offline = Join-Path $r 'offline-worktree'
    [void](Invoke-FixtureGit $clone @('worktree', 'add', '-q', '--detach', $offline, 'HEAD'))
    Remove-Item -LiteralPath $offline -Recurse -Force
    $registrations = Get-FixtureGitLines $clone @('worktree', 'list', '--porcelain') 'worktree *'
    Assert ($registrations.Count -eq 2) "The unavailable worktree was not registered: $($registrations -join ', ')"
    $before = Snapshot $clone
    $head = $fixture.Head
    $foldBranch = $fixture.FoldBranch
    $output = (& $submit -Root $clone -WorktreeParent $fixture.WorktreeParent -PushOnly -WhatIf 6>&1) -join "`n"
    Assert ($output.Contains(" in $(Join-Path $fixture.WorktreeParent 'changelog-fold-')")) "The fold worktree was not created in the sandbox folder it was given: $output"
    Assert ((Get-FixtureGitLines $origin @('branch', '--list', 'changelog/fold-*')).Count -eq 0) 'WhatIf pushed a fold branch'
    & $submit -Root $clone -WorktreeParent $fixture.WorktreeParent -PushOnly
    $changelog = (Invoke-FixtureGit $origin @('show', "${foldBranch}:CHANGELOG.md")) -join "`n"
    Assert ($changelog.Contains("## Unreleased`n`n- Second.`n  Detail.`n- First.`n- Existing.")) "The fold branch does not hold the exact fold: $changelog"
    $files = Get-FixtureGitLines $origin @('ls-tree', '--name-only', "${foldBranch}:Changes")
    Assert ($files.Count -eq 1 -and $files[0] -ceq 'README.md') "The fold branch kept fragments: $($files -join ', ')"
    Assert ((Snapshot $clone) -ceq $before) 'Submission changed the caller checkout files'
    Assert ((Invoke-FixtureGit $clone @('rev-parse', 'HEAD'))[0].Trim() -ceq $head) 'Submission moved the caller HEAD'
    Assert ((Get-FixtureGitLines $clone @('status', '--porcelain')).Count -eq 0) 'Submission left the caller checkout dirty'
    $after = Get-FixtureGitLines $clone @('worktree', 'list', '--porcelain') 'worktree *'
    Assert (($after -join "`n") -ceq ($registrations -join "`n")) "Submission left a temporary worktree or pruned another registration: $($after -join ', ')"
    & $submit -Root $clone -WorktreeParent $fixture.WorktreeParent -PushOnly
    $branches = Get-FixtureGitLines $origin @('branch', '--list', 'changelog/fold-*')
    Assert ($branches.Count -eq 1) "A repeated submission pushed a second fold branch: $($branches -join ', ')"
    # Once the fold is merged, the default branch has nothing left to fold.
    [void](Invoke-FixtureGit $origin @('update-ref', 'refs/heads/main', "refs/heads/$foldBranch"))
    $output = (& $submit -Root $clone -WorktreeParent $fixture.WorktreeParent -PushOnly 6>&1) -join "`n"
    Assert ($output.Contains('has no changelog fragments to fold')) "A folded default branch was folded again: $output"
    Assert-NoFoldWorktree $fixture
}
Case 'fold submission opens one pull request; WhatIf writes to neither the remote nor GitHub' {
    param($r)
    $fixture = New-FoldFixture $r
    # Stands in for gh: the submission resolves this function before any gh on PATH, and nothing reaches GitHub.
    $calls = [Collections.Generic.List[string]]::new()
    $openUrls = [Collections.Generic.List[string]]::new()
    function gh {
        $calls.Add(($args -join ' '))
        $global:LASTEXITCODE = 0
        if ($args[0] -ceq 'pr' -and $args[1] -ceq 'list') { $openUrls }
        elseif ($args[0] -ceq 'pr' -and $args[1] -ceq 'create') { 'https://github.com/fixture/example/pull/7' }
    }
    $creates = { @($calls | Where-Object { $_.StartsWith('pr create', [StringComparison]::Ordinal) }) }
    & $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -Repository fixture/example -WhatIf
    Assert (@(& $creates).Count -eq 0) 'WhatIf opened a pull request'
    Assert ((Get-FixtureGitLines $fixture.Origin @('branch', '--list', 'changelog/fold-*')).Count -eq 0) 'WhatIf pushed a fold branch'
    # A fold branch pushed earlier skips the fold itself, and WhatIf still opens nothing.
    & $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -PushOnly
    & $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -Repository fixture/example -WhatIf
    Assert (@(& $creates).Count -eq 0) 'WhatIf opened a pull request for a fold branch pushed earlier'
    & $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -Repository fixture/example
    $created = @(& $creates)
    Assert ($created.Count -eq 1 -and $created[0].Contains("--base main --head $($fixture.FoldBranch)") -and $created[0].EndsWith('--repo fixture/example')) "The fold pull request was not opened once against main: $($created -join ' | ')"
    # An open fold pull request is reported instead of opening a second, conflicting one.
    $openUrls.Add('https://github.com/fixture/example/pull/7')
    $output = (& $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -Repository fixture/example 6>&1) -join "`n"
    Assert (@(& $creates).Count -eq 1 -and $output.Contains('already open')) "A second fold pull request was opened: $output"
    # The open-PR query asks for every open pull request, not gh's default first 30.
    $lists = @($calls | Where-Object { $_.StartsWith('pr list', [StringComparison]::Ordinal) })
    # It also leaves out a fork's pull request, whose head name proves nothing.
    Assert ($lists.Count -gt 0 -and @($lists | Where-Object { -not $_.Contains('--limit 1000') -or -not $_.Contains('isCrossRepository == false') }).Count -eq 0) "An open-PR query was limited to gh's default page or took a fork's pull request: $($lists -join ' | ')"
    Assert-NoFoldWorktree $fixture
}
Case 'a reused remote fold branch must contain the exact selected fold' {
    param($r)
    $fixture = New-FoldFixture $r
    & $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -PushOnly
    [void](Invoke-FixtureGit $fixture.Clone @('fetch', '-q', 'origin', "refs/heads/$($fixture.FoldBranch)"))
    [void](Invoke-FixtureGit $fixture.Clone @('checkout', '-q', '--detach', 'FETCH_HEAD'))
    Add-Content -LiteralPath (Join-Path $fixture.Clone 'CHANGELOG.md') -Value '- forged entry'
    [void](Invoke-FixtureGit $fixture.Clone @('add', 'CHANGELOG.md'))
    [void](Invoke-FixtureGit $fixture.Clone @('commit', '-q', '--amend', '--no-edit'))
    [void](Invoke-FixtureGit $fixture.Clone @('push', '-q', '--force', 'origin', "HEAD:refs/heads/$($fixture.FoldBranch)"))
    $message = ''
    try { & $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -PushOnly } catch { $message = $_.Exception.Message }
    Assert ($message -match 'Changelog validation failed') "A forged remote fold was reused: $message"
    Assert-NoFoldWorktree $fixture
    [void](Invoke-FixtureGit $fixture.Clone @('checkout', 'HEAD^', '--', 'CHANGELOG.md'))
    [void](Invoke-FixtureGit $fixture.Clone @('commit', '-q', '--amend', '--no-edit'))
    [void](Invoke-FixtureGit $fixture.Clone @('push', '-q', '--force', 'origin', "HEAD:refs/heads/$($fixture.FoldBranch)"))
    $message = ''
    try { & $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -PushOnly } catch { $message = $_.Exception.Message }
    # The exact-fold check refuses it first, since merged fragments may not leave without their entries; the
    # complete-fold comparison is the second line of defense.
    Assert ($message -match 'without its entry reaching CHANGELOG\.md|not the complete fold') "A remote branch that discarded all pending notes was reused: $message"
    Assert-NoFoldWorktree $fixture
    Put $fixture.Clone 'unrelated.txt' 'Not a fold.'
    [void](Invoke-FixtureGit $fixture.Clone @('add', 'unrelated.txt'))
    [void](Invoke-FixtureGit $fixture.Clone @('commit', '-q', '--amend', '--no-edit'))
    [void](Invoke-FixtureGit $fixture.Clone @('push', '-q', '--force', 'origin', "HEAD:refs/heads/$($fixture.FoldBranch)"))
    $message = ''
    try { & $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -PushOnly } catch { $message = $_.Exception.Message }
    Assert ($message -match 'unrelated change') "A fold branch with an unrelated file was reused: $message"
    Assert-NoFoldWorktree $fixture
}
Case 'a default branch without a Changes folder has nothing to fold' {
    param($r)
    $fixture = New-FoldFixture $r
    [void](Invoke-FixtureGit $fixture.Clone @('rm', '-q', '-r', 'Changes'))
    [void](Invoke-FixtureGit $fixture.Clone @('commit', '-q', '-m', 'No Changes folder'))
    [void](Invoke-FixtureGit $fixture.Clone @('push', '-q', 'origin', 'main'))
    $output = (& $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -PushOnly 6>&1) -join "`n"
    Assert ($output.Contains('has no changelog fragments to fold')) "A default branch without Changes/ was not reported as having nothing to fold: $output"
    Assert ((Get-FixtureGitLines $fixture.Origin @('branch', '--list', 'changelog/fold-*')).Count -eq 0) 'A default branch with nothing to fold pushed a fold branch'
    Assert-NoFoldWorktree $fixture
}
Case 'a fold whose post-checkout hook fails reports it and leaves no worktree behind' {
    param($r)
    $fixture = New-FoldFixture $r
    # Git creates the worktree, then reports the hook's failure.
    $hooks = Join-Path $r 'failing-hooks'
    Put $hooks 'post-checkout' "#!/bin/sh`nexit 1`n"
    if (-not $IsWindows) { [IO.File]::SetUnixFileMode((Join-Path $hooks 'post-checkout'), [IO.UnixFileMode]'UserRead, UserWrite, UserExecute') }
    [void](Invoke-FixtureGit $fixture.Clone @('config', 'core.hooksPath', $hooks))
    $registrations = Get-FixtureGitLines $fixture.Clone @('worktree', 'list', '--porcelain') 'worktree *'
    $message = ''
    try { & $submit -Root $fixture.Clone -WorktreeParent $fixture.WorktreeParent -PushOnly } catch { $message = $_.Exception.Message }
    Assert ($message.Contains('git worktree add')) "The failing hook did not stop the fold with its error: $message"
    Assert-NoFoldWorktree $fixture
    $after = Get-FixtureGitLines $fixture.Clone @('worktree', 'list', '--porcelain') 'worktree *'
    Assert (($after -join "`n") -ceq ($registrations -join "`n")) "A failed fold left a worktree registration: $($after -join ', ')"
    Assert ((Get-FixtureGitLines $fixture.Origin @('branch', '--list', 'changelog/fold-*')).Count -eq 0) 'A failed fold pushed a branch'
}
Case 'invalid UTF-8 in CHANGELOG.md is refused without mutation' {
    param($r)
    [IO.File]::WriteAllBytes((Join-Path $r 'CHANGELOG.md'), [byte[]](@([Text.Encoding]::ASCII.GetBytes("# Changelog`n`n## Unreleased`n`n- Bad ")) + @(0xFF, 0x0A)))
    Put $r 'Changes/2026-10-21-utf8.md' '- Valid.'
    $before = Snapshot $r
    $message = ''
    try { & $fold -Root $r } catch { $message = $_.Exception.Message }
    Assert ($message.Contains('is not valid UTF-8')) "Invalid UTF-8 was not named: $message"
    Refuses { & $validate -Root $r }
    Assert ((Snapshot $r) -ceq $before) 'Invalid UTF-8 input was rewritten'
    # A UTF-16 byte order mark is not honored as another encoding: the file is still read as UTF-8 and refused.
    [IO.File]::WriteAllText((Join-Path $r 'CHANGELOG.md'), "# Changelog`n`n## Unreleased`n`n- Wide.`n", [Text.UnicodeEncoding]::new($false, $true))
    $before = Snapshot $r
    $message = ''
    try { & $fold -Root $r } catch { $message = $_.Exception.Message }
    Assert ($message.Contains('is not valid UTF-8')) "A UTF-16 changelog was not refused as UTF-8: $message"
    Assert ((Snapshot $r) -ceq $before) 'A UTF-16 changelog was rewritten'
}
Case 'links inside the checkout are refused; a junction above it is accepted' {
    param($r)
    if (-not $IsWindows) { Write-Host 'SKIP changelog junction controls: Windows junctions required.'; return }
    $holder = Join-Path $r 'holder'
    $inner = Join-Path $holder 'checkout'
    Put $inner 'Changes/README.md' '# Fragments'
    Put $inner 'CHANGELOG.md' "# Changelog`n`n## Unreleased`n"
    Put $inner 'Changes/2026-10-21-linked.md' '- Through a junction above the root.'
    $via = Join-Path $r 'via'
    New-FixtureJunction $via $holder
    & $fold -Root (Join-Path $via 'checkout')
    Assert ([IO.File]::ReadAllText((Join-Path $inner 'CHANGELOG.md')).Contains('- Through a junction above the root.')) 'A checkout below a junction was refused'
    $elsewhere = Join-Path $r 'elsewhere'
    Put $elsewhere '2026-10-21-outside.md' '- Outside.'
    Put $elsewhere 'README.md' '# Fragments'
    Remove-Item -LiteralPath (Join-Path $r 'Changes') -Recurse -Force
    New-FixtureJunction (Join-Path $r 'Changes') $elsewhere
    $before = Snapshot $elsewhere
    $message = ''
    try { & $fold -Root $r } catch { $message = $_.Exception.Message }
    Assert ($message.Contains('must not traverse reparse points') -and $message.Contains('Changes')) "A linked Changes folder was not refused: $message"
    Assert ((Snapshot $elsewhere) -ceq $before) 'A refused link target was changed'
}
Case 'a spelling of the root that differs only in case is the root only where the file system ignores case' {
    param($r)
    # Every changelog command checks its paths with this internal guard. On Linux the other spelling names a different
    # folder, and walking up from it never reaches the root.
    $variant = Join-Path $parent ([IO.Path]::GetFileName($r).ToUpperInvariant())
    $message = ''
    try { & $changelogModule { param($Path, $Root) Assert-ChangelogPath $Path $Root } (Join-Path $variant 'CHANGELOG.md') $r }
    catch { $message = $_.Exception.Message }
    if ($IsWindows) { Assert ($message -ceq '') "A differently cased spelling of the root was refused on Windows: $message" }
    else { Assert ($message -cne '') 'A folder whose name differs from the root only in case was accepted as the root' }
}
Case 'an interrupted cleanup names the fragment and a rerun finishes it' {
    param($r)
    # Only Windows refuses to delete a file that another handle holds open without delete sharing.
    if (-not $IsWindows) { Write-Host 'SKIP changelog interrupted-cleanup control: Windows file sharing semantics required.'; return }
    $held = Join-Path $r 'Changes/2026-10-21-held.md'
    Put $r 'Changes/2026-10-21-held.md' '- Held.'
    # Another reader without delete sharing makes the removal fail after publication.
    $reader = [IO.File]::Open($held, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $message = ''
        try { & $fold -Root $r } catch { $message = $_.Exception.Message }
        Assert ($message.Contains('Changes/2026-10-21-held.md could not be removed') -and $message.Contains('Run Tools/Fold-Changelog.ps1 again')) "Interrupted cleanup gave no guidance: $message"
        Assert ([IO.File]::ReadAllText((Join-Path $r 'CHANGELOG.md')).Contains('- Held.')) 'The entry was not published before cleanup'
    } finally { $reader.Dispose() }
    & $fold -Root $r
    Assert (-not [IO.File]::Exists($held)) 'The rerun did not finish the cleanup'
    Assert ([regex]::Matches([IO.File]::ReadAllText((Join-Path $r 'CHANGELOG.md')), '(?m)^- Held\.$').Count -eq 1) 'The rerun duplicated the entry'
}
Case 'product shims run the pinned engine with the product root and every parameter' {
    param($r)
    [void](New-ShimProduct $r)
    $validateShim = Join-Path $r 'Tools/Test-Changelog.ps1'
    $foldShim = Join-Path $r 'Tools/Fold-Changelog.ps1'
    Put $r 'Changes/2026-10-21-shim.md' '- Through the shim.'
    Save-FixtureBase $r
    & $validateShim
    & $validateShim -Base origin/main
    Refuses { & $validateShim -RequireFolded }
    Refuses { & $foldShim -Check }
    $before = Snapshot $r
    & $foldShim -WhatIf
    Assert ((Snapshot $r) -ceq $before) 'A shim preview mutated files'
    # An explicit relative Root follows the caller's location; without Root the shim's own product is used.
    $elsewhere = Join-Path $r 'elsewhere'
    Put $elsewhere 'Changes/README.md' '# Fragments'
    Put $elsewhere 'CHANGELOG.md' "# Changelog`n`n## Unreleased`n"
    Put $elsewhere 'Changes/notes.txt' 'Not a fragment.'
    Push-Location -LiteralPath $elsewhere
    try {
        Refuses { & $validateShim -Root . }
        & $validateShim
    } finally { Pop-Location }
    & $foldShim
    Assert ([IO.File]::ReadAllText((Join-Path $r 'CHANGELOG.md')).Contains('- Through the shim.')) 'The shim did not fold the product'
    Assert (-not [IO.File]::Exists((Join-Path $r 'Changes/2026-10-21-shim.md'))) 'The shim fold left its fragment'
    & $foldShim -Check
}
Case 'a missing, other-commit, changed or nested engine checkout is refused with one message naming the pin' {
    param($r)
    $pin = New-ShimProduct $r
    Put $r 'Changes/2026-10-21-held.md' '- Stays pending.'
    Save-FixtureBase $r
    $foldShim = Join-Path $r 'Tools/Fold-Changelog.ps1'
    $engineCheckout = Join-Path $r '.ci-engine'
    $inputs = { [IO.File]::ReadAllText((Join-Path $r 'CHANGELOG.md')) + [IO.File]::ReadAllText((Join-Path $r 'Changes/2026-10-21-held.md')) }
    $before = & $inputs
    $refusal = {
        $message = ''
        try { & $foldShim | Out-Null } catch { $message = $_.Exception.Message }
        Assert (-not [string]::IsNullOrEmpty($message)) 'A shim ran against the wrong engine'
        Assert ((& $inputs) -ceq $before) 'A refused shim changed the changelog or its fragment'
        $message
    }
    # Another engine commit.
    Put $engineCheckout 'README.md' 'A later engine commit.'
    [void](Invoke-FixtureGit $engineCheckout @('add', '--all'))
    [void](Invoke-FixtureGit $engineCheckout @('commit', '-q', '-m', 'Later'))
    $later = (Invoke-FixtureGit $engineCheckout @('rev-parse', 'HEAD'))[0].Trim()
    $message = & $refusal
    Assert ($message.Contains("pins ($pin)") -and $message.Contains("it is at $later") -and $message.Contains("checkout --detach $pin")) "Another engine commit was not named with the fix: $message"
    [void](Invoke-FixtureGit $engineCheckout @('checkout', '-q', '--detach', $pin))
    & (Join-Path $r 'Tools/Test-Changelog.ps1')
    # A tracked change in the pinned commit.
    Add-Content -LiteralPath (Join-Path $engineCheckout 'Tools/Modules/Ci.Changelog.psm1') -Value '# local edit'
    $message = & $refusal
    Assert ($message.Contains("pins ($pin)") -and $message.Contains('changes to tracked files')) "A changed engine checkout was not refused: $message"
    [void](Invoke-FixtureGit $engineCheckout @('checkout', '-q', '--', 'Tools/Modules/Ci.Changelog.psm1'))
    # A manifest that pins another commit.
    $manifest = Join-Path $r '.ci/project.json'
    $pinned = [IO.File]::ReadAllText($manifest)
    Put $r '.ci/project.json' $pinned.Replace($pin, ('b' * 40))
    $message = & $refusal
    Assert ($message.Contains("pins ($('b' * 40))") -and $message.Contains("it is at $pin")) "A manifest pinning another commit was not refused: $message"
    Put $r '.ci/project.json' $pinned
    # A folder inside the product rather than a checkout of its own.
    Move-Item -LiteralPath (Join-Path $engineCheckout '.git') -Destination (Join-Path $r 'engine-git')
    $message = & $refusal
    Assert ($message.Contains('not a Git checkout of its own')) "An engine folder without its own checkout was accepted: $message"
    Move-Item -LiteralPath (Join-Path $r 'engine-git') -Destination (Join-Path $engineCheckout '.git')
    # No engine at all.
    Move-Item -LiteralPath $engineCheckout -Destination (Join-Path $r 'engine-away')
    $message = & $refusal
    Assert ($message.Contains('is missing or predates engine shims') -and $message.Contains('git clone https://github.com/RedSalamanders/.github.git .ci-engine')) "A missing engine was not refused with the fix: $message"
    Move-Item -LiteralPath (Join-Path $r 'engine-away') -Destination $engineCheckout
    & (Join-Path $r 'Tools/Test-Changelog.ps1')
    # The check is read-only: a tracked engine file whose timestamp alone changed would make a plain git status
    # refresh and rewrite the engine's index.
    $touched = Join-Path $engineCheckout 'Tools/Modules/Ci.Changelog.psm1'
    [IO.File]::SetLastWriteTimeUtc($touched, [DateTime]::UtcNow.AddMinutes(-3))
    $index = Join-Path $engineCheckout '.git/index'
    $indexBefore = [Convert]::ToHexString([IO.File]::ReadAllBytes($index)) + [IO.File]::GetLastWriteTimeUtc($index).Ticks
    & (Join-Path $r 'Tools/Test-Changelog.ps1')
    Assert (([Convert]::ToHexString([IO.File]::ReadAllBytes($index)) + [IO.File]::GetLastWriteTimeUtc($index).Ticks) -ceq $indexBefore) 'The engine binding rewrote the engine checkout index'
    # A copy in a nested fixture without its own manifest never binds to the product around it.
    $nested = Join-Path $r 'nested/fixture'
    Put $nested 'Tools/Test-Changelog.ps1' ([IO.File]::ReadAllText((Join-Path $r 'Tools/Test-Changelog.ps1')))
    $message = ''
    try { & (Join-Path $nested 'Tools/Test-Changelog.ps1') | Out-Null } catch { $message = $_.Exception.Message }
    Assert ($message.Contains('is missing or predates engine shims')) "A nested shim bound to the product around it: $message"
}
if ($ProjectRoot) {
    Case "the product's changelog commands are this engine's shims" {
        param($r)
        foreach ($relative in $shims) {
            $path = Join-Path $ProjectRoot $relative
            Assert ([IO.File]::Exists($path)) "The product lacks the engine shim $relative"
            $expected = [IO.File]::ReadAllText((Join-Path $engine "Templates/Project/$relative")).Replace("`r`n", "`n").TrimEnd()
            Assert ([IO.File]::ReadAllText($path).Replace("`r`n", "`n").TrimEnd() -ceq $expected) "$relative differs from the pinned engine's Templates/Project/$relative; copy that file"
        }
    }
    Case 'the product PrePush runner validates the changelog against origin/main before build or test discovery' {
        param($r)
        $scoped = [IO.File]::Exists((Join-Path $ProjectRoot 'Test-Changes.ps1'))
        $runnerName = if ($scoped) { 'Test-Changes.ps1' } else { 'test.ps1' }
        [void](New-ShimProduct $r)
        Put $r $runnerName ([IO.File]::ReadAllText((Join-Path $ProjectRoot $runnerName)))
        Save-FixtureBase $r
        $run = {
            $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            foreach ($argument in @('-NoProfile','-File',(Join-Path $r $runnerName))) { $start.ArgumentList.Add($argument) }
            if ($scoped) { $start.ArgumentList.Add('-Mode'); $start.ArgumentList.Add('PrePush') }
            $start.Environment['NO_COLOR'] = '1'
            # The product's real runner and its engine shim start several processes; a busy host needs more than the default.
            $outcome = Invoke-FixtureProcess $start -TimeoutMilliseconds 120000
            # One line of plain text: a hosted runner may still color the error (ANSI) and wraps a long message, continuing
            # it on " | " lines, so color codes go before the lines are joined.
            $plain = $outcome.Output -replace "`e\[[0-9;?]*[ -/]*[@-~]", ''
            $outcome | Add-Member -NotePropertyName Flat -NotePropertyValue ((($plain -replace '\r?\n\s*\|\s?', ' ') -replace '\s+', ' '))
            $outcome
        }
        # Committed first: a runner may refuse a working tree that differs from what is pushed.
        Edit-Fixture $r 'CHANGELOG.md' '- Existing.' "- Hand edit.`n- Existing."
        [void](Invoke-FixtureGit $r @('commit', '-q', '-a', '-m', 'Hand edit'))
        $result = & $run
        Assert ($result.ExitCode -ne 0 -and $result.Flat.Contains('added by hand')) "The runner did not refuse a hand-edited changelog: $($result.Output)"
        Reset-FixtureBase $r
        Put $r 'Changes/2026-10-21-pending.md' '- Pending until the fold on main.'
        [void](Invoke-FixtureGit $r @('add', '--all'))
        [void](Invoke-FixtureGit $r @('commit', '-q', '-m', 'Pending fragment'))
        $result = & $run
        Assert ($result.Flat.Contains('Changelog valid: 1 pending fragment(s); CHANGELOG.md changes since origin/main are exact folds')) "The runner refused a pending fragment: $($result.Output)"
    }
}
Case 'a timed-out fixture child is terminated before fixture cleanup' {
    param($r)
    $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile','-Command','Start-Sleep -Seconds 60')) { $start.ArgumentList.Add($argument) }
    $identity = $null
    $message = ''
    try {
        try { Invoke-FixtureProcess $start -TimeoutMilliseconds 100 -ProcessIdentity ([ref]$identity) | Out-Null }
        catch { $message = $_.Exception.Message }
        Assert ($message.Contains('did not exit within its budget') -and $null -ne $identity) 'Timeout negative control was not reached'
        $remaining = Get-Process -Id $identity.Id -ErrorAction SilentlyContinue
        try { Assert ($null -eq $remaining -or $remaining.StartTime.ToUniversalTime().Ticks -ne $identity.StartTicks) 'Owned fixture child survived timeout cleanup' }
        finally { if ($remaining) { $remaining.Dispose() } }
    } finally {
        # Keep this negative control self-cleaning even if the implementation regresses; PID alone is not ownership proof.
        if ($identity) {
            $remaining = Get-Process -Id $identity.Id -ErrorAction SilentlyContinue
            if ($remaining) {
                try {
                    if ($remaining.StartTime.ToUniversalTime().Ticks -eq $identity.StartTicks) {
                        $remaining.Kill($true)
                        Assert ($remaining.WaitForExit(5000)) 'Negative-control cleanup did not finish'
                    }
                } finally { $remaining.Dispose() }
            }
        }
    }
}
Write-Host "Changelog behavior: $($results.Count) passed, $($failures.Count) failed."
if ($failures.Count) { throw ($failures -join "`n") }
$global:LASTEXITCODE = 0
