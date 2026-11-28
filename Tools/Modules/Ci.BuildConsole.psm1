# Shared build-console contract, version 1 (Specs/ProjectCommands.md): zero-warning gate, completed MSBuild summary
# validation where declared, safe terminal links and one result format. Products use Build/BuildConsole.psm1.
Set-StrictMode -Version Latest

function Get-NativeBuildDiagnostics {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath, [switch]$IncludeBuildSummary)
    $full=[IO.Path]::GetFullPath($LogPath)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "Build diagnostics log is missing: $full"}
    $warnings=0;$errors=0;$toolExceptions=0
    $details=[Collections.Generic.List[string]]::new()
    $succeeded=$false;$warningSummary=$null;$errorSummary=$null;$summaryStage=0
    $fileLoggerNotice = "FileLogger wrote to: $full"
    $sawFileLoggerNotice = $false
    $options=[Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant
    if([Enum]::IsDefined([Text.RegularExpressions.RegexOptions], 'NonBacktracking')){
        $options=$options -bor [Enum]::Parse([Text.RegularExpressions.RegexOptions], 'NonBacktracking')
    }
    # Same canonical MSBuild header grammar as RedSalamander's MSBuildInvocation.
    # Diagnostic-looking text in a message is not a second diagnostic.
    $diagnostic=[regex]::new('^\s*(?:\d+>)?\s*(?:(?:[a-z]:)?[^:\r\n]*:\s*)??(?:[^:\r\n]*?\s+)??(?<kind>warning|error)(?:\s+[^:\s]+)?\s*:',
        $options, [TimeSpan]::FromMilliseconds(500))
    $toolException=[regex]::new('^\s*(?:\d+>)?\s*ExceptionCode\s*=\s*(?:0x)?(?<code>[a-f0-9]{8})\s*$',
        $options, [TimeSpan]::FromMilliseconds(500))
    foreach($line in [IO.File]::ReadLines($full)){
        # A child tool can fail while MSBuild still reports a successful footer.
        $exception=$toolException.Match($line)
        $hasException=$exception.Success -and $exception.Groups['code'].Value -cne '00000000'
        if($hasException){++$toolExceptions}
        $match=$diagnostic.Match($line)
        if($match.Success){
            if($match.Groups['kind'].Value -ieq 'warning'){++$warnings}else{++$errors}
        }
        if(!$IncludeBuildSummary){continue}
        if(($match.Success -or $hasException) -and $details.Count -lt 16){
            $details.Add($line.Substring(0,[Math]::Min(2048,$line.Length)))
        }
        if($line -match '^\s*Build succeeded\.\s*$'){
            $summaryStage=1;$succeeded=$false;$warningSummary=$null;$errorSummary=$null
            $sawFileLoggerNotice = $false
        }elseif($line -match '^\s*Build FAILED\.\s*$'){
            $summaryStage=0;$succeeded=$false;$warningSummary=$null;$errorSummary=$null
        }elseif($succeeded -and $line -notmatch '^\s*$'){
            $succeeded=$false;$warningSummary=$null;$errorSummary=$null
        }elseif($summaryStage -gt 0 -and $line -notmatch '^\s*$'){
            if($summaryStage -eq 1 -and $line -match '^\s*0+ Warning\(s\)\s*$'){
                $warningSummary=0;$summaryStage=2
            }elseif($summaryStage -eq 2 -and $line -match '^\s*0+ Error\(s\)\s*$'){
                $errorSummary=0;$summaryStage=3
            }elseif($summaryStage -eq 3 -and !$sawFileLoggerNotice -and $line.Trim() -ieq $fileLoggerNotice){
                $sawFileLoggerNotice = $true
            }elseif($summaryStage -eq 3 -and $line -match '^\s*Time Elapsed \d{2,}:\d{2}:\d{2}\.\d{2,7}\s*$'){
                $succeeded=$true;$summaryStage=0
            }else{
                $summaryStage=0;$succeeded=$false;$warningSummary=$null;$errorSummary=$null
            }
        }
    }
    $result=[ordered]@{LogPath=$full;WarningCount=$warnings;ErrorCount=$errors;ToolExceptionCount=$toolExceptions}
    if($IncludeBuildSummary){
        $result.BuildSucceeded=$succeeded
        $result.WarningSummary=$warningSummary
        $result.ErrorSummary=$errorSummary
        $result.DiagnosticDetails=$details.ToArray()
    }
    return [pscustomobject]$result
}

function Assert-NativeBuildDiagnostics {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath, [switch]$RequireBuildSummary)
    $result=Get-NativeBuildDiagnostics -LogPath $LogPath -IncludeBuildSummary:$RequireBuildSummary
    $details=if($RequireBuildSummary -and $result.DiagnosticDetails.Count){"`n"+($result.DiagnosticDetails -join "`n")}else{''}
    if($result.ToolExceptionCount -ne 0){
        throw "Zero-warning build validation failed: $($result.ToolExceptionCount) tool process exception dump(s), despite any successful MSBuild footer. Log: $($result.LogPath)$details"
    }
    if($result.WarningCount -ne 0 -or $result.ErrorCount -ne 0){
        throw "Zero-warning build validation failed: $($result.WarningCount) warning(s), $($result.ErrorCount) error(s). Log: $($result.LogPath)$details"
    }
    if($RequireBuildSummary -and (-not $result.BuildSucceeded -or $null -eq $result.WarningSummary -or $null -eq $result.ErrorSummary -or
       $result.WarningSummary -ne 0 -or $result.ErrorSummary -ne 0)){
        throw "Zero-warning build validation failed: a completed successful MSBuild log with explicit zero warning/error summaries is required. Log: $($result.LogPath)"
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
          [ValidateSet('Auto','Always','Never')][string]$ColorMode='Auto',
          [switch]$RequireBuildSummary)
    # Validate everything before publishing a green result or launch affordance.
    Assert-NativeBuildDiagnostics -LogPath $LogPath -RequireBuildSummary:$RequireBuildSummary
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
