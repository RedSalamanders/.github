<#
.SYNOPSIS
Tests the engine modules that products import through module shims, and the shims themselves, without compilation.
.DESCRIPTION
Builds fixture products whose .ci-engine is an independent Git checkout of this engine's files, imports each module shim
of Templates/Project the way a product does, and runs the module's behavior cases through it. Also covers every refusal
of a module shim: a missing or other-commit engine and a nested copy without its own manifest.
.PARAMETER TestRoot
Existing marked RedSalamander.Perf root, or a hosted RUNNER_TEMP descendant. Creates one unique child only.
.OUTPUTS
Case results and results.json beneath the created child, which is retained. Nonzero exit on a failed case.
.NOTES
Requires PowerShell 7.4 and Git. No credentials, compiler, network or desktop input.
.EXAMPLE
./Tests/Test-ProjectModules.ps1 -TestRoot Z:/RedSalamander.Perf
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
    if (-not $selected.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Hosted module fixtures must remain under RUNNER_TEMP.' }
} elseif ($selected -notmatch '^[A-Za-z]:[\\/]RedSalamander\.Perf$' -or
    -not (Test-Path -LiteralPath (Join-Path $selected '.red-salamander-test-root')) -or
    [IO.File]::ReadAllText((Join-Path $selected '.red-salamander-test-root')).Trim() -cne 'red-salamander.test-sandbox-root.v1') {
    throw 'Module fixtures require the existing marked test root.'
}
$runRoot = Join-Path $selected ('unified-ci/modules-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runRoot)
$rows = [Collections.Generic.List[object]]::new()

function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Refuses([scriptblock]$Body, [string]$Pattern) {
    $message = ''
    try { & $Body | Out-Null } catch { $message = $_.Exception.Message }
    Require ($message -and $message -match $Pattern) "Expected a refusal matching '$Pattern', received '$message'."
    return $message
}
function Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; $rows.Add([ordered]@{ name = $Name; passed = $true }); Write-Host "PASS $Name" }
    catch { $rows.Add([ordered]@{ name = $Name; passed = $false; error = $_.Exception.Message }); Write-Host "FAIL $Name : $($_.Exception.Message)" -ForegroundColor Red }
}
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
    foreach ($setting in @(@('user.name', 'Module fixture'), @('user.email', 'modules@fixture.invalid'), @('commit.gpgsign', 'false'),
            @('core.autocrlf', 'false'), @('core.longpaths', 'true'), @('core.hooksPath', (Join-Path $Root '.no-hooks')))) {
        [void](Invoke-FixtureGit $Root (@('config') + $setting))
    }
}
$engineFiles = @('Schemas/project.schema.json', 'Tools/Modules/Ci.Policy.psm1', 'Tools/Modules/Ci.EngineBinding.psm1', 'Tools/Modules/Ci.BuildConsole.psm1')
function New-ModuleProduct([string]$Name) {
    # A product checkout with this engine's module shims and a .ci-engine checkout of this engine's files at its pin.
    $root = Join-Path $runRoot $Name
    New-Repository $root
    $engine = Join-Path $root '.ci-engine'
    New-Repository $engine
    foreach ($relative in $engineFiles) { Put $engine $relative ([IO.File]::ReadAllText((Join-Path $engineRoot $relative))) }
    [void](Invoke-FixtureGit $engine @('add', '--all'))
    [void](Invoke-FixtureGit $engine @('commit', '-q', '-m', 'Fixture engine'))
    $pin = (Invoke-FixtureGit $engine @('rev-parse', 'HEAD'))[0].Trim()
    $manifest = [ordered]@{ schemaVersion = 1; policyVersion = '1'; repository = 'RedSalamanders/RedMonitor';
        engine = [ordered]@{ repository = 'RedSalamanders/.github'; ref = $pin }; kind = 'application';
        adapter = 'Tools/Invoke-ProjectCi.ps1'; include = @('Tests/fixtures/**'); exclude = @('CHANGELOG.md', 'Changes/**');
        formatRoots = @('src'); versionBase = '0.1';
        winget = [ordered]@{ identifier = 'RedSalamanders.RedMonitor'; executable = 'RedMonitor.exe'; alias = 'redmonitor' } }
    Put $root '.ci/project.json' ($manifest | ConvertTo-Json -Depth 8)
    Put $root '.gitignore' ".ci-engine/`n"
    foreach ($shim in Get-ChildItem (Join-Path $engineRoot 'Templates/Project') -Recurse -File -Filter '*.psm1') {
        $relative = [IO.Path]::GetRelativePath((Join-Path $engineRoot 'Templates/Project'), $shim.FullName).Replace('\', '/')
        Put $root $relative ([IO.File]::ReadAllText($shim.FullName))
    }
    [void](Invoke-FixtureGit $root @('add', '--all'))
    [void](Invoke-FixtureGit $root @('commit', '-q', '-m', 'Fixture product'))
    return [pscustomobject]@{ Root = $root; Engine = $engine; Pin = $pin }
}
function Import-Shim([string]$Path) {
    # Imported as products do, by path, so each case sees exactly that shim's exports.
    Remove-Module -Name ([IO.Path]::GetFileNameWithoutExtension($Path)) -Force -ErrorAction SilentlyContinue
    return Import-Module $Path -Force -PassThru -Global
}

Case 'the BuildConsole module shim exports exactly the engine module''s functions' {
    $product = New-ModuleProduct 'console-exports'
    $shim = Import-Shim (Join-Path $product.Root 'Build/BuildConsole.psm1')
    $engineModule = Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.BuildConsole.psm1') -Force -PassThru -Scope Local
    $expected = @($engineModule.ExportedFunctions.Keys | Sort-Object) -join ','
    Require ((@($shim.ExportedFunctions.Keys | Sort-Object) -join ',') -ceq $expected) "The shim exports $(@($shim.ExportedFunctions.Keys) -join ',') instead of $expected."
    Remove-Module $engineModule.Name -Force -ErrorAction SilentlyContinue
}

Case 'build console diagnostics, results and links behave the same through the shim' {
    $product = New-ModuleProduct 'console-behavior'
    [void](Import-Shim (Join-Path $product.Root 'Build/BuildConsole.psm1'))
    $scratch = Join-Path $runRoot 'console-behavior-scratch'
    [void][IO.Directory]::CreateDirectory($scratch)
    $clean = Join-Path $scratch 'clean.log'
    [IO.File]::WriteAllText($clean, 'Build succeeded. 0 Warning(s) 0 Error(s)')
    Assert-NativeBuildDiagnostics -LogPath $clean
    foreach ($diagnostic in @('source.cpp(4): warning C4100: unused parameter', '2>C:\work\source.cpp(4): warning C4365: sign conversion',
            'LINK : warning LNK4099: missing PDB', 'cl : Command line warning D9025 : overriding option',
            'project.targets(8,3): warning MSB1234: build diagnostic', 'warning : custom build diagnostic')) {
        $warn = Join-Path $scratch 'warning.log'
        [IO.File]::WriteAllText($warn, $diagnostic)
        $facts = Get-NativeBuildDiagnostics -LogPath $warn
        Require ($facts.WarningCount -eq 1 -and $facts.ErrorCount -eq 0) "Missed diagnostic: $diagnostic"
        [void](Refuses { Assert-NativeBuildDiagnostics -LogPath $warn } 'Zero-warning')
    }
    $errorLog = Join-Path $scratch 'error.log'
    [IO.File]::WriteAllText($errorLog, 'file.cpp(1): fatal error C1083: missing header')
    [void](Refuses { Assert-NativeBuildDiagnostics -LogPath $errorLog } 'Zero-warning')
    [void](Refuses { Assert-NativeBuildDiagnostics -LogPath (Join-Path $scratch 'missing.log') } 'missing')
    $crashLog = Join-Path $scratch 'tool-exception.log'
    foreach ($dump in @('  ExceptionCode = C0000006', '3> ExceptionCode = c0000005', ' ExceptionCode = 0xE06D7363')) {
        [IO.File]::WriteAllText($crashLog, $dump + "`n    ExceptionInformation[ 2] = C000007F`n" + [IO.File]::ReadAllText($clean))
        $facts = Get-NativeBuildDiagnostics -LogPath $crashLog
        Require ($facts.ToolExceptionCount -eq 1 -and $facts.WarningCount -eq 0 -and $facts.ErrorCount -eq 0) 'A structured child exception must survive a clean MSBuild footer.'
        [void](Refuses { Assert-NativeBuildDiagnostics -LogPath $crashLog } 'tool process exception')
    }
    foreach ($ordinary in @('source.cpp: text ExceptionCode = C0000006', 'ExceptionCode = 00000000', 'ExceptionCode = not-a-code')) {
        [IO.File]::WriteAllText($crashLog, $ordinary + "`n" + [IO.File]::ReadAllText($clean))
        Assert-NativeBuildDiagnostics -LogPath $crashLog
    }
    $binary = Join-Path $scratch "synthetic # app's É.exe"
    # Deliberately not executable: writing a result must never launch it.
    [IO.File]::WriteAllText($binary, 'A synthetic artifact, never run.')
    Require ((ConvertTo-NativeBuildLink -LiteralPath $binary -HyperlinkMode Never) -ceq [IO.Path]::GetFullPath($binary)) 'Plain link mode changed the path.'
    if ($IsWindows) {
        $link = ConvertTo-NativeBuildLink -LiteralPath $binary -HyperlinkMode Always
        Require ($link.Contains('file://localhost/') -and $link.Contains('%20') -and $link.Contains('%23')) 'File hyperlink was not URI-escaped and locally hosted.'
        Require ($link.Contains([string][char]27 + ']8;;')) 'OSC 8 opening sequence missing.'
    }
    [void](Refuses { ConvertTo-NativeBuildLink -LiteralPath ('unsafe' + [char]27 + 'path') -HyperlinkMode Always } 'control characters')
    $records = @(Write-NativeBuildResult -Project Fixture -Platform x64 -Configuration Release -LogPath $clean -Artifacts @($binary) -Executable $binary -ColorMode Always -HyperlinkMode Always 6>&1)
    $messages = @($records | ForEach-Object { [string]$_.MessageData })
    Require (@($messages | Where-Object { $_ -like 'BUILD SUCCEEDED:*' }).Count -eq 1) 'Common success header missing.'
    foreach ($record in $records) { Require ([string]$record.MessageData.ForegroundColor -eq 'Green') 'A successful result line is not green.' }
    [void](Refuses { Write-NativeBuildResult -Project Fixture -Platform x64 -Configuration Release -LogPath $errorLog -Artifacts @($binary) } 'Zero-warning')
    [IO.File]::WriteAllText($crashLog, "ExceptionCode = C0000006`n" + [IO.File]::ReadAllText($clean))
    [void](Refuses { Write-NativeBuildResult -Project Fixture -Platform x64 -Configuration Release -LogPath $crashLog -Artifacts @($binary) } 'tool process exception')
    [void](Refuses { Write-NativeBuildResult -Project Fixture -Platform x64 -Configuration Release -LogPath $clean -Artifacts @((Join-Path $scratch 'absent.exe')) } 'missing')
}

Case 'a module shim refuses a missing, other-commit or changed engine and a nested copy without its manifest' {
    $product = New-ModuleProduct 'console-refusals'
    $shim = Join-Path $product.Root 'Build/BuildConsole.psm1'
    Put $product.Engine 'README.md' 'A later engine commit.'
    [void](Invoke-FixtureGit $product.Engine @('add', '--all'))
    [void](Invoke-FixtureGit $product.Engine @('commit', '-q', '-m', 'Later'))
    $later = (Invoke-FixtureGit $product.Engine @('rev-parse', 'HEAD'))[0].Trim()
    $message = Refuses { Import-Shim $shim } 'runs the shared CI engine'
    Require ($message.Contains("pins ($($product.Pin))") -and $message.Contains("it is at $later") -and $message.Contains("checkout --detach $($product.Pin)")) "Another engine commit was not named with the fix: $message"
    [void](Invoke-FixtureGit $product.Engine @('checkout', '-q', '--detach', $product.Pin))
    [void](Import-Shim $shim)
    Add-Content -LiteralPath (Join-Path $product.Engine 'Tools/Modules/Ci.BuildConsole.psm1') -Value '# local edit'
    [void](Refuses { Import-Shim $shim } 'changes to tracked files')
    [void](Invoke-FixtureGit $product.Engine @('checkout', '-q', '--', 'Tools/Modules/Ci.BuildConsole.psm1'))
    Move-Item -LiteralPath $product.Engine -Destination (Join-Path $product.Root 'engine-away')
    [void](Refuses { Import-Shim $shim } 'is missing or predates engine shims')
    Move-Item -LiteralPath (Join-Path $product.Root 'engine-away') -Destination $product.Engine
    [void](Import-Shim $shim)
    # A copy in a nested fixture repository without its own manifest never binds to the product around it.
    $nested = Join-Path $product.Root '.build/fixture'
    New-Repository $nested
    Put $nested 'Build/BuildConsole.psm1' ([IO.File]::ReadAllText($shim))
    [void](Refuses { Import-Shim (Join-Path $nested 'Build/BuildConsole.psm1') } 'is missing or predates engine shims')
}

Case 'a module shim finds its product root up to three levels above it' {
    $product = New-ModuleProduct 'console-depth'
    $deep = Join-Path $product.Root 'Tools/Modules/Testing/BuildConsole.psm1'
    Put $product.Root 'Tools/Modules/Testing/BuildConsole.psm1' ([IO.File]::ReadAllText((Join-Path $product.Root 'Build/BuildConsole.psm1')))
    $module = Import-Shim $deep
    Require ($module.ExportedFunctions.ContainsKey('Assert-NativeBuildDiagnostics')) 'A shim three levels below the product root did not bind.'
}

$failed = @($rows | Where-Object { -not $_.passed }).Count
[IO.File]::WriteAllText((Join-Path $runRoot 'results.json'), ([ordered]@{ schemaVersion = 1; passed = $failed -eq 0; executed = $rows.Count; failed = $failed; cases = $rows.ToArray() } | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Host "Module shims: $($rows.Count - $failed) passed, $failed failed. Results: $runRoot"
if ($failed) { throw "$failed module case(s) failed; preserve $runRoot." }
