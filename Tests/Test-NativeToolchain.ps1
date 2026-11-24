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
