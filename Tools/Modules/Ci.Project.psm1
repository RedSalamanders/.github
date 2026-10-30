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
        $processArchitecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        if($hostArchitecture -cne $processArchitecture){throw 'Native qualification cannot run through an emulated PowerShell host.'}
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
        if ((Invoke-CiGit $Root @('status','--porcelain','--untracked-files=normal')).stdout.Trim()) { throw 'Native qualification requires a clean exact source checkout.' }
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
    $result = Invoke-CiProcess -FilePath $hostPath -Arguments $commandArguments -WorkingDirectory $Context.root -TimeoutSeconds $TimeoutSeconds -Stream -AllowFailure
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
    $lf=[string][char]10
    $crlf=[string][char]13+$lf
    $templates=Get-ChildItem -LiteralPath (Join-Path $Context.engineRoot 'Templates') -Filter '*.yml' -File
    $core=@($templates.Name)
    foreach($template in $templates){
        $operations=if($project.kind -ceq 'sdk'){'Prepare, Release'}else{'Prepare, Release, Winget'}
        $expected=[IO.File]::ReadAllText($template.FullName).Replace('@ENGINE@',$project.engine.ref).Replace('@OPERATIONS@',$operations).Replace($crlf,$lf).TrimEnd()
        $path=Join-Path $Context.root ('.github/workflows/'+$template.Name)
        if(-not(Test-Path -LiteralPath $path) -or [IO.File]::ReadAllText($path).Replace($crlf,$lf).TrimEnd() -cne $expected){
            throw "The common workflow or engine pin diverged: $($template.Name)"
        }
    }
    $extensions=(Get-Content (Join-Path $Context.engineRoot 'Policy/extensions.json') -Raw|ConvertFrom-Json -AsHashtable)[$project.repository.Split('/')[1]]
    foreach($workflow in Get-ChildItem -LiteralPath (Join-Path $Context.root '.github/workflows') -Filter '*.yml' -File){
        if($workflow.Name -cin $core){continue}
        $text=[IO.File]::ReadAllText($workflow.FullName).Replace($crlf,$lf)
        if($extensions.sealedDisabled.Contains($workflow.Name)){
            if((Get-CiSha256 $text) -cne $extensions.sealedDisabled[$workflow.Name]){throw 'The sealed disabled workflow bytes changed.'}
            continue
        }
        if($extensions.metadata.Contains($workflow.Name)){
            if((Get-CiSha256 $text) -cne $extensions.metadata[$workflow.Name]){throw 'Scheduled metadata workflow changed; review its no-build dependency closure before updating policy.'}
            continue
        }
        if($workflow.Name -cnotin $extensions.manual){throw "Workflow has no reviewed owner/routing classification: $($workflow.Name)"}
        if($text -match '(?m)^  (?:push|pull_request|pull_request_target|schedule|workflow_run|release|repository_dispatch):'){
            throw "Extended native workflow has a forbidden automatic trigger: $($workflow.Name)"
        }
        if($extensions.sealed.Contains($workflow.Name) -and (Get-CiSha256 $text) -cne $extensions.sealed[$workflow.Name]){throw 'A sealed historical workflow changed.'}
    }
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

function Assert-CiPeArchitecture {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform)
    $stream=[IO.File]::OpenRead($Path)
    $reader=[IO.BinaryReader]::new($stream)
    try{
        if($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d){throw 'Native qualification requires a valid PE image.'}
        $stream.Position=0x3c
        $pe=$reader.ReadUInt32()
        if($pe -lt 64 -or [long]$pe+6 -gt $stream.Length){throw 'Invalid PE header boundary.'}
        $stream.Position=$pe
        if($reader.ReadUInt32() -ne 0x00004550){throw 'Invalid PE signature.'}
        $machine=$reader.ReadUInt16()
        $expected=if($Platform -ceq 'ARM64'){0xaa64}else{0x8664}
        if($machine -ne $expected){throw 'Native qualification refuses an emulated or wrong-architecture executable.'}
    }finally{$reader.Dispose();$stream.Dispose()}
}

function Invoke-CiAssertionProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory)][string]$Executable, [string[]]$Arguments = @('--ci-assertion-probe'),
        [Parameter(Mandatory)][int]$ExpectedExitCode, [string]$ExpectedMarker = 'CI_ASSERTION_PROBE')
    $path = Assert-CiContainedPath $Context.root (Join-Path $Context.root $Executable)
    Assert-CiPeArchitecture -Path $path -Platform $Context.platform
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
        [Parameter(Mandatory)][string]$EvidenceDirectory, [Parameter(Mandatory)][object[]]$CanonicalEvidence,
        [ValidateSet('case','required-case','suite','scenario')][string]$CountUnit='case',
        [int]$Registered=0,[int]$ExpectedSkipped=0)
    if ($Discovered -le 0 -or $Executed -ne $Discovered -or -not $AssertionProbePassed -or -not $CanonicalEvidence.Count) { throw 'Incomplete native regression execution; no passing receipt can be written.' }
    Assert-CiSourceFrozen $Context
    if($Registered -eq 0){$Registered=$Discovered+$ExpectedSkipped}
    $receipt = [ordered]@{ schemaVersion = 1; repository = $Context.batch.repository; commit = $Context.batch.commit;
        nativeDigest = $Context.batch.nativeDigest; platform = $Context.platform; role = 'ReleaseTest'; passed = $true;
        countUnit=$CountUnit;registered=$Registered;expectedSkipped=$ExpectedSkipped;
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
    Assert-CiSourceFrozen $Context
    if($Context.project.kind -ceq 'application'){
        $binary=Join-Path $Context.root ".build/$($Context.platform)/Release/$($Context.project.winget.executable)"
        Assert-CiPeArchitecture -Path $binary -Platform $Context.platform
        $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($binary)
        $actual="$($version.FileMajorPart).$($version.FileMinorPart).$($version.FileBuildPart)"
        if($actual -cne $Context.batch.version){throw 'Production executable and frozen batch version differ.'}
    }
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

function Assert-CiSourceFrozen {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Context)
    if ((Resolve-CiCommit $Context.root HEAD) -cne $Context.batch.commit -or
        (Invoke-CiGit $Context.root @('status','--porcelain','--untracked-files=normal')).stdout.Trim()) {
        throw 'Source changed during native qualification; no passing receipt can be published.'
    }
}

function Get-CiEvidenceReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Paths)
    $rows = foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Canonical evidence is missing: $path" }
        [ordered]@{ path = [IO.Path]::GetFullPath($path); sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    return ,@($rows)
}

function Get-CiProfileArtifacts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Context)
    $profile=Assert-CiContainedPath $Context.root (Join-Path $Context.root ".build/$($Context.platform)/Release")
    $paths=@(Get-ChildItem -LiteralPath $profile -Recurse -File|Where-Object Extension -in @('.exe','.dll','.lib')|
        ForEach-Object{[IO.Path]::GetRelativePath($Context.root,$_.FullName).Replace('\','/')})
    if(-not $paths.Count){throw 'No native profile artifacts were produced.'}
    return Get-CiBinaryArtifacts -Context $Context -Paths $paths
}

function Get-CiSuiteEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Context, [Parameter(Mandatory)][DateTime]$StartedAt)
    $root = Join-Path $Context.root '.build/evidence/test-runs'
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -Filter 'normal-suites.json' -File |
        Where-Object { $_.LastWriteTimeUtc -ge $StartedAt })
    if (-not $files.Count) { throw 'No fresh canonical native suite summary was produced.' }
    $total = 0; $references = [Collections.Generic.List[string]]::new()
    foreach ($file in $files) {
        $completed = Join-Path (Split-Path -Parent $file.DirectoryName) 'completed.json'
        $completion = Get-Content -LiteralPath $completed -Raw | ConvertFrom-Json -AsHashtable
        $receipt = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        if ($completion.outcome -cne 'passed' -or $receipt.passed -isnot [bool] -or -not $receipt.passed -or
            $receipt.filtered -ne $false -or $receipt.platform -cne $Context.platform -or $receipt.configuration -cne 'Release' -or
            @($receipt.discovered).Count -eq 0 -or @($receipt.discovered).Count -ne @($receipt.executed).Count -or
            (@($receipt.discovered | Sort-Object -Unique) -join ',') -cne (@($receipt.executed | Sort-Object -Unique) -join ',')) {
            throw 'Canonical native suites are incomplete, filtered or do not match this Release profile.'
        }
        $total += @($receipt.executed).Count
        $references.Add($file.FullName); $references.Add($completed)
    }
    [ordered]@{ countUnit = 'suite'; discovered = $total; executed = $total; evidence = (Get-CiEvidenceReference $references.ToArray()) }
}

Export-ModuleMember -Function New-CiProjectContext, Invoke-CiProjectScript, Test-CiProjectConfiguration, Assert-CiPeArchitecture, Invoke-CiAssertionProbe, Get-CiBinaryArtifacts, Get-CiProfileArtifacts, Write-CiRegressionReceipt, Write-CiProductionReceipt, Get-CiEvidenceReference, Get-CiSuiteEvidence
