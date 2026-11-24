Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function Find-CiVisualStudioInstallation {
    [CmdletBinding()]
    param([string] $VersionRange)

    $vswhere = @(
        foreach ($folder in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
            if ($folder) { Join-Path $folder 'Microsoft Visual Studio/Installer/vswhere.exe' }
        }
    ) | Where-Object { [IO.File]::Exists($_) } | Select-Object -First 1
    if (-not $vswhere) { throw 'Visual Studio Installer/vswhere.exe was not found.' }

    $arguments = @('-latest', '-prerelease', '-products', '*', '-requires', 'Microsoft.Component.MSBuild')
    if ($VersionRange) { $arguments += @('-version', $VersionRange) }
    $arguments += @('-utf8', '-property', 'installationPath')
    $result = Invoke-CiProcess -FilePath $vswhere -Arguments $arguments -WorkingDirectory (Split-Path -Parent $vswhere)
    $installation = $result.stdout.Trim()
    if (-not [IO.Directory]::Exists($installation)) {
        throw 'Visual Studio with MSBuild was not found. Install the required Desktop development with C++ workload.'
    }
    return $installation
}

function Get-CiVisualStudioInstallationOfMSBuild {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $MSBuildPath)

    $path = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($MSBuildPath)
    if (-not [IO.File]::Exists($path)) { throw "MSBuild was not found at '$path'." }
    $directory = [IO.Path]::GetDirectoryName($path)
    while ($directory) {
        if ([IO.Directory]::Exists((Join-Path $directory 'VC/Auxiliary/Build'))) { return $directory }
        $directory = [IO.Path]::GetDirectoryName($directory)
    }
    throw "The MSBuild at '$path' is not inside a Visual Studio installation with the MSVC build tools (there is no VC\Auxiliary\Build above it). Install the Desktop development with C++ workload, or put a Visual Studio MSBuild on the build's path."
}

function Get-CiNativeMSBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Installation,
        [Runtime.InteropServices.Architecture] $Architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    )

    $hostFolder = switch ($Architecture) {
        X64 { 'amd64' }
        Arm64 { 'arm64' }
        default { throw 'Native MSBuild requires an x64 or ARM64 host.' }
    }
    $path = $PSCmdlet.GetUnresolvedProviderPathFromPSPath((Join-Path $Installation "MSBuild/Current/Bin/$hostFolder/MSBuild.exe"))
    if (-not [IO.File]::Exists($path)) { throw "Native MSBuild is missing: $path" }
    return $path
}

function Get-CiDefaultMsvcToolset {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Installation)

    $path = $PSCmdlet.GetUnresolvedProviderPathFromPSPath((Join-Path $Installation 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'))
    $cause = "Cannot pin vcpkg to the default MSVC toolset of the Visual Studio installation at '$Installation'"
    if (-not [IO.File]::Exists($path)) {
        throw "${cause}: '$path' does not exist. Install the Desktop development with C++ workload (MSVC build tools) in the Visual Studio Installer, or repair the installation, and try again."
    }
    $version = [IO.File]::ReadAllText($path).Trim()
    $match = [regex]::Match($version, '^(?<majorMinor>[0-9]+\.[0-9]+)\.[0-9]+\z')
    if (-not $match.Success) {
        $shown = $version -replace '\s+', ' '
        if ($shown.Length -gt 60) { $shown = $shown.Substring(0, 60) + '...' }
        $holds = if ($shown) { "holds '$shown'" } else { 'is empty' }
        throw "${cause}: '$path' $holds, not a toolset version such as 14.51.36231. Repair the installation in the Visual Studio Installer so the file names the default toolset, and try again."
    }
    return [pscustomobject]@{ Installation = $Installation; VersionFile = $path; Version = $version; MajorMinor = $match.Groups['majorMinor'].Value }
}

Export-ModuleMember -Function Find-CiVisualStudioInstallation, Get-CiVisualStudioInstallationOfMSBuild,
    Get-CiNativeMSBuild, Get-CiDefaultMsvcToolset
