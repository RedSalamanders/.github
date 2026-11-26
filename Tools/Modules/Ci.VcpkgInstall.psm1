Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function Get-CiVcpkgManifestInstallArguments {
    <#
    .SYNOPSIS
    Returns the argument vector for a vcpkg manifest install with product-owned output paths.
    .DESCRIPTION
    Reads only. Product callers retain their existing lease, bootstrap, environment and native invocation.
    .PARAMETER ProjectRoot
    Checkout that owns the manifest and generated .build tree.
    .PARAMETER ManifestRoot
    Optional alternate manifest directory inside the checkout. Defaults to ProjectRoot.
    .PARAMETER Triplet
    The selected product's target triplet.
    .PARAMETER InstallRoot
    Platform-specific installed package directory below the checkout's .build.
    .PARAMETER BuildTreesRoot
    Platform-specific build tree directory below .build.
    .PARAMETER PackagesRoot
    Platform-specific package staging directory below .build.
    .PARAMETER DownloadsRoot
    Managed downloads directory below .build.
    .PARAMETER UseDefaultStorage
    Keep the selected vcpkg tool's buildtrees, packages and downloads locations.
    .PARAMETER OverlayTriplets
    Generated triplet directory below .build.
    .PARAMETER OverlayPorts
    Optional project-owned port overlay directory.
    .PARAMETER RegistryRoot
    Optional independently pinned vcpkg registry directory below .build.
    .PARAMETER DisableBinaryCache
    Clear configured vcpkg binary sources for a product that needs an isolated restore.
    .OUTPUTS
    Arguments in invocation order. Each path is passed as one argument.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ExplicitStorage')]
    param(
        [Parameter(Mandatory)][string] $ProjectRoot,
        [Parameter(Mandatory)][string] $Triplet,
        [Parameter(Mandatory)][string] $InstallRoot,
        [Parameter(Mandatory, ParameterSetName = 'ExplicitStorage')][string] $BuildTreesRoot,
        [Parameter(Mandatory, ParameterSetName = 'ExplicitStorage')][string] $PackagesRoot,
        [Parameter(Mandatory, ParameterSetName = 'ExplicitStorage')][string] $DownloadsRoot,
        [Parameter(Mandatory)][string] $OverlayTriplets,
        [string] $ManifestRoot,
        [string] $RegistryRoot,
        [switch] $DisableBinaryCache,
        [Parameter(Mandatory, ParameterSetName = 'DefaultStorage')][switch] $UseDefaultStorage,
        [string] $OverlayPorts
    )

    if ($PSCmdlet.ParameterSetName -eq 'DefaultStorage') {
        if ([string]::IsNullOrWhiteSpace($Triplet) -or $Triplet -in @('.', '..') -or $Triplet -match '[<>:"/\\|?*\x00-\x1F]') {
            throw "Triplet must be a single file name: $Triplet"
        }
    } elseif ($Triplet -notmatch '^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$') {
        throw "Invalid triplet name: $Triplet"
    }

    $root = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($ProjectRoot)
    $buildRoot = Join-Path $root '.build'
    if (-not $ManifestRoot) { $ManifestRoot = $root }
    $manifestDirectory = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($ManifestRoot)
    $manifest = Assert-CiContainedPath -Root $root -Path (Join-Path $manifestDirectory 'vcpkg.json')
    if (-not [IO.File]::Exists($manifest)) { throw "vcpkg manifest is missing: $manifest" }

    $arguments = [Collections.Generic.List[string]]::new()
    $arguments.Add('install')
    if ($RegistryRoot) {
        $registry = Assert-CiContainedPath -Root $buildRoot -Path ($PSCmdlet.GetUnresolvedProviderPathFromPSPath($RegistryRoot))
        $registry = Assert-CiContainedPath -Root $root -Path $registry
        if (-not [IO.Directory]::Exists($registry)) { throw "Pinned vcpkg registry is missing: $registry" }
        $arguments.Add("--vcpkg-root=$registry")
    }
    $arguments.Add("--triplet=$Triplet")
    $arguments.Add("--x-manifest-root=$manifestDirectory")

    $outputPaths = [ordered]@{ '--x-install-root' = $InstallRoot }
    if ($PSCmdlet.ParameterSetName -eq 'ExplicitStorage') {
        $outputPaths.Add('--x-buildtrees-root', $BuildTreesRoot)
        $outputPaths.Add('--x-packages-root', $PackagesRoot)
        $outputPaths.Add('--downloads-root', $DownloadsRoot)
    }
    $outputPaths.Add('--overlay-triplets', $OverlayTriplets)
    foreach ($name in $outputPaths.Keys) {
        $path = Assert-CiContainedPath -Root $buildRoot -Path ($PSCmdlet.GetUnresolvedProviderPathFromPSPath($outputPaths[$name]))
        $path = Assert-CiContainedPath -Root $root -Path $path
        if ($name -eq '--overlay-triplets' -and -not [IO.Directory]::Exists($path)) {
            throw "Generated vcpkg overlay directory is missing: $path"
        }
        $arguments.Add("$name=$path")
    }
    if ($OverlayPorts) {
        $portOverlay = Assert-CiContainedPath -Root $root -Path ($PSCmdlet.GetUnresolvedProviderPathFromPSPath($OverlayPorts))
        if (-not [IO.Directory]::Exists($portOverlay)) { throw "vcpkg port overlay directory is missing: $portOverlay" }
        $arguments.Add("--overlay-ports=$portOverlay")
    }
    if ($DisableBinaryCache) { $arguments.Add('--binarysource=clear') }
    return $arguments.ToArray()
}

Export-ModuleMember -Function Get-CiVcpkgManifestInstallArguments
