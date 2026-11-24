<#
.SYNOPSIS
Explains and runs the tests that a change affects, reusing identical successful local evidence.
.DESCRIPTION
The one scoped-testing runner of every product (Specs/ProjectCommands.md, Scoped testing, behaviors B1 to B14).
Products run it through their root Test-Changes.ps1 shim, which passes -Root; Tests/test-scopes.json (version 2) holds
every repository fact.
Affected (the default) compares the checkout with its merge base with -BaseRef, or, in an ordinary local run, with the
last successful affected run of the profile for 24 hours. Full runs every scope of one profile. PrePush refuses an
uncommitted changelog, checks it against the base and runs every scope of each prePushProfiles entry. An unmapped
input selects every scope; interactive suites are listed as INTERACTIVE_NOT_RUN and never run.
.PARAMETER Root
Product checkout. Mandatory here; the product shim passes its own folder.
.PARAMETER Mode
Affected, Full or PrePush.
.PARAMETER BaseRef
Comparison ref, by default origin/<defaultBranch>. Never fetched. An explicit value turns the iteration baseline off.
.PARAMETER Scopes
Explicit scopes of an Affected run, as names or comma-separated strings.
.PARAMETER Configuration
Debug, Release or ASan Debug, for Affected and Full. PrePush takes its profiles from the data.
.PARAMETER Platform
x64 or ARM64, for Affected and Full. Runtime tests need a host of the same architecture.
.PARAMETER Explain
Prints the plan, its reasons and the interactive obligations, then stops: no changelog gate, lease, build, test or write.
.PARAMETER Force
Runs every selected scope even when identical successful evidence exists, and ignores the iteration baseline.
.PARAMETER SkipBuild
Uses only build outputs whose attestation (.build/reports/scoped-tests/<profile>/build.json) still matches.
.PARAMETER ParallelSuites
Suites test.ps1 may run at once (1 to 8). Bound into native identity; passed to test.ps1 only when above 1.
.OUTPUTS
The plan with one reason per path and rule, REUSED/PASSED lines per scope, then one token: NOTHING_SELECTED,
PROSE_CHECKS_PASSED, SELECTED_PASSED or FULL_PASSED, followed by "; repository NOT_EVALUATED". Any failure or refusal
is a terminating error (nonzero exit).
.NOTES
Requires PowerShell 7 and Git; native scopes need the product's build.ps1 and test.ps1. Side effects: runs
Tools/Test-Changelog.ps1 of this engine, then the product's build.ps1 and test.ps1 (through Tools/Invoke-ScopedScript.ps1)
and each selected scope's commands in child pwsh processes; writes receipts, build attestations and the iteration
baseline under .build/reports/scoped-tests; holds the profile lease (Enter-ScopedProfileLease) while a profile runs.
No fetch, network, GitHub or desktop focus.
.EXAMPLE
./Test-Changes.ps1 -Explain
.EXAMPLE
./.ci-engine/Tools/Test-Changes.ps1 -Root . -Scopes Core,Tooling -Configuration Release
.EXAMPLE
./Test-Changes.ps1 -Mode PrePush
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [ValidateSet('Affected', 'Full', 'PrePush')][string]$Mode = 'Affected',
    [string]$BaseRef = '',
    [string[]]$Scopes = @(),
    [ValidateSet('Debug', 'Release', 'ASan Debug')][string]$Configuration = 'Debug',
    [ValidateSet('x64', 'ARM64')][string]$Platform = 'x64',
    [switch]$Explain,
    [switch]$Force,
    [switch]$SkipBuild,
    [ValidateRange(1, 8)][int]$ParallelSuites = 1
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
if (-not [IO.Directory]::Exists($Root)) { throw "Test-Changes.ps1 -Root must be an existing product checkout: $Root" }
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.ScopedTesting.psm1') -Force
# The data's own keys first; the rules derived from bound projects are read after the changelog gate (B3).
$manifest = Read-ScopedTestManifest -Root $Root -SkipProjectRules
# O2: names or comma-separated strings.
$Scopes = @($Scopes | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Scopes.Count -and $Mode -ne 'Affected') { throw '-Scopes selects the scopes of an Affected run; Full and PrePush run every scope.' }
if ($Mode -eq 'PrePush') {
    foreach ($name in @('Platform', 'Configuration')) {
        if ($PSBoundParameters.ContainsKey($name)) { throw "PrePush runs every profile in prePushProfiles of Tests/test-scopes.json; -$name selects the profile of an Affected or Full run." }
    }
}
# B1: the data's default branch.
$explicitBase = [bool]$BaseRef
if (-not $BaseRef) { $BaseRef = 'origin/' + $manifest.defaultBranch }
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$bridge = Join-Path $PSScriptRoot 'Invoke-ScopedScript.ps1'
$results = [Collections.Generic.List[string]]::new()

function Invoke-ScopedProductScript([string]$Name, [Collections.Specialized.OrderedDictionary]$Parameters, [string]$Label) {
    # A child process, so the product script never shares this runner's modules; the bridge passes arrays as arrays.
    $script = Join-Path $Root $Name
    if (-not [IO.File]::Exists($script)) { throw "$Label needs the product's $Name ($script)." }
    $json = ConvertTo-Json -InputObject $Parameters -Compress -Depth 4
    $global:LASTEXITCODE = 0
    & $pwsh -NoProfile -NonInteractive -File $bridge -Script $script -WorkingDirectory $Root -ParametersJson $json | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit $LASTEXITCODE." }
}

function Invoke-ScopedCommands([object]$Scope) {
    # B11: each non-native scope runs its own commands, each in a child pwsh.
    foreach ($command in @($Scope.commands)) {
        $path = Join-Path $Root $command.path
        if (-not [IO.File]::Exists($path)) { throw "Scope $($Scope.name) runs $($command.path), which does not exist." }
        $global:LASTEXITCODE = 0
        & $pwsh -NoProfile -NonInteractive -File $path @([string[]]@($command.arguments)) | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Independent scope failed: $($Scope.name) ($($command.path) exited with $LASTEXITCODE)." }
    }
}

function Get-ScopedArtifactState([string]$P, [string]$C) {
    if (-not [IO.Directory]::Exists((Join-Path $Root ".build/$P/$C"))) { return 'absent' }
    try { return Get-ScopedArtifactIdentity -Root $Root -Platform $P -Configuration $C -Manifest $manifest } catch { return 'incomplete' }
}

function Get-ScopedReceiptPath([object]$Scope, [string]$Reports) {
    if ($Scope.native) { return Join-Path $Reports ($Scope.name + '.json') }
    return Join-Path $Root ('.build/reports/scoped-tests/independent/' + $Scope.name + '.json')
}

function Get-ScopedSuiteReportPath([string]$Name, [string]$P, [string]$C, [bool]$Instrumented) {
    $path = Join-Path $Root ".build/reports/$Name-$P-$C$(if ($Instrumented) { '.instrumented' }).json"
    return Assert-CiContainedPath -Root $Root -Path $path
}

function Read-ScopedSuiteReport([string]$Name, [string]$P, [string]$C, [bool]$Instrumented) {
    $path = Get-ScopedSuiteReportPath $Name $P $C $Instrumented
    if (-not [IO.File]::Exists($path)) { return $null }
    try {
        $report = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path))
        return [pscustomobject]@{ exitCode = [int]$report.exitCode; skips = @($report.skips | Where-Object { $null -ne $_ }) }
    } catch { return $null }
}

function Invoke-ScopedBuild([string]$P, [string]$C, [string]$Reports, [string]$Environment, [Collections.IDictionary]$Source = $null) {
    # B12: the whole profile. Returns the build options bound into native identity and the compiled source identity,
    # taken from the run's source map when given (the final input check covers any change since).
    $compiledBefore = Get-ScopedSourceIdentity -Root $Root -Manifest $manifest -CompiledOnly -From $Source
    $parameters = [ordered]@{ Platform = $P; Configuration = $C }
    $buildOptions = [Collections.Generic.List[string]]::new()
    $number = $null
    if ($manifest.buildNumber -ceq 'mergeBaseCount') {
        $number = Get-ScopedBuildNumber -Root $Root -BaseRef $BaseRef
        $parameters['BuildNumber'] = $number
        $buildOptions.Add("build-number=$number")
    }
    $buildScript = Join-Path $Root 'build.ps1'
    $tokens = $null
    $parseErrors = $null
    $buildDefinition = [System.Management.Automation.Language.Parser]::ParseFile($buildScript, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "Cannot read build parameters from ${buildScript}: $($parseErrors[0].Message)" }
    if ($buildDefinition.ParamBlock -and ($buildDefinition.ParamBlock.Parameters | Where-Object {
        $_.Name.VariablePath.UserPath -eq 'EnableTests' -and $_.StaticType -eq [switch]
    })) {
        $parameters['EnableTests'] = $true
        $buildOptions.Add('enable-tests=true')
    }
    $options = $buildOptions -join ','
    $attestation = Join-Path $Reports 'build.json'
    if ($SkipBuild) {
        $artifact = Get-ScopedArtifactState $P $C
        if (-not (Test-ScopedReceipt -Path $attestation -Identity (Get-ScopedDigest (@($compiledBefore, $artifact, $options, $Environment) -join "`n")))) {
            throw "SkipBuild refused: compiled source, build outputs, build options or environment of $P $C changed since the last attested build. Run without -SkipBuild."
        }
        return [pscustomobject]@{ Options = $options; Compiled = $compiledBefore; BuildNumber = $number }
    }
    Invoke-ScopedProductScript 'build.ps1' $parameters "Build ($P $C)"
    if ((Get-ScopedSourceIdentity -Root $Root -Manifest $manifest -CompiledOnly) -cne $compiledBefore) { throw 'Compiled source changed during the build; no build attestation was published.' }
    $artifact = Get-ScopedArtifactIdentity -Root $Root -Platform $P -Configuration $C -Manifest $manifest
    Write-ScopedReceipt -Path $attestation -Identity (Get-ScopedDigest (@($compiledBefore, $artifact, $options, $Environment) -join "`n"))
    return [pscustomobject]@{ Options = $options; Compiled = $compiledBefore; BuildNumber = $number }
}

function Invoke-ScopedProfile([object]$Target) {
    $P = [string]$Target.platform
    $C = [string]$Target.configuration
    $reports = Get-ScopedReportRoot -Root $Root -Platform $P -Configuration $C
    $iterationPath = Join-Path $reports 'iteration.json'
    if ($Mode -eq 'PrePush') { Write-Host "== PrePush profile $P $C$(if ($Target.buildOnly) { ' (build only)' })" }
    if ($Target.buildOnly -and $Explain) {
        Write-Host "Build only: build.ps1 -Platform $P -Configuration $C; runtime tests of $P need a matching host."
        $results.Add('explained')
        return
    }
    # B8: fail fast; nested build.ps1, test.ps1 and commands re-enter through the inherited handoff.
    $lease = if (-not $Explain) { Enter-ScopedProfileLease -Root $Root -Platform $P -Configuration $C } else { $null }
    try {
        $environmentBase = Get-ScopedEnvironmentIdentity -Root $Root -Manifest $manifest
        if ($Target.buildOnly) {
            # B10: a cross build stays a build.
            [void](Invoke-ScopedBuild $P $C $reports $environmentBase)
            Write-Host "BUILT $P $C (build only; runtime tests of $P need a matching host)"
            $results.Add('built')
            return
        }
        $toolIdentity = Get-ScopedToolIdentity
        $environment = Get-ScopedDigest ($environmentBase + "`n" + $toolIdentity)
        $toolingEnvironment = Get-ScopedDigest ((Get-ScopedEnvironmentIdentity -Root $Root -Manifest $manifest -Tooling) + "`n" + $toolIdentity)
        $instrumentation = @(Get-ScopedInstrumentation -Manifest $manifest)
        $options = "parallel-suites=$ParallelSuites"
        $source = Get-ScopedSourceMap -Root $Root -Manifest $manifest
        $index = Get-ScopedIndexMap -Root $Root
        $artifact = Get-ScopedArtifactState $P $C
        $changed = @()
        $branchChanged = @()
        $forceFull = $false
        $basis = if ($Scopes.Count) { 'explicit scopes' } elseif ($Mode -ne 'Affected') { "$Mode selects every scope" } else { '' }
        $ordinary = $Mode -eq 'Affected' -and -not $Scopes.Count -and -not $explicitBase -and -not $env:CI -and -not $env:GITHUB_ACTIONS
        if ($Mode -eq 'Affected' -and -not $Scopes.Count) {
            # B2: an unresolvable base refuses with its remedy, also when a baseline exists.
            $branchChanged = @(Get-ScopedChangedPaths -Root $Root -BaseRef $BaseRef)
            $changed = $branchChanged
            $basis = "merge base with $BaseRef"
            # B4: the iteration baseline is local, recent and exact; never in CI, with an explicit base, -Force or instrumentation.
            $off = @($(if ($explicitBase) { 'explicit -BaseRef' }), $(if ($env:CI -or $env:GITHUB_ACTIONS) { 'CI' }), $(if ($Force) { '-Force' }),
                $(if ($instrumentation.Count) { 'instrumentation' }) | Where-Object { $_ })
            if ($off.Count) { $basis += " (iteration baseline off: $($off -join ', '))" }
            else {
                $iteration = Read-ScopedIteration -Path $iterationPath -Root $Root -Platform $P -Configuration $C -Environment $environment -Options $options
                if ($iteration) {
                    $changed = @(@(Get-ScopedMapDelta -Before $iteration.source -After $source) + @(Get-ScopedPendingIndexDelta -Root $Root -Before $iteration.index -After $index) |
                            Sort-Object -Unique -CaseSensitive)
                    $basis = 'the last successful affected run of this profile (under 24 hours)'
                    if ($artifact -cne $iteration.artifact) { $forceFull = $true; $basis = 'build outputs changed since the last successful affected run' }
                } else { $basis += ' (no iteration baseline)' }
            }
        }
        $plan = Get-ScopedTestPlan -Manifest $manifest -ChangedPaths $changed -Scopes $Scopes -Full:($Mode -ne 'Affected' -or $forceFull) -Configuration $C
        # B9: listed from the data, never run; a baseline never consumes cumulative obligations.
        $interactive = @(Get-ScopedInteractiveObligations -Manifest $manifest -ChangedPaths $branchChanged -Full:($Mode -ne 'Affected'))
        Write-Host "Test plan: $Mode ($P $C); baseline: $basis; scopes: $(if ($plan.scopes.Count) { $plan.scopes -join ', ' } else { '(none)' })"
        foreach ($reason in $plan.reasons) { Write-Host "  $($reason.path): $($reason.reason) => $(if (@($reason.scopes).Count) { @($reason.scopes) -join ', ' } else { '(none)' })" }
        if ($plan.notApplicable.Count) { Write-Host "  not run in ${C}: $($plan.notApplicable -join ', ')" }
        foreach ($obligation in $interactive) { Write-Host "INTERACTIVE_NOT_RUN: $($obligation.suite) - $($obligation.reason) [$($obligation.pattern)]" }
        if ($instrumentation.Count) { Write-Host "INSTRUMENTED RUN (no receipt or iteration baseline is written or reused): $($instrumentation -join ', ')" }
        if ($Explain) { $results.Add('explained'); return }
        if (-not $plan.scopes.Count) { $results.Add('nothing'); return }
        # B4: revoked before any build or test, so a failed run never leaves a baseline that hides its failure.
        Remove-ScopedIteration -Path $iterationPath -Root $Root
        $selected = @($manifest.scopes | Where-Object { $_.name -cin $plan.scopes })
        $native = @($selected | Where-Object { $_.native })
        $buildOptions = ''
        $compiled = ''
        if ($native.Count) {
            Assert-ScopedRuntimePlatform -Platform $P
            $build = Invoke-ScopedBuild $P $C $reports $environmentBase $source
            $buildOptions = $build.Options
            $compiled = $build.Compiled
            $artifact = Get-ScopedArtifactIdentity -Root $Root -Platform $P -Configuration $C -Manifest $manifest
        }
        $nativeOptions = "$options;$buildOptions"
        $nativeKey = if ($native.Count) { Get-ScopedDigest (@($Root, $P, $C, '(common)', $nativeOptions, $compiled, $artifact, $environment) -join "`n") } else { '' }
        $toolingKey = Get-ScopedDigest ((Get-ScopedSourceIdentity -Root $Root -Manifest $manifest -From $source) + "`n" + $toolingEnvironment)
        # B5: reuse needs the exact receipt and, for a native scope, a clean suite report; instrumentation never reuses.
        $pending = [Collections.Generic.List[object]]::new()
        $identities = @{}
        foreach ($scope in $selected) {
            $key = Get-ScopedDigest ($(if ($scope.native) { $nativeKey } else { $toolingKey }) + "`n" + $scope.name)
            $identities[$scope.name] = $key
            $receipt = Get-ScopedReceiptPath $scope $reports
            $reuse = -not $instrumentation.Count -and -not $Force -and $scope.reuse -and (Test-ScopedReceipt -Path $receipt -Identity $key)
            if ($reuse -and $scope.native) {
                $report = Read-ScopedSuiteReport $scope.name $P $C $false
                $reuse = $null -ne $report -and $report.exitCode -eq 0 -and -not $report.skips.Count
            }
            if ($reuse) { Write-Host "REUSED $($scope.name) (identical successful local evidence)"; continue }
            # A failed or interrupted rerun never leaves an earlier success reusable.
            if ([IO.File]::Exists($receipt)) { [IO.File]::Delete($receipt) }
            $pending.Add($scope)
        }
        foreach ($scope in @($pending | Where-Object { -not $_.native })) {
            Invoke-ScopedCommands $scope
            # B6: a scope whose inputs changed while it ran publishes nothing and fails the run.
            $after = Get-ScopedDigest ((Get-ScopedDigest ((Get-ScopedSourceIdentity -Root $Root -Manifest $manifest) + "`n" + $toolingEnvironment)) + "`n" + $scope.name)
            if ($after -cne $identities[$scope.name]) { throw "Inputs changed during $($scope.name); no reusable success was published." }
            if ($scope.reuse -and -not $instrumentation.Count) { Write-ScopedReceipt -Path (Get-ScopedReceiptPath $scope $reports) -Identity $identities[$scope.name] }
            Write-Host "PASSED $($scope.name) (independent obligation; native coverage remains separate)"
        }
        $runtime = [string[]]@($pending | Where-Object { $_.native } | ForEach-Object { $_.name })
        $reduced = [Collections.Generic.List[string]]::new()
        if ($runtime.Count) {
            $parameters = [ordered]@{ Platform = $P; Configuration = $C; Suites = $runtime; SkipBuild = $true; SkipTooling = $true }
            if ($null -ne $build.BuildNumber) { $parameters['BuildNumber'] = $build.BuildNumber }
            if ($ParallelSuites -gt 1) { $parameters['ParallelSuites'] = $ParallelSuites }
            # Keep prior evidence and require test.ps1 to create the report for this invocation.
            $archive = Assert-CiContainedPath -Root $Root -Path (Join-Path $reports ("prior-suite-reports/" + [guid]::NewGuid().ToString('N')))
            foreach ($name in $runtime) {
                $priorReport = Get-ScopedSuiteReportPath $name $P $C ([bool]$instrumentation.Count)
                if (-not [IO.File]::Exists($priorReport)) { continue }
                [void][IO.Directory]::CreateDirectory($archive)
                [IO.File]::Move($priorReport, (Join-Path $archive ([IO.Path]::GetFileName($priorReport))))
            }
            Invoke-ScopedProductScript 'test.ps1' $parameters "Selected runtime tests ($P $C)"
            $afterKey = Get-ScopedDigest (@($Root, $P, $C, '(common)', $nativeOptions, (Get-ScopedSourceIdentity -Root $Root -Manifest $manifest -CompiledOnly),
                    (Get-ScopedArtifactIdentity -Root $Root -Platform $P -Configuration $C -Manifest $manifest), $environment) -join "`n")
            foreach ($name in $runtime) {
                if ((Get-ScopedDigest ($afterKey + "`n" + $name)) -cne $identities[$name]) { throw "Inputs changed during $name; no reusable success was published." }
            }
            foreach ($scope in @($pending | Where-Object { $_.native })) {
                $report = Read-ScopedSuiteReport $scope.name $P $C ([bool]$instrumentation.Count)
                if (-not $report) { throw "test.ps1 wrote no current suite report .build/reports/$($scope.name)-$P-$C.json; no success was established for $($scope.name)." }
                if ($report.exitCode -ne 0) { throw "The suite report of $($scope.name) does not show a successful exit." }
                if ($report.skips.Count) { $reduced.Add($scope.name); Write-Host "PASSED_WITH_CAPABILITY_SKIPS $($scope.name) (not reusable)"; continue }
                if ($scope.reuse -and -not $instrumentation.Count) { Write-ScopedReceipt -Path (Get-ScopedReceiptPath $scope $reports) -Identity $identities[$scope.name] }
                Write-Host "PASSED $($scope.name) (native suite)"
            }
        }
        if ((Get-ScopedMapIdentity (Get-ScopedSourceMap -Root $Root -Manifest $manifest)) -cne (Get-ScopedMapIdentity $source) -or
            (Get-ScopedMapIdentity (Get-ScopedIndexMap -Root $Root)) -cne (Get-ScopedMapIdentity $index) -or
            (Get-ScopedDigest ((Get-ScopedEnvironmentIdentity -Root $Root -Manifest $manifest) + "`n" + (Get-ScopedToolIdentity))) -cne $environment) {
            throw 'Source, index or environment changed during the run; no iteration baseline was published.'
        }
        if ($ordinary -and -not $instrumentation.Count -and -not $reduced.Count) {
            Write-ScopedIteration -Path $iterationPath -Root $Root -Platform $P -Configuration $C -Environment $environment -Options $options `
                -Source $source -Index $index -Artifact (Get-ScopedArtifactState $P $C)
        }
        $results.Add($(if ($plan.full) { 'full' } elseif ($plan.prose) { 'prose' } else { 'selected' }))
    } finally { Exit-ScopedProfileLease $lease }
}

Push-Location -LiteralPath $Root
try {
    if (-not $Explain) {
        # B3: the changelog gate comes first; PrePush validates the committed candidate against the base.
        $changelog = Join-Path $PSScriptRoot 'Test-Changelog.ps1'
        if ($Mode -eq 'PrePush') {
            $state = Invoke-CiGit $Root @('--no-optional-locks', 'status', '--porcelain', '--untracked-files=normal', '--', 'CHANGELOG.md', 'Changes/')
            if ($state.stdout.Trim()) { throw 'PrePush requires committed CHANGELOG.md and Changes/ state; commit or restore those files before validation.' }
            & $changelog -Root $Root -Base $BaseRef
        } else { & $changelog -Root $Root }
    }
    $manifest = Read-ScopedTestManifest -Root $Root
    if ($manifest.nativeInventory) { Write-Host "Native test naming: $(Assert-ScopedTestNames -Root $Root -Manifest $manifest) files checked." }
    # O1: PrePush runs every profile the data lists, in one call.
    $profiles = if ($Mode -eq 'PrePush') { @($manifest.prePushProfiles) } else { @([pscustomobject]@{ platform = $Platform; configuration = $Configuration; buildOnly = $false }) }
    foreach ($entry in $profiles) { Invoke-ScopedProfile $entry }
} finally { Pop-Location }
if ($Explain) { return }
# B14: one vocabulary.
$kinds = @($results | Where-Object { $_ -cne 'built' })
$token = if (-not @($kinds | Where-Object { $_ -cne 'nothing' }).Count) { 'NOTHING_SELECTED' }
elseif (-not @($kinds | Where-Object { $_ -cne 'full' }).Count) { 'FULL_PASSED' }
elseif (-not @($kinds | Where-Object { $_ -cnotin @('prose', 'nothing') }).Count) { 'PROSE_CHECKS_PASSED' }
else { 'SELECTED_PASSED' }
Write-Host "$token; repository NOT_EVALUATED" -ForegroundColor Green
