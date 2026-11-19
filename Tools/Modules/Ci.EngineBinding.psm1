Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function Get-CiEngineBindingMessage([string]$Command, [string]$Pin, [string]$Problem) {
    # One message for every way a product shim can meet the wrong engine. The fix is always the same two commands.
    $commit = if ($Pin) { $Pin } else { '<engine.ref from .ci/project.json>' }
    return "$Command runs the shared CI engine that .ci/project.json pins ($commit) from .ci-engine, and $Problem. " +
        "Check out that commit: git -C .ci-engine fetch origin $commit; git -C .ci-engine checkout --detach $commit " +
        '(first time: git clone https://github.com/RedSalamanders/.github.git .ci-engine).'
}

function Get-CiPinnedEngineRoot([string]$ProjectRoot, [string]$Name) {
    # This module's engine, after proving it is the project's own independent .ci-engine checkout at the exact pin with no
    # tracked changes: the rule the project adapter applies. Read-only: the status check never rewrites the index.
    $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $project = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd($separators)
    $engine = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd($separators)
    $comparison = if ([OperatingSystem]::IsWindows()) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $pin = ''
    try { $pin = [string](Read-CiProject $project).engine.ref }
    catch { throw (Get-CiEngineBindingMessage $Name '' "its manifest cannot be read ($($_.Exception.Message))") }
    $expected = [IO.Path]::GetFullPath((Join-Path $project '.ci-engine')).TrimEnd($separators)
    if (-not $engine.Equals($expected, $comparison)) { throw (Get-CiEngineBindingMessage $Name $pin "the engine that answered is $engine instead") }
    $top = Invoke-CiGit $engine @('rev-parse', '--show-toplevel') -AllowFailure
    if ($top.exitCode -ne 0 -or -not [IO.Path]::GetFullPath($top.stdout.Trim()).TrimEnd($separators).Equals($engine, $comparison)) {
        throw (Get-CiEngineBindingMessage $Name $pin '.ci-engine is not a Git checkout of its own')
    }
    $head = (Invoke-CiGit $engine @('rev-parse', 'HEAD')).stdout.Trim()
    if ($head -cne $pin) { throw (Get-CiEngineBindingMessage $Name $pin "it is at $head") }
    # --no-optional-locks: the check never refreshes or rewrites the engine's index, so a caller that snapshots its
    # checkout (or a read-only one) sees no change.
    if ((Invoke-CiGit $engine @('--no-optional-locks', '-c', 'core.fsmonitor=false', 'status', '--porcelain', '--untracked-files=no')).stdout.Trim()) {
        throw (Get-CiEngineBindingMessage $Name $pin 'it has changes to tracked files')
    }
    return [pscustomobject]@{ Root = $engine; Pin = $pin }
}

function Resolve-CiPinnedEngineCommand {
    <#
    .SYNOPSIS
        Returns the pinned engine's implementation of a product command shim.
    .DESCRIPTION
        A product keeps a thin shim with its command's name and parameters that imports this module from its own
        .ci-engine and runs the path returned here. Refuses, with one message naming the pin and the fix, unless this
        module is the project's own independent .ci-engine Git checkout at the exact commit .ci/project.json pins, with
        no tracked changes: the same rule the project adapter applies. No network, writes or compiler.
    .PARAMETER ProjectRoot
        Product checkout that holds .ci/project.json and the shim.
    .PARAMETER Name
        File name of the shim, which is also the engine command's name under Tools/.
    .OUTPUTS
        Full path of the engine command.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][ValidatePattern('^[A-Z][A-Za-z]*-[A-Za-z]+\.ps1$')][string]$Name)
    $bound = Get-CiPinnedEngineRoot $ProjectRoot $Name
    $command = Join-Path $bound.Root "Tools/$Name"
    if (-not [IO.File]::Exists($command)) { throw (Get-CiEngineBindingMessage $Name $bound.Pin "that engine commit has no Tools/$Name") }
    return $command
}

function Resolve-CiPinnedEngineModule {
    <#
    .SYNOPSIS
        Returns the pinned engine's implementation of a product module shim.
    .DESCRIPTION
        A product module shim (for example Build/BuildConsole.psm1) imports this module from its own .ci-engine, imports
        the path returned here into its own scope and re-exports its functions. The engine module is
        Tools/Modules/Ci.<shim file name>. Refuses exactly as Resolve-CiPinnedEngineCommand does. No network, writes or
        compiler.
    .PARAMETER ProjectRoot
        Product checkout that holds .ci/project.json and the shim.
    .PARAMETER Name
        File name of the module shim, such as BuildConsole.psm1.
    .OUTPUTS
        Full path of the engine module.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][ValidatePattern('^[A-Z][A-Za-z]*\.psm1$')][string]$Name)
    $bound = Get-CiPinnedEngineRoot $ProjectRoot $Name
    $module = Join-Path $bound.Root "Tools/Modules/Ci.$Name"
    if (-not [IO.File]::Exists($module)) { throw (Get-CiEngineBindingMessage $Name $bound.Pin "that engine commit has no Tools/Modules/Ci.$Name") }
    return $module
}

Export-ModuleMember -Function Resolve-CiPinnedEngineCommand, Resolve-CiPinnedEngineModule
