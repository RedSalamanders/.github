<#
.SYNOPSIS
Exercises shared Visual Studio discovery and triplet generation with contained, compiler-free fixtures.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$engine = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $engine 'Tools/Modules/Ci.Policy.psm1')
Import-Module (Join-Path $engine 'Tools/Modules/Ci.VisualStudio.psm1')
Import-Module (Join-Path $engine 'Tools/Modules/Ci.VcpkgTriplet.psm1')

function Assert-Equal($Expected, $Actual) {
    if ($Expected -cne $Actual) { throw "Expected '$Expected', received '$Actual'." }
}

function Assert-Refused([scriptblock] $Action, [string] $Message) {
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message.Contains($Message)) { return }
        throw
    }
    throw "Expected refusal naming '$Message'."
}

function Write-FixtureFile([string] $Name, [string] $Content) {
    $path = Assert-CiContainedPath -Root $fixture -Path (Join-Path $fixture $Name)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $Content)
    return $path
}

$run = 'native-toolchain-' + [guid]::NewGuid().ToString('N')
if ($env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted' -and $env:RUNNER_TEMP) {
    $fixture = Assert-CiContainedPath -Root $env:RUNNER_TEMP -Path (Join-Path $env:RUNNER_TEMP "unified-ci-tests/$run")
} else {
    $fixture = Assert-CiContainedPath -Root $engine -Path (Join-Path $engine ".build/$run")
}
$setup = Join-Path $engine '.github/actions/setup-msvc/Setup.ps1'
$setupRoot = Join-Path $fixture 'setup-policy'
foreach ($invalidPolicy in @(
    '<Project><PropertyGroup /></Project>',
    '<Project><PropertyGroup><RequiredMsvcToolsVersion>latest</RequiredMsvcToolsVersion></PropertyGroup></Project>',
    '<Project><PropertyGroup><RequiredMsvcToolsVersion>14.52</RequiredMsvcToolsVersion><RequiredMsvcToolsVersion>14.53</RequiredMsvcToolsVersion></PropertyGroup></Project>'
)) {
    [void](Write-FixtureFile 'setup-policy/Directory.Build.props' $invalidPolicy)
    Assert-Refused { & $setup -ProjectRoot $setupRoot -VerifyOnly } 'must declare one required MSVC major.minor family'
}
foreach ($invalidBudget in @(0,3601)) {
    Assert-Refused { & $setup -ProjectRoot $setupRoot -VerifyOnly -InstallerTimeoutSeconds $invalidBudget } 'InstallerTimeoutSeconds'
}
Write-Host 'PASS shared setup rejects invalid product MSVC policy and installer budgets before discovery'

$tokens = $null
$errors = $null
$setupAst = [Management.Automation.Language.Parser]::ParseFile($setup,[ref]$tokens,[ref]$errors)
Assert-Equal 0 $errors.Count
# Exercise just the in-process dispatch with a recording callback and no installer.
$dispatches = @($setupAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -ceq '$InstallerRunner' -and
        $node.Clauses[0].Item2.Extent.Text.Contains('-TimeoutMilliseconds')
}, $true))
Assert-Equal 1 $dispatches.Count
$dispatch = $dispatches[0].Clauses[0].Item2.Extent.Text
$dispatch = [scriptblock]::Create($dispatch.Substring(1,$dispatch.Length-2))

function Invoke-InstallerDispatchFixture([scriptblock]$InstallerRunner) {
    $scratch = Join-Path $fixture 'installer workspace with spaces'
    $installer = Join-Path $scratch 'fixture.exe'
    $stdout = Join-Path $scratch 'bootstrapper.stdout.log'
    $stderr = Join-Path $scratch 'bootstrapper.stderr.log'
    $arguments = @('--quiet','--installPath',(Join-Path $scratch 'install root'))
    $installerTimeoutMilliseconds = 2700000
    $installerExit = $null
    $installerFailure = $null
    . $dispatch
    return @{ ExitCode=$installerExit; Failure=$installerFailure }
}
$result = Invoke-InstallerDispatchFixture {
    param($FilePath,[string[]]$Arguments,$WorkingDirectory,$LogPath,$ErrorLogPath,$TimeoutMilliseconds)
    Assert-Equal (Join-Path $WorkingDirectory 'fixture.exe') $FilePath
    Assert-Equal (Join-Path $WorkingDirectory 'bootstrapper.stdout.log') $LogPath
    Assert-Equal (Join-Path $WorkingDirectory 'bootstrapper.stderr.log') $ErrorLogPath
    Assert-Equal (Join-Path $WorkingDirectory 'install root') $Arguments[2]
    Assert-Equal 2700000 $TimeoutMilliseconds
    return 3010
}
Assert-Equal 3010 $result.ExitCode
Assert-Equal $null $result.Failure
$result = Invoke-InstallerDispatchFixture { throw 'Fixture timeout' }
Assert-Equal 'Fixture timeout' $result.Failure.Exception.Message
$result = Invoke-InstallerDispatchFixture { 'invalid result' }
Assert-Equal 'The product installer runner must return one integer exit code.' $result.Failure.Exception.Message
Write-Host 'PASS installer dispatch retains the argument array, diagnostic paths, timeout, and exact result'

$installation = Join-Path $fixture 'VS Fixture'
$versionPath = 'VS Fixture/VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'
$x64 = Write-FixtureFile 'VS Fixture/MSBuild/Current/Bin/amd64/MSBuild.exe' ''
$arm64 = Write-FixtureFile 'VS Fixture/MSBuild/Current/Bin/arm64/MSBuild.exe' ''
$orphan = Write-FixtureFile 'orphan/MSBuild.exe' ''
Assert-Equal $x64 (Get-CiNativeMSBuild -Installation $installation -Architecture X64)
Assert-Equal $arm64 (Get-CiNativeMSBuild -Installation $installation -Architecture Arm64)
Assert-Refused { Get-CiNativeMSBuild -Installation $installation -Architecture X86 } 'x64 or ARM64'
Assert-Refused { Get-CiNativeMSBuild -Installation (Join-Path $fixture 'missing') -Architecture Arm64 } 'Native MSBuild is missing'
Assert-Refused { Get-CiDefaultMsvcToolset -Installation $installation } 'does not exist'
[void](Write-FixtureFile $versionPath 'bad.version')
Assert-Refused { Get-CiDefaultMsvcToolset -Installation $installation } 'not a toolset version'
$versionFile = Write-FixtureFile $versionPath "14.52.37025`r`n"
Assert-Equal $installation (Get-CiVisualStudioInstallationOfMSBuild -MSBuildPath $x64)
Assert-Refused { Get-CiVisualStudioInstallationOfMSBuild -MSBuildPath $orphan } 'is not inside a Visual Studio installation'
$toolset = Get-CiDefaultMsvcToolset -Installation $installation
Assert-Equal '14.52' $toolset.MajorMinor
Assert-Equal '14.52.37025' $toolset.Version
Assert-Equal $versionFile $toolset.VersionFile
Write-Host 'PASS x64 and ARM64 host choice, installation selection, and the default MSVC toolset'

$header = '# preserve the product header'
$inputs = @{ Installation = 'C:\VS "build" $preview'; ToolsetVersion = '14.52'; Header = $header }
$pins = @(
    $header,
    'set(VCPKG_VISUAL_STUDIO_PATH "C:\\VS \"build\" \$preview")',
    'set(VCPKG_PLATFORM_TOOLSET_VERSION "14.52")'
)
foreach ($newline in @("`n", "`r`n")) {
    $source = "set(VCPKG_TARGET_ARCHITECTURE x64)$newline"
    $expected = $source + $newline + ($pins -join $newline) + $newline
    Assert-Equal $expected (Get-CiVcpkgOverlayTripletText -SourceText $source @inputs)
}
Assert-Equal (($pins -join "`n") + "`n") (Get-CiVcpkgOverlayTripletText -SourceText '' @inputs)
Write-Host 'PASS exact overlay text with CRLF, LF, CMake quoting, and the legacy header'

$sourceText = 'set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/asan-toolchain.cmake")'
$triplet = Write-FixtureFile 'trips/arm64-windows-asan.cmake' $sourceText
$companionSource = Write-FixtureFile 'trips/asan-toolchain.cmake' "set(CMAKE_CXX_FLAGS /fsanitize=address)`r`n"
$overlayArgs = @{
    ProjectRoot = $fixture
    SourceTripletPath = $triplet
    Toolset = $toolset
    OutputDirectory = (Join-Path $fixture '.build/arm64')
    Header = $header
}
$created = Update-CiVcpkgOverlayTriplet @overlayArgs
Assert-Equal 'arm64-windows-asan' $created.Triplet
Assert-Equal $true $created.Changed
Assert-Equal 1 $created.Companions.Count
Assert-Equal (Get-FileHash -LiteralPath $companionSource).Hash (Get-FileHash -LiteralPath $created.Companions[0]).Hash

$seedTime = [datetime]::new(2020, 1, 2, 3, 4, 5, [DateTimeKind]::Utc)
[IO.File]::SetLastWriteTimeUtc($created.Path, $seedTime)
[IO.File]::SetLastWriteTimeUtc($created.Companions[0], $seedTime)
$unchanged = Update-CiVcpkgOverlayTriplet @overlayArgs
Assert-Equal $false $unchanged.Changed
Assert-Equal $seedTime ([IO.File]::GetLastWriteTimeUtc($created.Path))
Assert-Equal $seedTime ([IO.File]::GetLastWriteTimeUtc($created.Companions[0]))
[void](Write-FixtureFile 'trips/asan-toolchain.cmake' 'set(CMAKE_CXX_FLAGS_DEBUG /fsanitize=address)')
Assert-Equal $true (Update-CiVcpkgOverlayTriplet @overlayArgs).Changed
Assert-Equal $seedTime ([IO.File]::GetLastWriteTimeUtc($created.Path))
Write-Host 'PASS companion bytes and repeat restore preserve unchanged timestamps'

$invalid = $overlayArgs.Clone()
$invalid.SourceTripletPath = Write-FixtureFile 'trips/missing.cmake' 'include("${CMAKE_CURRENT_LIST_DIR}/missing-helper.cmake")'
Assert-Refused { Update-CiVcpkgOverlayTriplet @invalid } 'missing-helper.cmake'
Assert-Equal $false ([IO.File]::Exists((Join-Path $invalid.OutputDirectory 'missing.cmake')))
$invalid = $overlayArgs.Clone()
$invalid.OutputDirectory = Join-Path $fixture 'outside-build'
Assert-Refused { Update-CiVcpkgOverlayTriplet @invalid } 'contained repository'
Assert-Equal $false ([IO.Directory]::Exists($invalid.OutputDirectory))
$target = Join-Path $fixture 'trips'
$linked = Join-Path $fixture '.build/linked'
$linkKind = if ([OperatingSystem]::IsWindows()) { 'Junction' } else { 'SymbolicLink' }
New-Item -ItemType $linkKind -Path $linked -Target $target | Out-Null
$invalid.OutputDirectory = $linked
Assert-Refused { Update-CiVcpkgOverlayTriplet @invalid } 'Reparse path refused'
$invalid.SourceTripletPath = $created.Path
$invalid.OutputDirectory = [IO.Path]::GetDirectoryName($created.Path)
Assert-Refused { Update-CiVcpkgOverlayTriplet @invalid } 'cannot overwrite its source'
Write-Host "PASS incomplete, external, reparse and source-overwriting outputs are refused. Evidence at $fixture"

Import-Module (Join-Path $engine 'Tools/Modules/Ci.VcpkgInstall.psm1')
[void](Write-FixtureFile 'product/vcpkg.json' '{"name":"fixture","version":"0.1.0"}')
[void](Write-FixtureFile 'product/.build/alternate/vcpkg.json' '{"name":"fixture","version":"0.1.1"}')
$product = Join-Path $fixture 'product'
$arguments = @{
    ProjectRoot = $product
    Triplet = 'arm64-windows-static-md-asan'
    InstallRoot = (Join-Path $product '.build/installed/arm64 asan')
    BuildTreesRoot = (Join-Path $product '.build/buildtrees/arm64 asan')
    PackagesRoot = (Join-Path $product '.build/packages/arm64 asan')
    DownloadsRoot = (Join-Path $product '.build/downloads')
    OverlayTriplets = (Join-Path $product '.build/triplets')
}
[void][IO.Directory]::CreateDirectory($arguments.OverlayTriplets)
$expected = @(
    'install',
    '--triplet=arm64-windows-static-md-asan',
    "--x-manifest-root=$product",
    "--x-install-root=$($arguments.InstallRoot)",
    "--x-buildtrees-root=$($arguments.BuildTreesRoot)",
    "--x-packages-root=$($arguments.PackagesRoot)",
    "--downloads-root=$($arguments.DownloadsRoot)",
    "--overlay-triplets=$($arguments.OverlayTriplets)"
)
$actual = @(Get-CiVcpkgManifestInstallArguments @arguments)
Assert-Equal ($expected -join [char]0) ($actual -join [char]0)
Assert-Equal $false ([IO.Directory]::Exists($arguments.InstallRoot))
$registry = Join-Path $product '.build/registry'
[void][IO.Directory]::CreateDirectory($registry)
$alternate = Join-Path $product '.build/alternate'
$actual = @(Get-CiVcpkgManifestInstallArguments @arguments -RegistryRoot $registry -ManifestRoot $alternate -DisableBinaryCache)
Assert-Equal "--vcpkg-root=$registry" $actual[1]
Assert-Equal "--x-manifest-root=$alternate" $actual[3]
Assert-Equal '--binarysource=clear' $actual[-1]
Assert-Equal 10 $actual.Count
Write-Host 'PASS ordinary and independent-registry vcpkg arguments preserve exact owned paths and cache option'

$defaultStorage = @{
    ProjectRoot = $product
    Triplet = 'x64-windows'
    InstallRoot = $arguments.InstallRoot
    OverlayTriplets = $arguments.OverlayTriplets
    UseDefaultStorage = $true
}
$expected = @('install', '--triplet=x64-windows', "--x-manifest-root=$product",
    "--x-install-root=$($arguments.InstallRoot)", "--overlay-triplets=$($arguments.OverlayTriplets)")
$actual = @(Get-CiVcpkgManifestInstallArguments @defaultStorage)
Assert-Equal ($expected -join [char]0) ($actual -join [char]0)
$portOverlay = Join-Path $product 'Build/fixture ports'
[void][IO.Directory]::CreateDirectory($portOverlay)
$defaultStorage.Triplet = 'arm64-fixture_custom'
$expected[1] = '--triplet=arm64-fixture_custom'
$actual = @(Get-CiVcpkgManifestInstallArguments @defaultStorage -OverlayPorts $portOverlay)
Assert-Equal (($expected + "--overlay-ports=$portOverlay") -join [char]0) ($actual -join [char]0)
Assert-Equal $false ([IO.Directory]::Exists($arguments.InstallRoot))
Assert-Refused { Get-CiVcpkgManifestInstallArguments @defaultStorage -OverlayPorts (Join-Path $product 'missing') } 'port overlay directory is missing'
Assert-Refused { Get-CiVcpkgManifestInstallArguments @defaultStorage -OverlayPorts $fixture } 'contained repository'
$linkedPortOverlay = Join-Path $product 'Build/linked ports'
New-Item -ItemType $linkKind -Path $linkedPortOverlay -Target $portOverlay | Out-Null
Assert-Refused { Get-CiVcpkgManifestInstallArguments @defaultStorage -OverlayPorts $linkedPortOverlay } 'Reparse path refused'
$defaultStorage.Triplet = '../arm64-fixture'
Assert-Refused { Get-CiVcpkgManifestInstallArguments @defaultStorage } 'single file name'
$invalidName = $arguments.Clone()
$invalidName.Triplet = 'arm64-fixture_custom'
Assert-Refused { Get-CiVcpkgManifestInstallArguments @invalidName } 'Invalid triplet name'
Write-Host 'PASS vcpkg default storage and target port overlays preserve custom triplets, storage and path policy'

$invalid = $arguments.Clone()
$invalid.InstallRoot = Join-Path $fixture 'foreign'
Assert-Refused { Get-CiVcpkgManifestInstallArguments @invalid } 'contained repository'
$invalid = $arguments.Clone()
$invalid.OverlayTriplets = Join-Path $product '.build/missing'
Assert-Refused { Get-CiVcpkgManifestInstallArguments @invalid } 'overlay directory is missing'
Assert-Refused { Get-CiVcpkgManifestInstallArguments @arguments -ManifestRoot (Join-Path $product 'missing') } 'manifest is missing'
Assert-Refused { Get-CiVcpkgManifestInstallArguments @arguments -RegistryRoot (Join-Path $product '.build/absent-registry') } 'registry is missing'
$badOverlay = Join-Path $product '.build/linked'
New-Item -ItemType $linkKind -Path $badOverlay -Target $arguments.OverlayTriplets | Out-Null
$invalid.OverlayTriplets = $badOverlay
Assert-Refused { Get-CiVcpkgManifestInstallArguments @invalid } 'Reparse path refused'
Write-Host "PASS vcpkg manifest, registry, overlay and output ownership refusals. Evidence at $fixture"

Import-Module (Join-Path $engine 'Tools/Modules/Ci.VcpkgCheckout.psm1')
$sourceDir = Join-Path $fixture 'source repository'
[void](Write-FixtureFile 'source repository/versions/baseline.json' '{"baseline":1}')
[void](Write-FixtureFile 'source repository/.gitattributes' '* -text')
$null = Invoke-CiGit $sourceDir @('init', '--initial-branch=main')
foreach ($setting in @(@('user.name','Toolchain Fixture'), @('user.email','toolchain-fixture@example.invalid'),
                       @('commit.gpgsign','false'), @('core.longpaths','true'), @('uploadpack.allowFilter','true'))) {
    $null = Invoke-CiGit $sourceDir @('config', $setting[0], $setting[1])
}
$null = Invoke-CiGit $sourceDir @('add', '--', '.gitattributes', 'versions')
$null = Invoke-CiGit $sourceDir @('commit', '-m', 'Declare the original baseline')
$firstCommit = Resolve-CiCommit $sourceDir HEAD
[void](Write-FixtureFile 'source repository/versions/baseline.json' '{"baseline":2}')
$null = Invoke-CiGit $sourceDir @('commit', '-am', 'Declare the next baseline')
$secondCommit = Resolve-CiCommit $sourceDir HEAD
$repository = [uri]::new($sourceDir).AbsoluteUri
$checkoutRoot = Join-Path $product '.build/checkout'
$pin = @{ ProjectRoot=$product; Path=$checkoutRoot; Repository=$repository; Commit=$firstCommit }

Initialize-CiVcpkgCheckout @pin
Assert-Equal $firstCommit (Resolve-CiCommit $checkoutRoot HEAD)
Assert-Equal '{"baseline":1}' ([IO.File]::ReadAllText((Join-Path $checkoutRoot 'versions/baseline.json')))
Initialize-CiVcpkgCheckout @pin
Assert-Equal $firstCommit (Resolve-CiCommit $checkoutRoot HEAD)
$pin.Commit = $secondCommit
Initialize-CiVcpkgCheckout @pin
Assert-Equal $secondCommit (Resolve-CiCommit $checkoutRoot HEAD)
Assert-Equal $secondCommit (Resolve-CiCommit $sourceDir HEAD)
Write-Host 'PASS complete pinned checkout reuse and move to a different reviewed commit'

$dirtyPath = Join-Path $checkoutRoot 'versions/baseline.json'
[IO.File]::WriteAllText($dirtyPath, 'retain this edit')
Assert-Refused { Initialize-CiVcpkgCheckout @pin } 'contains local changes'
Assert-Equal 'retain this edit' ([IO.File]::ReadAllText($dirtyPath))
$wrongRepository = $pin.Clone()
$wrongRepository.Repository = 'file:///wrong-pinned-origin'
Assert-Refused { Initialize-CiVcpkgCheckout @wrongRepository } 'origin differs'
$badPath = $pin.Clone()
$badPath.Path = Join-Path $fixture 'external-checkout'
Assert-Refused { Initialize-CiVcpkgCheckout @badPath } 'contained repository'
Assert-Equal $false ([IO.Directory]::Exists($badPath.Path))
$badPath.Path = Join-Path $product '.build/unowned'
[void][IO.Directory]::CreateDirectory($badPath.Path)
Assert-Refused { Initialize-CiVcpkgCheckout @badPath } 'not an owned clone'
$badPath.Path = Join-Path $product '.build/linked-checkout'
New-Item -ItemType $linkKind -Path $badPath.Path -Target $sourceDir | Out-Null
Assert-Refused { Initialize-CiVcpkgCheckout @badPath } 'Reparse path refused'
Write-Host 'PASS dirty, foreign, out-of-scope and reparse checkouts retain their files'

$older = Join-Path $product '.build/partial'
$null = Invoke-CiGit $product @('clone','--depth=1','--filter=blob:none','--',$repository,$older)
Assert-Equal 'true' ((Invoke-CiGit $older @('rev-parse','--is-shallow-repository')).stdout.Trim())
Assert-Equal 'blob:none' ((Invoke-CiGit $older @('config','--get','remote.origin.partialclonefilter')).stdout.Trim())
$recovery = $pin.Clone()
$recovery.Path = $older
$recovery.Commit = $firstCommit
Initialize-CiVcpkgCheckout @recovery
Assert-Equal 'false' ((Invoke-CiGit $older @('rev-parse','--is-shallow-repository')).stdout.Trim())
Assert-Equal 1 (Invoke-CiGit $older @('config','--get','remote.origin.partialclonefilter') -AllowFailure).exitCode
Assert-Equal $firstCommit (Resolve-CiCommit $older HEAD)
Assert-Equal '{"baseline":1}' ((Invoke-CiGit $older @('cat-file','blob','HEAD:versions/baseline.json')).stdout.Trim())
Write-Host "PASS partial checkout completion restores pinned offline port metadata. Evidence at $fixture"

$missing = $pin.Clone()
$missing.Path = Join-Path $product '.build/missing-pin'
$missing.Commit = 'a' * 40
$stagedBefore = @(Get-ChildItem -LiteralPath (Join-Path $product '.build') -Directory -Filter '~v*').Count
Assert-Refused { Initialize-CiVcpkgCheckout @missing } 'failed (128)'
Assert-Equal $false ([IO.Directory]::Exists($missing.Path))
$stagedAfter = @(Get-ChildItem -LiteralPath (Join-Path $product '.build') -Directory -Filter '~v*').Count
Assert-Equal ($stagedBefore + 1) $stagedAfter
Write-Host 'PASS unavailable pin retains the staged attempt and leaves the destination unpublished'

$deep = $pin.Clone()
$deepParent = Join-Path $product '.build/nested'
while ($deepParent.Length -lt 195) {
    $deepParent = Join-Path $deepParent 'ports-catalogue-directory'
}
$deep.Path = Join-Path $deepParent 'vcpkg-tool'
Initialize-CiVcpkgCheckout @deep
Initialize-CiVcpkgCheckout @deep
$deepCommit = (Invoke-CiGit $product @('-c', 'core.longpaths=true', '-C', $deep.Path, 'rev-parse', 'HEAD')).stdout.Trim()
Assert-Equal $secondCommit $deepCommit
Assert-Equal '{"baseline":2}' ([IO.File]::ReadAllText((Join-Path $deep.Path 'versions/baseline.json')))
Write-Host 'PASS deep destination materializes through the short managed staging path'

if ([OperatingSystem]::IsWindows()) {
    $fixtureBootstrap = @'
@echo off
if not "%1"=="-disableMetrics" exit /b 19
if "%RedHome_CV507_Bootstrap_Fixture%"=="fail" (
    > "%~dp0vcpkg.exe" echo partial
    exit /b 17
)
> "%~dp0vcpkg.exe" echo initialized
exit /b 0
'@
    [void](Write-FixtureFile 'source repository/bootstrap-vcpkg.bat' $fixtureBootstrap)
    [void](Write-FixtureFile 'source repository/.gitignore' 'vcpkg.exe')
    $null = Invoke-CiGit $sourceDir @('add', '--', 'bootstrap-vcpkg.bat', '.gitignore')
    $null = Invoke-CiGit $sourceDir @('commit', '-m', 'Add a recording Windows bootstrap')
    $bootstrapCommit = Resolve-CiCommit $sourceDir HEAD
    $tool = Join-Path $product '.build/bootstrap'
    Initialize-CiVcpkgCheckout -ProjectRoot $product -Path $tool -Repository $repository -Commit $bootstrapCommit
    $bootstrapArgs = @{
        ProjectRoot = $product
        ToolRoot = $tool
        StampPath = (Join-Path $product '.build/bootstrap.commit')
        Commit = $bootstrapCommit
    }

    $previous = [Environment]::GetEnvironmentVariable('RedHome_CV507_Bootstrap_Fixture', 'Process')
    try {
        $env:RedHome_CV507_Bootstrap_Fixture = 'success'
        $executable = Initialize-CiVcpkgExecutable @bootstrapArgs
        Assert-Equal (Join-Path $tool 'vcpkg.exe') $executable
        Assert-Equal $bootstrapCommit ([IO.File]::ReadAllText($bootstrapArgs.StampPath).Trim())
        Assert-Equal 'initialized' ([IO.File]::ReadAllText($executable).Trim())
        $env:RedHome_CV507_Bootstrap_Fixture = 'fail'
        Assert-Equal $executable (Initialize-CiVcpkgExecutable @bootstrapArgs)
        Assert-Equal 'initialized' ([IO.File]::ReadAllText($executable).Trim())
        [IO.File]::Delete($executable)
        Assert-Refused { Initialize-CiVcpkgExecutable @bootstrapArgs } 'exit code 17'
        Assert-Equal 'partial' ([IO.File]::ReadAllText($executable).Trim())
        Assert-Equal $false ([IO.File]::Exists($bootstrapArgs.StampPath))
        $env:RedHome_CV507_Bootstrap_Fixture = 'success'
        Assert-Equal $executable (Initialize-CiVcpkgExecutable @bootstrapArgs)
        Assert-Equal $bootstrapCommit ([IO.File]::ReadAllText($bootstrapArgs.StampPath).Trim())
        Assert-Equal 'initialized' ([IO.File]::ReadAllText($executable).Trim())
    } finally {
        [Environment]::SetEnvironmentVariable('RedHome_CV507_Bootstrap_Fixture', $previous, 'Process')
    }
    $wrong = $bootstrapArgs.Clone()
    $wrong.Commit = $firstCommit
    Assert-Refused { Initialize-CiVcpkgExecutable @wrong } 'checkout does not match'
    $wrong = $bootstrapArgs.Clone()
    $wrong.StampPath = $executable
    Assert-Refused { Initialize-CiVcpkgExecutable @wrong } 'separate path'
    Assert-Equal 'initialized' ([IO.File]::ReadAllText($executable).Trim())
    Write-Host 'PASS bootstrap marker reuse, failure refusal, retry and exact source binding'
}
