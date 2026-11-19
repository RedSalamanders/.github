# Shared build-console contract, version 1 (Specs/ProjectCommands.md): zero-warning gate that also refuses a structured
# native tool exception dump, safe terminal links, one result format. Products import it through Build/BuildConsole.psm1.
Set-StrictMode -Version Latest

function Get-NativeBuildDiagnostics {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath)
    $full=[IO.Path]::GetFullPath($LogPath)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "Build diagnostics log is missing: $full"}
    $warnings=0;$errors=0;$toolExceptions=0
    foreach($line in [IO.File]::ReadLines($full)){
        # A child tool can fail while MSBuild still reports a successful footer.
        $exception=[regex]::Match($line,'^\s*(?:\d+>)?\s*ExceptionCode\s*=\s*(?:0x)?(?<code>[a-f0-9]{8})\s*$',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if($exception.Success -and $exception.Groups['code'].Value -cne '00000000'){++$toolExceptions}
        # Same canonical MSBuild header grammar as RedSalamander's MSBuildInvocation.
        # Diagnostic-looking text in a message is not a second diagnostic.
        $match=[regex]::Match($line,'^\s*(?:\d+>)?\s*(?:(?:[a-z]:)?[^:\r\n]*:\s*)??(?:[^:\r\n]*?\s+)??(?<kind>warning|error)(?:\s+[^:\s]+)?\s*:',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if($match.Success){
            if($match.Groups['kind'].Value -ieq 'warning'){++$warnings}else{++$errors}
        }
    }
    return [pscustomobject]@{LogPath=$full;WarningCount=$warnings;ErrorCount=$errors;ToolExceptionCount=$toolExceptions}
}

function Assert-NativeBuildDiagnostics {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath)
    $result=Get-NativeBuildDiagnostics -LogPath $LogPath
    if($result.ToolExceptionCount -ne 0){
        throw "Zero-warning build validation failed: $($result.ToolExceptionCount) tool process exception dump(s), despite any successful MSBuild footer. Log: $($result.LogPath)"
    }
    if($result.WarningCount -ne 0 -or $result.ErrorCount -ne 0){
        throw "Zero-warning build validation failed: $($result.WarningCount) warning(s), $($result.ErrorCount) error(s). Log: $($result.LogPath)"
    }
}

function ConvertTo-NativeBuildLink {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath,
          [ValidateSet('Auto','Always','Never')][string]$HyperlinkMode='Auto')
    if($LiteralPath -match '[\x00-\x1f\x7f]'){throw 'Build artifact paths cannot contain terminal control characters.'}
    $full=[IO.Path]::GetFullPath($LiteralPath)
    $enabled=$HyperlinkMode -eq 'Always' -or
        ($HyperlinkMode -eq 'Auto' -and $Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected)
    if(-not $enabled -or $full -notmatch '^[a-zA-Z]:[\\/]'){return $full}
    $uri=([Uri]::new($full)).AbsoluteUri
    # OSC 8 local file links need a local hostname in Windows Terminal.
    $uri=$uri.Replace('file:///','file://localhost/')
    $escape=[string][char]27
    return $escape+']8;;'+$uri+$escape+'\'+$full+$escape+']8;;'+$escape+'\'
}

function Write-NativeBuildResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Project,
          [Parameter(Mandatory)][string]$Platform,
          [Parameter(Mandatory)][string]$Configuration,
          [Parameter(Mandatory)][string]$LogPath,
          [string[]]$Artifacts=@(),
          [string]$Executable='',
          [TimeSpan]$Duration=[TimeSpan]::Zero,
          [ValidateSet('Auto','Always','Never')][string]$HyperlinkMode='Auto',
          [ValidateSet('Auto','Always','Never')][string]$ColorMode='Auto')
    # Validate everything before publishing a green result or launch affordance.
    Assert-NativeBuildDiagnostics -LogPath $LogPath
    foreach($path in @($Artifacts)+@($Executable)|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}){
        if(-not(Test-Path -LiteralPath $path)){throw "Successful build artifact is missing: $path"}
    }
    $color=$ColorMode -eq 'Always' -or
        ($ColorMode -eq 'Auto' -and $null -eq [Environment]::GetEnvironmentVariable('NO_COLOR','Process'))
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add("BUILD SUCCEEDED: $Project | $Platform | $Configuration | $($Duration.ToString('hh\:mm\:ss'))")
    $lines.Add('Diagnostics: 0 warning(s), 0 error(s)')
    foreach($artifact in $Artifacts){$lines.Add('Artifact: '+(ConvertTo-NativeBuildLink -LiteralPath $artifact -HyperlinkMode $HyperlinkMode))}
    $lines.Add('Log: '+(ConvertTo-NativeBuildLink -LiteralPath $LogPath -HyperlinkMode $HyperlinkMode))
    if(-not[string]::IsNullOrWhiteSpace($Executable)){
        $native=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        if($Platform -eq 'ARM64' -and $native -ne 'Arm64'){
            $lines.Add('Run on ARM64 Windows: '+[IO.Path]::GetFullPath($Executable))
        }else{
            $lines.Add('Run: '+(ConvertTo-NativeBuildLink -LiteralPath $Executable -HyperlinkMode $HyperlinkMode))
            $lines.Add("& '"+([IO.Path]::GetFullPath($Executable).Replace("'","''"))+"'")
        }
    }
    foreach($line in $lines){
        if($color){Write-Host $line -ForegroundColor Green}else{Write-Host $line}
    }
}

Export-ModuleMember -Function Get-NativeBuildDiagnostics,Assert-NativeBuildDiagnostics,ConvertTo-NativeBuildLink,Write-NativeBuildResult
