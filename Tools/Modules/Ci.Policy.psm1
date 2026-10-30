Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CiProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory, [int]$TimeoutSeconds = 120, [switch]$AllowFailure, [switch]$Stream)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.WorkingDirectory = [IO.Path]::GetFullPath($WorkingDirectory)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = -not $Stream
    $start.RedirectStandardError = -not $Stream
    if (-not $Stream) {
        $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    }
    foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::new()
    $child.StartInfo = $start
    try {
        if (-not $child.Start()) { throw "Could not start $FilePath." }
        if (-not $Stream) {
            $stdout = $child.StandardOutput.ReadToEndAsync()
            $stderr = $child.StandardError.ReadToEndAsync()
        }
        if (-not $child.WaitForExit($TimeoutSeconds * 1000)) {
            # This exact handle was created by this invocation; it owns the entire child tree.
            $child.Kill($true)
            $child.WaitForExit()
            throw "Owned $FilePath invocation timed out after $TimeoutSeconds seconds."
        }
        $result = [pscustomobject]@{ exitCode = $child.ExitCode;
            stdout = $(if ($Stream) { '' } else { $stdout.GetAwaiter().GetResult() });
            stderr = $(if ($Stream) { '' } else { $stderr.GetAwaiter().GetResult() }) }
        if ($result.exitCode -ne 0 -and -not $AllowFailure) {
            $diagnostic=($result.stderr+$result.stdout).Trim()
            foreach($secret in @($env:GH_TOKEN,$env:WINGET_TOKEN)){if($secret){$diagnostic=$diagnostic.Replace($secret,'<credential>')}}
            if($diagnostic.Length -gt 8000){$diagnostic=$diagnostic.Substring($diagnostic.Length-8000)}
            throw "$FilePath failed ($($result.exitCode)): $diagnostic"
        }
        return $result
    } finally { $child.Dispose() }
}

function Invoke-CiGit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    Invoke-CiProcess -FilePath 'git' -Arguments $Arguments -WorkingDirectory $Root -AllowFailure:$AllowFailure
}

function Get-CiSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Resolve-CiCommit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Ref)
    $value = (Invoke-CiGit $Root @('rev-parse', '--verify', '--end-of-options', ($Ref + '^{commit}'))).stdout.Trim()
    if ($value -notmatch '^[a-f0-9]{40,64}$') { throw 'Invalid immutable Git commit identity.' }
    return $value
}

function Read-CiProject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [string]$Path = '.ci/project.json', [string]$Ref = '')
    $manifestPath = [IO.Path]::GetFullPath((Join-Path $Root $Path))
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $manifestPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Project manifest must be inside its repository.' }
    $text = if ($Ref) { (Invoke-CiGit $Root @('show', ((Resolve-CiCommit $Root $Ref) + ':' + $Path))).stdout }
        else { [IO.File]::ReadAllText($manifestPath, [Text.UTF8Encoding]::new($false, $true)) }
    $schema = Join-Path $PSScriptRoot '../../Schemas/project.schema.json'
    if (-not (Test-Json -Json $text -SchemaFile $schema -ErrorAction Stop)) { throw 'Invalid project manifest.' }
    $project = $text | ConvertFrom-Json -AsHashtable
    if (($project.kind -eq 'sdk') -ne ($null -eq $project.winget)) { throw 'SDKs have no winget application; applications require a declared winget identity.' }
    $patterns = @($project.include) + @($project.exclude) + @($project.formatRoots)
    if ($project.Contains('formatExclude')) { $patterns += @($project.formatExclude) }
    foreach ($pattern in $patterns) {
        if ($pattern.Contains('\') -or $pattern.StartsWith('/') -or $pattern -match '(^|/)\.\.(/|$)' -or $pattern.Contains([char]0)) {
            throw "Invalid repository-relative input pattern: $pattern"
        }
    }
    return $project
}

function Test-CiGlob {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Pattern)
    $expression = [regex]::Escape($Pattern).Replace('\*\*/', '(?:.*/)?').Replace('\*\*', '.*').Replace('\*', '[^/]*').Replace('\?', '[^/]')
    [regex]::IsMatch($Path, '^' + $expression + '$', [Text.RegularExpressions.RegexOptions]::CultureInvariant -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Assert-CiContainedPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $target = [IO.Path]::GetFullPath($Path)
    $comparison = if ([OperatingSystem]::IsWindows()) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $target.StartsWith(($rootPath + [IO.Path]::DirectorySeparatorChar), $comparison)) { throw 'Output must be a contained repository/sandbox child.' }
    $cursor = $target
    while ($cursor -and $cursor.StartsWith($rootPath, $comparison)) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse path refused: $cursor" }
        }
        if ($cursor.Equals($rootPath, $comparison)) { break }
        $cursor = Split-Path -Parent $cursor
    }
    return $target
}

function Get-CiPathDisposition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][System.Collections.IDictionary]$Project)
    $pathValue = $Path.Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($pathValue) -or $pathValue.StartsWith('/') -or $pathValue -match '(^|/)\.\.(/|$)') { throw 'Invalid changed repository path.' }
    foreach ($pattern in $Project.include) {
        if (Test-CiGlob $pathValue $pattern) { return [pscustomobject]@{ path = $pathValue; native = $true; reason = "explicit-input:$pattern" } }
    }
    foreach ($pattern in $Project.exclude) {
        if (Test-CiGlob $pathValue $pattern) { return [pscustomobject]@{ path = $pathValue; native = $false; reason = "excluded:$pattern" } }
    }
    [pscustomobject]@{ path = $pathValue; native = $true; reason = 'unknown-conservative' }
}

function Get-CiChangedPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Base, [string]$Head = 'HEAD', [switch]$WorkingTree)
    $arguments = @('diff', '--no-ext-diff', '--no-textconv', '--name-status', '-z', '--find-renames', (Resolve-CiCommit $Root $Base))
    if (-not $WorkingTree) { $arguments += (Resolve-CiCommit $Root $Head) }
    $arguments += '--'
    $raw = (Invoke-CiGit $Root $arguments).stdout
    $fields = $raw.Split([char]0)
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $fields.Length - 1;) {
        $status = $fields[$index++]
        if ($status -notmatch '^[ACDMRTUXB][0-9]*$') { throw "Unreadable Git diff status: $status" }
        if ($index -ge $fields.Length - 1) { throw 'Truncated Git diff path.' }
        [void]$paths.Add($fields[$index++])
        if ($status -match '^[RC]') {
            if ($index -ge $fields.Length - 1) { throw 'Truncated Git rename/copy path.' }
            [void]$paths.Add($fields[$index++])
        }
    }
    $orderedPaths = [string[]]@($paths)
    [Array]::Sort($orderedPaths, [StringComparer]::Ordinal)
    return ,$orderedPaths
}

function Get-CiChangeDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Base, [string]$Head = 'HEAD')
    $project = Read-CiProject $Root -Ref $Head
    $rows = @(foreach ($path in (Get-CiChangedPaths $Root $Base $Head)) { Get-CiPathDisposition $path $project })
    [ordered]@{ schemaVersion = 1; repository = $project.repository; base = $Base; head = $Head;
        meaningful = @($rows | Where-Object native).Count -gt 0; paths = $rows }
}

function New-CiInputDescriptor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [string]$Ref = 'HEAD')
    $commit = Resolve-CiCommit $Root $Ref
    $project = Read-CiProject $Root -Ref $commit
    $raw = (Invoke-CiGit $Root @('ls-tree', '-r', '-z', '--full-tree', $commit)).stdout
    $inputs = [Collections.Generic.List[object]]::new()
    foreach ($entry in $raw.Split([char]0)) {
        if (-not $entry) { continue }
        if ($entry -notmatch '^(?<mode>[0-9]{6}) (?<type>blob|commit) (?<object>[a-f0-9]{40,64})\t(?<path>[\s\S]+)$') { throw 'Unreadable Git tree entry.' }
        $mode = $Matches.mode; $objectId = $Matches.object; $path = $Matches.path
        if ((Get-CiPathDisposition $path $project).native) {
            $inputs.Add([ordered]@{ path = $path; mode = $mode; object = $objectId })
        }
    }
    $buildNumberText = (Invoke-CiGit $Root @('rev-list', '--count', $commit)).stdout.Trim()
    if ($buildNumberText -notmatch '^\d+$' -or [long]$buildNumberText -gt 65535) { throw 'Build number is outside the native version range.' }
    $identity = [ordered]@{ policyVersion = $project.policyVersion; repository = $project.repository; engine = $project.engine; inputs = $inputs.ToArray() }
    [ordered]@{ schemaVersion = 1; repository = $project.repository; commit = $commit; engine = $project.engine;
        policyVersion = $project.policyVersion; nativeDigest = (Get-CiSha256 ($identity | ConvertTo-Json -Depth 12 -Compress));
        buildNumber = [int]$buildNumberText; version = "$($project.versionBase).$buildNumberText"; inputCount = $inputs.Count }
}

function Get-CiQuietDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ObservedHead, [Parameter(Mandatory)][DateTimeOffset]$ObservedAt,
        [Parameter(Mandatory)][string]$CurrentHead, [Parameter(Mandatory)][DateTimeOffset]$Now)
    if ($Now -lt $ObservedAt) { throw 'Coordinator clock moved backwards.' }
    $anchor = if ($ObservedHead -ceq $CurrentHead) { $ObservedAt } else { $Now }
    [ordered]@{ head = $CurrentHead; observedAt = $anchor.ToString('o');
        quiet = ($Now - $anchor).TotalSeconds -ge 300;
        remainingSeconds = [int][Math]::Max(0, [Math]::Ceiling(300 - ($Now - $anchor).TotalSeconds)) }
}

function Get-CiAdmissionDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Candidate,
        [AllowNull()][System.Collections.IDictionary]$State, [Parameter(Mandatory)][string]$CurrentHead,
        [bool]$Quiet, [switch]$Retry)
    if ($Candidate.commit -cne $CurrentHead) { return [ordered]@{ action = 'superseded'; reason = 'main-moved-before-admission' } }
    if ($State -and $State.nativeDigest -ceq $Candidate.nativeDigest -and -not $Retry) {
        if ($State.outcome -notin @('running', 'succeeded', 'failed', 'cancelled')) { throw 'Invalid recorded native outcome.' }
        return [ordered]@{ action = 'retain'; reason = 'inputs-already-admitted'; outcome = $State.outcome; runId = $State.runId }
    }
    if (-not $Quiet) { return [ordered]@{ action = 'wait'; reason = 'five-minute-quiet-window-required' } }
    [ordered]@{ action = 'admit'; reason = $(if ($Retry) { 'explicit-retry' } else { 'new-meaningful-inputs' }) }
}

function Test-CiRegressionReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Receipt,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Descriptor, [Parameter(Mandatory)][string]$Platform)
    foreach ($field in @('schemaVersion','repository','commit','nativeDigest','runId','platform','role','passed','countUnit','registered','expectedSkipped','discovered','executed','failed','unexpectedSkipped','assertionProbePassed','artifacts')) {
        if (-not $Receipt.Contains($field)) { throw "Missing regression receipt field: $field" }
    }
    if ($Receipt.schemaVersion -ne 1 -or $Receipt.repository -cne $Descriptor.repository -or $Receipt.commit -cne $Descriptor.commit -or
        $Receipt.nativeDigest -cne $Descriptor.nativeDigest -or $Receipt.runId -cne $Descriptor.runId -or
        $Receipt.platform -cne $Platform -or $Receipt.role -cne 'ReleaseTest') { throw 'Regression receipt identity mismatch.' }
    if ($Receipt.passed -isnot [bool] -or -not $Receipt.passed -or $Receipt.assertionProbePassed -isnot [bool] -or -not $Receipt.assertionProbePassed) { throw 'Regression or active-assertion probe did not pass.' }
    foreach ($field in @('registered','expectedSkipped','discovered','executed','failed','unexpectedSkipped')) {
        if ($Receipt[$field] -isnot [int] -and $Receipt[$field] -isnot [long]) { throw "Invalid regression count: $field" }
    }
    if($Receipt.countUnit -cnotin @('case','required-case','suite','scenario') -or $Receipt.expectedSkipped -lt 0 -or
        $Receipt.registered -ne ($Receipt.discovered+$Receipt.expectedSkipped)){throw 'Regression discovery/skip accounting is invalid.'}
    if ($Receipt.discovered -le 0 -or $Receipt.executed -ne $Receipt.discovered -or $Receipt.failed -ne 0 -or $Receipt.unexpectedSkipped -ne 0 -or @($Receipt.artifacts).Count -eq 0) { throw 'Incomplete regression execution.' }
    foreach ($artifact in $Receipt.artifacts) {
        if (-not $artifact.path -or $artifact.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid regression artifact identity.' }
    }
    return $true
}


function Test-CiWorkflowQueues {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    $lines=$Text -split [string][char]10
    for($index=0;$index -lt $lines.Count;$index++){
        if($lines[$index] -notmatch '^(?<space> *)[''"]?queue[''"]?:\s*(?<value>[^#]+?)\s*(?:#.*)?$'){continue}
        $indent=$Matches.space.Length
        $value=$Matches.value.Trim().Trim('''"')
        if($indent -lt 2 -or $value -cnotin @('max','single')){throw 'Invalid workflow concurrency queue value.'}
        $parent=$indent-2;$start=-1
        for($before=$index-1;$before -ge 0;$before--){
            $line=$lines[$before].TrimEnd()
            if(-not $line.Trim() -or $line.TrimStart().StartsWith('#')){continue}
            $width=$line.Length-$line.TrimStart().Length
            if($width -le $parent){
                if($width -eq $parent -and $line.Trim() -ceq 'concurrency:'){$start=$before}
                break
            }
        }
        if($start -lt 0){throw 'queue belongs only to a concurrency mapping.'}
        for($after=$start+1;$after -lt $lines.Count;$after++){
            $line=$lines[$after].TrimEnd()
            if(-not $line.Trim() -or $line.TrimStart().StartsWith('#')){continue}
            $width=$line.Length-$line.TrimStart().Length
            if($width -le $parent){break}
            if($value -ceq 'max' -and $width -eq $indent -and $line.Trim() -match '^cancel-in-progress:\s*(.+)$' -and $Matches[1].Trim() -cne 'false'){
                throw 'queue:max cannot be combined with cancellation or an unevaluated cancellation expression.'
            }
        }
    }
    return $true
}

Export-ModuleMember -Function Invoke-CiProcess, Invoke-CiGit, Get-CiSha256, Resolve-CiCommit, Read-CiProject, Test-CiGlob, Assert-CiContainedPath, Get-CiPathDisposition, Get-CiChangedPaths, Get-CiChangeDecision, New-CiInputDescriptor, Get-CiQuietDecision, Get-CiAdmissionDecision, Test-CiRegressionReceipt, Test-CiWorkflowQueues
