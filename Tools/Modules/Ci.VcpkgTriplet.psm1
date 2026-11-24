Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function ConvertTo-CMakeQuotedArgument([string] $Value) {
    return '"' + [regex]::Replace($Value, '[\\"$]', '\$&') + '"'
}

function Get-CiVcpkgOverlayTripletText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $SourceText,
        [Parameter(Mandatory)][ValidatePattern('^[^\r\n]+$')][string] $Installation,
        [Parameter(Mandatory)][ValidatePattern('^[0-9]+\.[0-9]+$')][string] $ToolsetVersion,
        [Parameter(Mandatory)][ValidatePattern('^#[^\r\n]*$')][string] $Header
    )

    $newline = if ($SourceText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $text = $SourceText
    if ($text.Length -and -not $text.EndsWith("`n", [StringComparison]::Ordinal)) { $text += $newline }
    if ($text.Length) { $text += $newline }
    $pins = @(
        $Header,
        "set(VCPKG_VISUAL_STUDIO_PATH $(ConvertTo-CMakeQuotedArgument $Installation))",
        "set(VCPKG_PLATFORM_TOOLSET_VERSION $(ConvertTo-CMakeQuotedArgument $ToolsetVersion))"
    )
    return $text + (($pins -join $newline) + $newline)
}

function Write-CiTripletFileIfChanged([string] $Root, [string] $Path, [byte[]] $Bytes) {
    $path = Assert-CiContainedPath -Root $Root -Path $Path
    if ([IO.File]::Exists($path) -and
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -ceq [Convert]::ToBase64String($Bytes)) {
        return $false
    }

    $directory = [IO.Path]::GetDirectoryName($path)
    [void][IO.Directory]::CreateDirectory($directory)
    $stage = Assert-CiContainedPath -Root $Root -Path (Join-Path $directory ('.triplet-' + [guid]::NewGuid().ToString('N') + '.tmp'))
    $stream = [IO.File]::Open($stage, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
        $path = Assert-CiContainedPath -Root $Root -Path $path
        [IO.File]::Move($stage, $path, $true)
    } finally {
        if ([IO.File]::Exists($stage)) { [IO.File]::Delete((Assert-CiContainedPath -Root $Root -Path $stage)) }
    }
    return $true
}

function Update-CiVcpkgOverlayTriplet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectRoot,
        [Parameter(Mandatory)][string] $SourceTripletPath,
        [Parameter(Mandatory)] $Toolset,
        [Parameter(Mandatory)][string] $OutputDirectory,
        [Parameter(Mandatory)][string] $Header
    )

    $root = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($ProjectRoot)
    $source = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($SourceTripletPath)
    $output = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    if (-not [IO.File]::Exists($source)) { throw "The triplet to pin does not exist: $source." }
    $name = [IO.Path]::GetFileName($source)
    $path = Assert-CiContainedPath -Root (Join-Path $root '.build') -Path (Join-Path $output $name)
    $path = Assert-CiContainedPath -Root $root -Path $path
    $comparison = if ([OperatingSystem]::IsWindows()) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($path.Equals($source, $comparison)) { throw 'A generated overlay cannot overwrite its source triplet.' }
    $sourceText = [IO.File]::ReadAllText($source)
    $text = Get-CiVcpkgOverlayTripletText -SourceText $sourceText -Installation $Toolset.Installation -ToolsetVersion $Toolset.MajorMinor -Header $Header
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)

    # Resolve and read all named companions before publishing any output.
    $companions = [ordered]@{}
    $sourceDirectory = [IO.Path]::GetDirectoryName($source)
    foreach ($ref in [regex]::Matches($sourceText, '\$\{CMAKE_CURRENT_LIST_DIR\}/(?<name>[A-Za-z0-9_.-]+)')) {
        $companionName = $ref.Groups['name'].Value
        if ($companionName -ieq $name) { throw "The triplet cannot use itself as a companion: $source." }
        $companionSource = Assert-CiContainedPath -Root $sourceDirectory -Path (Join-Path $sourceDirectory $companionName)
        if (-not [IO.File]::Exists($companionSource)) {
            throw "The triplet $source names '$companionName' beside itself with CMAKE_CURRENT_LIST_DIR, but '$companionSource' does not exist."
        }
        $companionPath = Assert-CiContainedPath -Root $root -Path (Join-Path $output $companionName)
        $companions[$companionPath] = [IO.File]::ReadAllBytes($companionSource)
    }

    $changed = $false
    foreach ($companionPath in $companions.Keys) {
        if (Write-CiTripletFileIfChanged $root $companionPath $companions[$companionPath]) { $changed = $true }
    }
    if (Write-CiTripletFileIfChanged $root $path $bytes) { $changed = $true }
    return [pscustomobject]@{
        Triplet = [IO.Path]::GetFileNameWithoutExtension($name)
        Directory = $output
        Path = $path
        Changed = $changed
        Companions = @($companions.Keys)
    }
}

Export-ModuleMember -Function Get-CiVcpkgOverlayTripletText, Update-CiVcpkgOverlayTriplet
