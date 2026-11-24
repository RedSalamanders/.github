Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function Invoke-CiVcpkgGit([string] $Directory, [string[]] $Arguments, [switch] $AllowFailure) {
    $gitArguments = @('--no-optional-locks', '-c', 'core.longpaths=true', '-C', $Directory) + $Arguments
    # Git accepts deep directories through -C. Windows process startup needs a short working directory.
    $workingDirectory = [IO.Path]::GetPathRoot($Directory)
    return Invoke-CiProcess -FilePath 'git' -Arguments $gitArguments -WorkingDirectory $workingDirectory -TimeoutSeconds 3600 -AllowFailure:$AllowFailure
}

function Set-CiVcpkgCheckoutCommit([string] $Path, [string] $Repository, [string] $Commit, [bool] $Materialize) {
    $origin = (Invoke-CiVcpkgGit $Path @('remote', 'get-url', 'origin')).stdout.Trim()
    if ($origin.TrimEnd('/') -cne $Repository.TrimEnd('/')) {
        throw "Managed vcpkg origin differs from the declared repository: $Path"
    }
    if (-not $Materialize -and (Invoke-CiVcpkgGit $Path @('status', '--porcelain')).stdout.Trim()) {
        throw "Managed vcpkg checkout contains local changes: $Path"
    }

    $filter = Invoke-CiVcpkgGit $Path @('config', '--get', 'remote.origin.partialclonefilter') -AllowFailure
    $promisor = Invoke-CiVcpkgGit $Path @('config', '--get', 'remote.origin.promisor') -AllowFailure
    foreach ($result in @($filter, $promisor)) {
        if ($result.exitCode -notin @(0, 1)) { throw "Could not read managed vcpkg clone settings: $Path" }
    }
    if ((Invoke-CiVcpkgGit $Path @('rev-parse', '--is-shallow-repository')).stdout.Trim() -ceq 'true') {
        $null = Invoke-CiVcpkgGit $Path @('fetch', '--unshallow', 'origin')
    }
    if ($filter.exitCode -eq 0 -or $promisor.stdout.Trim() -ieq 'true') {
        $null = Invoke-CiVcpkgGit $Path @('fetch', '--refetch', '--no-filter', 'origin')
        if ($filter.exitCode -eq 0) { $null = Invoke-CiVcpkgGit $Path @('config', '--unset-all', 'remote.origin.partialclonefilter') }
        if ($promisor.exitCode -eq 0) { $null = Invoke-CiVcpkgGit $Path @('config', '--unset-all', 'remote.origin.promisor') }
    }

    $available = Invoke-CiVcpkgGit $Path @('cat-file', '-e', ($Commit + '^{commit}')) -AllowFailure
    if ($available.exitCode -ne 0) { $null = Invoke-CiVcpkgGit $Path @('fetch', 'origin', $Commit) }
    $head = (Invoke-CiVcpkgGit $Path @('rev-parse', 'HEAD')).stdout.Trim()
    if ($Materialize) {
        # This operation owns the new --no-checkout clone, including its empty worktree.
        $null = Invoke-CiVcpkgGit $Path @('checkout', '--force', '--detach', $Commit)
    } elseif ($head -cne $Commit) {
        $null = Invoke-CiVcpkgGit $Path @('checkout', '--no-overwrite-ignore', '--detach', $Commit)
    }
    if ((Invoke-CiVcpkgGit $Path @('rev-parse', 'HEAD')).stdout.Trim() -cne $Commit -or
        (Invoke-CiVcpkgGit $Path @('status', '--porcelain')).stdout.Trim()) {
        throw "Pinned vcpkg source verification failed: $Path"
    }
    $null = Invoke-CiVcpkgGit $Path @('config', 'core.longpaths', 'true')
}

function Initialize-CiVcpkgCheckout {
    <#
    .SYNOPSIS
    Restores an ordinary, clean vcpkg checkout at an exact immutable commit.
    .PARAMETER ProjectRoot
    Checkout owning the managed .build tree.
    .PARAMETER Path
    Managed Git checkout below the project's .build directory.
    .PARAMETER Repository
    Origin declared by the project's version-controlled vcpkg pin.
    .PARAMETER Commit
    Full nonzero vcpkg revision for the tool checkout or catalogue.
    .DESCRIPTION
    Reuses clean existing clones, completes recoverable older clones and fetches only
    missing sources. Fresh clones use a short staging path beneath the project build root and are published
    only after Git verifies the requested worktree. Leaves bootstrap and install leases
    to the product caller.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectRoot,
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidatePattern('\S')][string] $Repository,
        [Parameter(Mandatory)][ValidatePattern('^(?!0{40}\z)[a-fA-F0-9]{40}\z')][string] $Commit
    )

    $root = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($ProjectRoot)
    $buildRoot = Join-Path $root '.build'
    $path = Assert-CiContainedPath -Root $buildRoot -Path ($PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path))
    $path = Assert-CiContainedPath -Root $root -Path ($path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    $commit = $Commit.ToLowerInvariant()

    if (-not (Test-Path -LiteralPath $path)) {
        $parent = [IO.Path]::GetDirectoryName($path)
        # Git for Windows index-pack can reject a deep Git directory even with core.longpaths.
        $stageName = '~v' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $stage = Assert-CiContainedPath -Root $root -Path (Join-Path $buildRoot $stageName)
        [void][IO.Directory]::CreateDirectory($parent)
        if (Test-Path -LiteralPath $stage) { throw "Managed vcpkg staging path is occupied: $stage" }
        $null = Invoke-CiVcpkgGit $root @('clone', '--no-hardlinks', '--no-checkout', '--', $Repository, $stage)
        Set-CiVcpkgCheckoutCommit $stage $Repository $commit $true

        $stage = Assert-CiContainedPath -Root $buildRoot -Path $stage
        $stage = Assert-CiContainedPath -Root $root -Path $stage
        $path = Assert-CiContainedPath -Root $buildRoot -Path $path
        $path = Assert-CiContainedPath -Root $root -Path $path
        [IO.Directory]::Move($stage, $path)
        return
    }

    $gitDirectory = Assert-CiContainedPath -Root $root -Path (Join-Path $path '.git')
    if (-not [IO.Directory]::Exists($gitDirectory)) { throw "Managed vcpkg path is not an owned clone: $path" }
    $comparison = if ([OperatingSystem]::IsWindows()) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $top = [IO.Path]::GetFullPath((Invoke-CiVcpkgGit $path @('rev-parse', '--show-toplevel')).stdout.Trim())
    if (-not $top.Equals($path, $comparison)) { throw "Managed vcpkg path names another checkout: $path" }
    Set-CiVcpkgCheckoutCommit $path $Repository $commit $false
}

Export-ModuleMember -Function Initialize-CiVcpkgCheckout
