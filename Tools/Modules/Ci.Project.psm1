Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function New-CiProjectContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$EngineRoot,
        [Parameter(Mandatory)][string]$Phase, [ValidateSet('x64','ARM64')][string]$Platform = 'x64',
        [string]$Descriptor = '', [switch]$DevelopmentEngine)
    $project = Read-CiProject $Root
    if ($DevelopmentEngine -and $Phase -ne 'Static') { throw 'A development engine is allowed only for compiler-free static checks.' }
    if (-not $DevelopmentEngine) {
        $engineCommit = (Invoke-CiGit $EngineRoot @('rev-parse', 'HEAD')).stdout.Trim()
        if ($engineCommit -cne $project.engine.ref -or
            (Invoke-CiGit $EngineRoot @('status', '--porcelain', '--untracked-files=no')).stdout.Trim()) { throw 'Project adapter requires the exact clean pinned engine.' }
    }
    $native = $Phase -notin @('Static')
    if ($native) {
        if ($env:CI_NATIVE_BUILDS_DISABLED -eq 'true') { throw 'Native compilation is forbidden in the PR/static lane.' }
        if ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted') { throw 'Use the canonical local build/test commands; this adapter is a hosted qualification entry point.' }
        $hostArchitecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        if (($Platform -eq 'ARM64' -and $hostArchitecture -cne 'Arm64') -or ($Platform -eq 'x64' -and $hostArchitecture -cne 'X64')) { throw 'Native qualification requires the matching native host architecture.' }
    }
    $batch = $null
    if ($native) {
        if (-not $Descriptor) { throw 'Native phases require the frozen admission descriptor.' }
        $batch = Get-Content -LiteralPath $Descriptor -Raw | ConvertFrom-Json -AsHashtable
        $actual = New-CiInputDescriptor $Root
        if ($batch.repository -cne $project.repository -or $batch.commit -cne $actual.commit -or
            $batch.nativeDigest -cne $actual.nativeDigest -or $batch.engine.ref -cne $project.engine.ref -or
            $batch.buildNumber -ne $actual.buildNumber -or $batch.version -cne $actual.version) { throw 'Frozen native input/version identity mismatch.' }
        if ($env:GITHUB_REPOSITORY -cne $project.repository) { throw 'Native adapter repository mismatch.' }
    }
    [ordered]@{ root = [IO.Path]::GetFullPath($Root); engineRoot = [IO.Path]::GetFullPath($EngineRoot);
        project = $project; batch = $batch; platform = $Platform; phase = $Phase; development = [bool]$DevelopmentEngine }
}

function Invoke-CiProjectScript {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Context, [Parameter(Mandatory)][string]$Script,
        [string[]]$Arguments = @(), [int]$TimeoutSeconds = 18000)
    $path = Assert-CiContainedPath $Context.root (Join-Path $Context.root $Script)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing project command: $Script" }
    if ($Context.phase -eq 'Static') {
        $allowed = @('Tools/Test-Changelog.ps1','validate-skills.ps1','validate-specs.ps1','validate-dependencies.ps1',
            'validate-test-port.ps1','validate-build-matrix.ps1','Tools/Get-SpecInventory.ps1','Tools/Get-ToolInventory.ps1',
            'Tools/Verify-NoSubclassManager.ps1','Tools/Audit-ComctlReportSurfaces.ps1','Tools/Audit-VisibleNativeSurfaces.ps1')
        if ($Context.project.repository -eq 'RedSalamanders/RedMonitor') { $allowed += 'validate.ps1' }
        if ($Script.Replace('\','/') -cnotin $allowed) { throw "Project command is not in the reviewed compiler-free static subset: $Script" }
    }
    $hostPath = (Get-Process -Id $PID).Path
    $commandArguments = @('-NoProfile','-NonInteractive','-File',$path) + $Arguments
    $result = Invoke-CiProcess -FilePath $hostPath -Arguments $commandArguments -WorkingDirectory $Context.root -TimeoutSeconds $TimeoutSeconds -Stream
    if ($result.exitCode -ne 0) { throw "Project command failed: $Script ($($result.exitCode))." }
}

function Test-CiProjectConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Context)
    $project = $Context.project
    if ($project.engine.ref -eq ('0' * 40) -and -not $Context.development) { throw 'A placeholder engine pin cannot pass CI.' }
    $scopePath = Join-Path $Context.root 'Tests/test-scopes.json'
    if (Test-Path -LiteralPath $scopePath) {
        $scopes = Get-Content -LiteralPath $scopePath -Raw | ConvertFrom-Json -AsHashtable
        if ($scopes.Contains('prCoverage') -and @($scopes.prCoverage).Count) { throw 'Native obligations cannot be delegated to compiler-free PR checks.' }
    }
    $adapter = Assert-CiContainedPath $Context.root (Join-Path $Context.root $project.adapter)
    if (-not (Test-Path -LiteralPath $adapter -PathType Leaf)) { throw 'The declared project adapter is missing.' }
    $files = (Invoke-CiGit $Context.root @('ls-files', '-z', '--', '*.ps1', '*.psm1', '*.props', '*.targets', '*.vcxproj')).stdout.Split([char]0)
    foreach ($path in $files) {
        if (-not $path -or $path -match '^(Specs/TestRuns|Specs/Plans/Done|Measurements|legacy|ThirdParty|External)/') { continue }
        $full = Join-Path $Context.root $path
        if ([IO.Path]::GetExtension($path) -in @('.ps1','.psm1')) {
            $tokens = $null; $errors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($full, [ref]$tokens, [ref]$errors)
            if ($errors.Count) { throw "PowerShell parse failure: $path : $($errors[0].Message)" }
        } else {
            $null = [xml][IO.File]::ReadAllText($full)
        }
    }
    Write-Host "Validated policy $($project.policyVersion), adapter, source syntax and compiler-free PR delegation for $($project.repository)."
}

function Invoke-CiAssertionProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory)][string]$Executable, [string[]]$Arguments = @('--ci-assertion-probe'),
        [Parameter(Mandatory)][int]$ExpectedExitCode, [string]$ExpectedMarker = 'CI_ASSERTION_PROBE')
    $path = Assert-CiContainedPath $Context.root (Join-Path $Context.root $Executable)
    $result = Invoke-CiProcess $path $Arguments $Context.root -TimeoutSeconds 60 -AllowFailure
    $text = $result.stdout + $result.stderr
    if ($result.exitCode -ne $ExpectedExitCode -or $ExpectedExitCode -eq 0 -or
        -not $text.Contains($ExpectedMarker) -or $text.Contains('CI_ASSERTION_PROBE_DISABLED')) { throw 'The Release failure-detection canary did not produce its exact expected failure.' }
    Write-Host "Verified active Release assertion probe: $ExpectedMarker, exit $($result.exitCode)."
    return $true
}

function Get-CiBinaryArtifacts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Context, [Parameter(Mandatory)][string[]]$Paths)
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($path in $Paths) {
        $full = Assert-CiContainedPath $Context.root (Join-Path $Context.root $path)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Missing built binary: $path" }
        $rows.Add([ordered]@{ path = $path.Replace('\','/'); sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() })
    }
    return ,$rows.ToArray()
}

function Write-CiRegressionReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory)][int]$Discovered, [Parameter(Mandatory)][int]$Executed,
        [Parameter(Mandatory)][bool]$AssertionProbePassed, [Parameter(Mandatory)][object[]]$Artifacts,
        [Parameter(Mandatory)][string]$EvidenceDirectory, [Parameter(Mandatory)][object[]]$CanonicalEvidence)
    if ($Discovered -le 0 -or $Executed -ne $Discovered -or -not $AssertionProbePassed -or -not $CanonicalEvidence.Count) { throw 'Incomplete native regression execution; no passing receipt can be written.' }
    $receipt = [ordered]@{ schemaVersion = 1; repository = $Context.batch.repository; commit = $Context.batch.commit;
        nativeDigest = $Context.batch.nativeDigest; platform = $Context.platform; role = 'ReleaseTest'; passed = $true;
        discovered = $Discovered; executed = $Executed; failed = 0; unexpectedSkipped = 0;
        assertionProbePassed = $AssertionProbePassed; artifacts = $Artifacts; canonicalEvidence = $CanonicalEvidence;
        runId = $env:GITHUB_RUN_ID; completedAt = [DateTimeOffset]::UtcNow.ToString('o') }
    $null = Test-CiRegressionReceipt $receipt $Context.batch $Context.platform
    [void][IO.Directory]::CreateDirectory($EvidenceDirectory)
    $path = Assert-CiContainedPath $EvidenceDirectory (Join-Path $EvidenceDirectory ("regression-$($Context.platform).json"))
    [IO.File]::WriteAllText($path, ($receipt | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value ('receipt_path=' + $path) }
    Write-Host "Source-bound regression receipt: $path"
}

function Write-CiProductionReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Context, [Parameter(Mandatory)][string[]]$Archives,
        [Parameter(Mandatory)][bool]$TestModeDisabled, [Parameter(Mandatory)][bool]$SmokePassed)
    if (-not $TestModeDisabled -or -not $SmokePassed -or -not $Archives.Count) { throw 'Production mode and native smoke are required before retaining a distributable ZIP.' }
    $rows = [Collections.Generic.List[object]]::new()
    $stage = Assert-CiContainedPath $Context.root (Join-Path $Context.root ".build/ci/production/$($Context.platform)")
    [void][IO.Directory]::CreateDirectory($stage)
    foreach ($archive in $Archives) {
        $source = Assert-CiContainedPath $Context.root $archive
        if ([IO.Path]::GetExtension($source) -cne '.zip' -or -not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Publication accepts existing qualified ZIP archives only.' }
        $destination = Assert-CiContainedPath $Context.root (Join-Path $stage ([IO.Path]::GetFileName($source)))
        if (-not $source.Equals($destination, [StringComparison]::OrdinalIgnoreCase)) { Copy-Item -LiteralPath $source -Destination $destination }
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash) { throw 'Staging changed qualified ZIP bytes.' }
        $rows.Add([ordered]@{ file = [IO.Path]::GetFileName($destination); sha256 = $hash; size = (Get-Item -LiteralPath $destination).Length })
    }
    $receipt = [ordered]@{ schemaVersion = 1; repository = $Context.batch.repository; commit = $Context.batch.commit;
        nativeDigest = $Context.batch.nativeDigest; engine = $Context.batch.engine; platform = $Context.platform;
        version = $Context.batch.version; buildNumber = $Context.batch.buildNumber; role = 'ProductionRelease';
        testModeDisabled = $true; smokePassed = $true; kind = $Context.project.kind; archives = $rows.ToArray(); runId = $env:GITHUB_RUN_ID }
    $path = Assert-CiContainedPath $Context.root (Join-Path $stage ("production-$($Context.platform).json"))
    [IO.File]::WriteAllText($path, ($receipt | ConvertTo-Json -Depth 15), [Text.UTF8Encoding]::new($false))
    if ($env:GITHUB_OUTPUT) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value @('receipt_path=' + $path, 'archive_directory=' + $stage)
    }
    Write-Host "Qualified production ZIP receipt: $path"
}

Export-ModuleMember -Function New-CiProjectContext, Invoke-CiProjectScript, Test-CiProjectConfiguration, Invoke-CiAssertionProbe, Get-CiBinaryArtifacts, Write-CiRegressionReceipt, Write-CiProductionReceipt
