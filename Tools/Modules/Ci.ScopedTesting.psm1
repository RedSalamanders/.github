# Scoped testing, version 2: changed paths against the merge base, plans with reasons, evidence identities, receipts,
# the iteration baseline and the profile lease that Tools/Test-Changes.ps1 runs (Specs/ProjectCommands.md, "Scoped
# testing"). Every repository fact comes from the product's Tests/test-scopes.json (Schemas/test-scopes.schema.json).
# No network, compiler, desktop or GitHub access; nothing here writes outside the product's .build/reports.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function Invoke-ScopedGit([string]$Root, [string[]]$Arguments) {
    # Read-only (no optional index refresh); UTF-8 output; callers list paths NUL-delimited.
    $result = Invoke-CiProcess -FilePath 'git' -Arguments (@('--no-optional-locks', '-c', 'core.quotepath=false', '-c', 'core.fsmonitor=false') + $Arguments) `
        -WorkingDirectory $Root -TimeoutSeconds 300 -AllowFailure
    if ($result.exitCode -ne 0) {
        # Name the command and its exit code: merge-base, for one, fails silently when the histories share no commit.
        $text = $result.stderr.Trim()
        throw "Git scope discovery failed: git $($Arguments -join ' ') exited with code $($result.exitCode): $(if ($text) { $text } else { '(no message)' })"
    }
    return $result.stdout
}

function Split-ScopedNul([AllowEmptyString()][string]$Text) {
    return $Text.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)
}

function Get-ScopedOrdinalUniquePaths([AllowEmptyCollection()][string[]]$Paths) {
    # Git path identity is ordinal and case-sensitive, even where the file system is not.
    $unique = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $Paths) { if (-not [string]::IsNullOrEmpty($path)) { [void]$unique.Add($path) } }
    return @($unique)
}

function Get-ScopedTrackedPaths([string]$Root) {
    return @(Get-ScopedOrdinalUniquePaths (Split-ScopedNul (Invoke-ScopedGit $Root @('ls-files', '--cached', '--others', '--exclude-standard', '-z'))))
}

function Get-ScopedFileHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try { return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) } finally { $stream.Dispose() }
}

function Get-ScopedMergeBase([string]$Root, [string]$BaseRef) {
    # A base that does not resolve and one that shares no history with HEAD need different remedies; both name the
    # full run, which needs no comparison.
    try { [void](Invoke-ScopedGit $Root @('rev-parse', '--verify', '--quiet', '--end-of-options', "$BaseRef^{commit}")) }
    catch [System.Management.Automation.RuntimeException] {
        throw "Scoped testing compares HEAD with '$BaseRef', which does not resolve here: fetch it, pass -BaseRef <ref>, or run every scope (Test-Changes.ps1 -Mode Full). $($_.Exception.Message)"
    }
    try { return (Invoke-ScopedGit $Root @('merge-base', '--end-of-options', $BaseRef, 'HEAD')).Trim() }
    catch [System.Management.Automation.RuntimeException] {
        throw "HEAD shares no history with '$BaseRef': deepen a shallow clone (git fetch --unshallow), pass -BaseRef <ref>, or run every scope (Test-Changes.ps1 -Mode Full). $($_.Exception.Message)"
    }
}

function Get-ScopedComparisonProblem {
    <# .SYNOPSIS Why affected selection cannot compare HEAD with BaseRef here, or '' when it can. Read-only. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$BaseRef)
    try { [void](Get-ScopedMergeBase $Root $BaseRef); return '' }
    catch [System.Management.Automation.RuntimeException] { return $_.Exception.Message }
}

function Get-ScopedChangedPaths {
    <#
    .SYNOPSIS Paths changed since HEAD's merge base with BaseRef: committed, staged, unstaged, deleted and untracked.
    .DESCRIPTION Refuses, naming the remedy, when BaseRef does not resolve or shares no history with HEAD. Read-only.
    .OUTPUTS Repository-relative Git paths, ordinal and unique.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$BaseRef)
    $base = Get-ScopedMergeBase $Root $BaseRef
    $texts = foreach ($arguments in @(
            @('diff', '--no-ext-diff', '--no-textconv', '--name-only', '--no-renames', '-z', $base, 'HEAD', '--'),
            @('diff', '--no-ext-diff', '--no-textconv', '--cached', '--name-only', '--no-renames', '-z', '--'),
            @('diff', '--no-ext-diff', '--no-textconv', '--name-only', '--no-renames', '-z', '--'),
            @('ls-files', '--others', '--exclude-standard', '-z'))) {
        Split-ScopedNul (Invoke-ScopedGit $Root $arguments)
    }
    return @(Get-ScopedOrdinalUniquePaths @($texts))
}

function Get-ScopedBuildNumber {
    <#
    .SYNOPSIS The build number of buildNumber 'mergeBaseCount': the commit count of HEAD's merge base with BaseRef.
    .DESCRIPTION A commit neither relinks version-stamped binaries nor invalidates native evidence; a rebase does.
    Without that base (a Full run's remedy), the commit count of HEAD. Read-only.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$BaseRef)
    try { $base = Get-ScopedMergeBase $Root $BaseRef } catch [System.Management.Automation.RuntimeException] { $base = 'HEAD' }
    return [int](Invoke-ScopedGit $Root @('rev-list', '--count', '--end-of-options', $base)).Trim()
}

function Assert-ScopedRuntimePlatform {
    <#
    .SYNOPSIS Refuses runtime tests of a platform the host does not run natively (exact match: x64 on X64, ARM64 on Arm64).
    .DESCRIPTION A cross build stays a build: build.ps1 or a buildOnly PrePush profile.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('x64', 'ARM64')][string]$Platform,
        [string]$HostArchitecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString())
    $expected = if ($Platform -ceq 'ARM64') { 'Arm64' } else { 'X64' }
    if ($HostArchitecture -cne $expected) {
        throw "Native runtime testing of $Platform requires a matching $Platform host; this host is $HostArchitecture. A cross build stays a build: run build.ps1 -Platform $Platform, or list the profile with buildOnly in prePushProfiles."
    }
}

function ConvertTo-ScopedPatternText([string]$Pattern) {
    return [regex]::Escape($Pattern).Replace('\*\*/', '(?:.*/)?').Replace('\*\*', '.*').Replace('\*', '[^/]*').Replace('\?', '[^/]')
}

function Get-ScopedPatternExpression([string]$Pattern) {
    if (-not (Get-Variable -Name ScopedPatternCache -Scope Script -ErrorAction Ignore)) {
        $script:ScopedPatternCache = [Collections.Generic.Dictionary[string, regex]]::new([StringComparer]::Ordinal)
    }
    $expression = $null
    if (-not $script:ScopedPatternCache.TryGetValue($Pattern, [ref]$expression)) {
        $expression = [regex]::new('^' + (ConvertTo-ScopedPatternText $Pattern) + '$', [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        $script:ScopedPatternCache[$Pattern] = $expression
    }
    return $expression
}

function New-ScopedAnyExpression([AllowEmptyCollection()][object[]]$Patterns) {
    # One expression for "any of these globs", or $null for none.
    $texts = @(foreach ($pattern in $Patterns) { '(?:' + (ConvertTo-ScopedPatternText ([string]$pattern)) + ')' })
    if (-not $texts.Count) { return $null }
    return [regex]::new('^(?:' + ($texts -join '|') + ')$', [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant)
}

function Test-ScopedPattern {
    <# .SYNOPSIS Whether a repository-relative path matches a glob (** any folders, * and ? within one name; case-insensitive). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path, [Parameter(Mandatory)][string]$Pattern)
    return (Get-ScopedPatternExpression $Pattern).IsMatch($Path)
}

function Test-ScopedAnyPattern([string]$Path, [AllowEmptyCollection()][object[]]$Patterns) {
    foreach ($pattern in $Patterns) { if ((Get-ScopedPatternExpression ([string]$pattern)).IsMatch($Path)) { return $true } }
    return $false
}

function Assert-ScopedRelativePath([string]$Value, [string]$What) {
    if ([string]::IsNullOrEmpty($Value) -or $Value -match '(^/|(^|/)\.\.(/|$)|:|\\)' -or $Value.Contains([char]0)) {
        throw "Tests/test-scopes.json: $What '$Value' is not a repository-relative path."
    }
}

function Add-ScopedDefault([object]$Object, [string]$Name, $Value) {
    if (-not $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Read-ScopedTestManifest {
    <#
    .SYNOPSIS Reads and validates the product's Tests/test-scopes.json (version 2).
    .DESCRIPTION Validates the engine schema, then what a schema cannot: unique scope names, known scopes in every rule,
    binding and override, exact paths for exclusive rules, repository-relative globs, a native inventory when a scope
    is native, and distinct PrePush profiles. Optional keys receive their defaults, rule scopes their declared
    spelling, and projectBindings become exact-path liveRules. Read-only.
    .PARAMETER SkipProjectRules Leaves liveRules empty instead of reading the bound projects and their sources, for a
    caller that needs only the data's own keys.
    .OUTPUTS The data object, with liveRules.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [switch]$SkipProjectRules)
    $path = Join-Path $Root 'Tests/test-scopes.json'
    if (-not [IO.File]::Exists($path)) {
        throw "Scoped testing needs Tests/test-scopes.json (version 2, Schemas/test-scopes.schema.json in the engine); $path is missing."
    }
    $text = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false, $true))
    $schema = Join-Path $PSScriptRoot '../../Schemas/test-scopes.schema.json'
    $problems = $null
    $valid = $false
    try { $valid = Test-Json -Json $text -SchemaFile $schema -ErrorAction SilentlyContinue -ErrorVariable problems }
    catch { $problems = @($_) }
    if (-not $valid) {
        $details = @(@($problems) | Where-Object { $_ } | ForEach-Object { $_.Exception.Message }) -join '; '
        throw "Tests/test-scopes.json is not valid scoped testing data (version 2, the engine's Schemas/test-scopes.schema.json; Specs/ProjectCommands.md, Scoped testing): $details"
    }
    $manifest = ConvertFrom-Json -InputObject $text
    $canonical = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($scope in @($manifest.scopes)) {
        if (-not $canonical.TryAdd($scope.name, $scope.name)) { throw "Tests/test-scopes.json declares the scope '$($scope.name)' twice." }
        # A native receipt lives beside the profile's build attestation and iteration baseline.
        if ($scope.native -and $scope.name -in @('build', 'iteration')) { throw "Tests/test-scopes.json: '$($scope.name)' is reserved and cannot name a native scope." }
        Add-ScopedDefault $scope 'configurations' $null
        Add-ScopedDefault $scope 'commands' @()
        foreach ($command in @($scope.commands)) { Assert-ScopedRelativePath $command.path "the command of scope $($scope.name)" }
    }
    $resolve = {
        param([object[]]$Names, [string]$Owner)
        foreach ($name in $Names) {
            if ($name -ceq '*') { '*'; continue }
            $known = $null
            if (-not $canonical.TryGetValue($name, [ref]$known)) { throw "Tests/test-scopes.json: $Owner selects the unknown scope '$name'." }
            $known
        }
    }
    foreach ($rule in @($manifest.rules)) {
        Assert-ScopedRelativePath $rule.pattern 'the rule pattern'
        Add-ScopedDefault $rule 'exclusive' $false
        Add-ScopedDefault $rule 'additive' $false
        Add-ScopedDefault $rule 'fallback' $false
        $rule.scopes = @(& $resolve @($rule.scopes) "the rule '$($rule.pattern)'")
        # An exclusive rule is an isolated exception for one exact path, never a prefix-wide exclusion.
        if ($rule.exclusive -and $rule.pattern -match '[*?]') { throw "Tests/test-scopes.json: the exclusive rule '$($rule.pattern)' must name one exact path, not a pattern." }
    }
    foreach ($name in @('prose', 'unscoped')) { foreach ($pattern in @($manifest.$name)) { Assert-ScopedRelativePath $pattern "the $name pattern" } }
    Add-ScopedDefault $manifest 'nativeInventory' $null
    Add-ScopedDefault $manifest 'runtimeFiles' @()
    Add-ScopedDefault $manifest 'projectBindings' $null
    Add-ScopedDefault $manifest 'interactiveObligations' @()
    Add-ScopedDefault $manifest 'instrumentationVariables' @()
    Add-ScopedDefault $manifest 'systemFiles' @()
    foreach ($file in @($manifest.runtimeFiles)) { Assert-ScopedRelativePath $file 'the runtime file' }
    if ($manifest.nativeInventory) {
        Assert-ScopedRelativePath $manifest.nativeInventory.path 'the native inventory'
        foreach ($pattern in @($manifest.nativeInventory.exclude) + @($manifest.nativeInventory.testFolders)) { Assert-ScopedRelativePath $pattern 'the native inventory pattern' }
    } elseif (@($manifest.scopes | Where-Object { $_.native }).Count) {
        throw 'Tests/test-scopes.json declares native scopes without a nativeInventory of their test sources.'
    }
    foreach ($obligation in @($manifest.interactiveObligations)) { Assert-ScopedRelativePath $obligation.pattern 'the interactive obligation pattern' }
    $profiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($manifest.prePushProfiles)) {
        Add-ScopedDefault $entry 'buildOnly' $false
        if (-not $profiles.Add("$($entry.platform)|$($entry.configuration)")) { throw "Tests/test-scopes.json lists the PrePush profile $($entry.platform) $($entry.configuration) twice." }
    }
    $live = @()
    if ($manifest.projectBindings) {
        foreach ($pattern in @($manifest.projectBindings.exclude)) { Assert-ScopedRelativePath $pattern 'the project binding exclusion' }
        foreach ($folder in @($manifest.projectBindings.includeRoots)) { Assert-ScopedRelativePath $folder 'the include root' }
        foreach ($project in @($manifest.projectBindings.projects)) {
            Assert-ScopedRelativePath $project.path 'the bound project'
            $project.scopes = @(& $resolve @($project.scopes) "the project binding '$($project.path)'")
            Add-ScopedDefault $project 'overrides' @()
            foreach ($override in @($project.overrides)) {
                Assert-ScopedRelativePath $override.pattern 'the project binding override'
                $override.scopes = @(& $resolve @($override.scopes) "an override of '$($project.path)'")
            }
        }
        if (-not $SkipProjectRules) { $live = @(Get-ScopedProjectRules -Root $Root -Bindings $manifest.projectBindings) }
    }
    $manifest | Add-Member -NotePropertyName liveRules -NotePropertyValue $live -Force
    return $manifest
}

function Assert-ScopedTestNames {
    <#
    .SYNOPSIS Proves the native test inventory: every declared file exists and is named *.Tests.*.cpp|h, and every live
    native test source (in a test folder, with a .Tests. name, or a SelfTest/Test/Mock/Fake name component) is declared.
    .OUTPUTS The number of declared files; 0 when the repository declares no native inventory. Read-only.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [object]$Manifest = $null)
    if (-not $Manifest) { $Manifest = Read-ScopedTestManifest $Root }
    $inventory = $Manifest.nativeInventory
    if (-not $inventory) { return 0 }
    $file = Join-Path $Root $inventory.path
    if (-not [IO.File]::Exists($file)) { throw "The native test inventory $($inventory.path) is missing." }
    $parsed = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file, [Text.UTF8Encoding]::new($false, $true))) -NoEnumerate
    $declared = @(if ($parsed -is [array]) { $parsed } elseif ($parsed.PSObject.Properties['files']) { @($parsed.files | ForEach-Object { $_.path }) }
        else { throw "The native test inventory $($inventory.path) is neither a list of paths nor {files:[{path}]}." })
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $declared) {
        if ($path -isnot [string] -or -not $seen.Add($path)) { throw "Duplicate or invalid native test inventory path: $path" }
        if (Test-ScopedAnyPattern $path @($inventory.exclude)) { throw "Historical or external source cannot enter the active test inventory: $path" }
        if ($path -cnotmatch '(^|/)[^/]+\.Tests\.[^/]+\.(cpp|h)$' -or -not [IO.File]::Exists((Join-Path $Root $path))) { throw "Invalid or missing native test source: $path" }
    }
    # Outside the test folders a name marks a test source by a .Tests. segment in any spelling, or by a SelfTest, Test,
    # Mock or Fake name component in the case the naming rule uses (FakeClock.h, MockHost.cpp), never by those letters
    # inside a word (Attestation.h, LatestRelease.cpp, Mockingbird.h).
    foreach ($path in @(Get-ScopedTrackedPaths $Root)) {
        if ($path -notmatch '\.(cpp|h)$' -or (Test-ScopedAnyPattern $path @($inventory.exclude))) { continue }
        $test = (Test-ScopedAnyPattern $path @($inventory.testFolders)) -or $path -match '(^|/)[^/]*\.Tests\.[^/]*$' -or
            $path -cmatch '(^|/)[^/]*(SelfTest|Tests?|Mocks?|Fakes?)(?=[A-Z0-9_.-])[^/]*$'
        if ($test -and [IO.File]::Exists((Join-Path $Root $path)) -and -not $seen.Contains($path)) {
            throw "Native test source is absent from $($inventory.path): $path"
        }
    }
    return $declared.Count
}

function Get-ScopedProjectRules {
    <#
    .SYNOPSIS Exact-path rules for the compiled inputs of bound native projects and their transitive local includes.
    .DESCRIPTION Reads ClCompile, ResourceCompile, CustomBuild and FxCompile items; a macro or wildcard item or an
    unparsable #include adds a conservative '**' full-fallback rule. Read-only.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][object]$Bindings)
    $owners = [Collections.Generic.Dictionary[string, Collections.Generic.SortedSet[string]]]::new([StringComparer]::OrdinalIgnoreCase)
    $includes = [Collections.Generic.Dictionary[string, string[]]]::new([StringComparer]::OrdinalIgnoreCase)
    $ownedByLeaf = [Collections.Generic.Dictionary[string, Collections.Generic.List[string]]]::new([StringComparer]::OrdinalIgnoreCase)
    $unresolved = $false
    foreach ($owned in @(Get-ScopedTrackedPaths $Root)) {
        if (Test-ScopedAnyPattern $owned @($Bindings.exclude)) { continue }
        $leaf = [IO.Path]::GetFileName($owned)
        if (-not $ownedByLeaf.ContainsKey($leaf)) { $ownedByLeaf[$leaf] = [Collections.Generic.List[string]]::new() }
        $ownedByLeaf[$leaf].Add($owned)
    }
    foreach ($project in @($Bindings.projects)) {
        $projectFile = Join-Path $Root $project.path
        if (-not [IO.File]::Exists($projectFile)) { throw "Missing bound native project: $($project.path)" }
        $directory = Split-Path $projectFile
        $document = [xml]::new()
        $document.XmlResolver = $null
        $document.LoadXml([IO.File]::ReadAllText($projectFile))
        $stack = [Collections.Generic.Stack[string]]::new()
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($node in $document.SelectNodes('//*[local-name()="ClCompile" or local-name()="ResourceCompile" or local-name()="CustomBuild" or local-name()="FxCompile"]')) {
            if (-not $node.HasAttribute('Include')) { continue }
            $include = $node.GetAttribute('Include')
            if ($include -match '\$|%|\*|\?') { $unresolved = $true; continue }
            $file = [IO.Path]::GetFullPath((Join-Path $directory $include))
            if (-not [IO.File]::Exists($file)) { throw "Missing native project input: $($project.path) -> $include" }
            $stack.Push($file)
        }
        while ($stack.Count) {
            $file = $stack.Pop()
            if (-not $seen.Add($file)) { continue }
            $relative = [IO.Path]::GetRelativePath($Root, $file).Replace('\', '/')
            if ($relative -match '^\.\./|^\.build/') { continue }
            $scopes = @($project.scopes)
            foreach ($override in @($project.overrides)) { if (Test-ScopedPattern $relative $override.pattern) { $scopes = @($override.scopes); break } }
            if (-not $owners.ContainsKey($relative)) { $owners[$relative] = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal) }
            foreach ($scope in $scopes) { [void]$owners[$relative].Add($scope) }
            if (-not $includes.ContainsKey($file)) {
                $body = [IO.File]::ReadAllText($file)
                $found = [Collections.Generic.List[string]]::new()
                if ($body -match '(?m)^\s*#\s*include\s+[^\s"<]') { $unresolved = $true }
                foreach ($match in [regex]::Matches($body, '(?m)^\s*#\s*include\s*[<"]([^">]+)[">]')) {
                    $name = $match.Groups[1].Value.Replace('\', '/')
                    $leaf = [IO.Path]::GetFileName($name)
                    if (-not $ownedByLeaf.ContainsKey($leaf)) { continue }
                    $candidates = @(@((Join-Path (Split-Path $file) $name), (Join-Path $Root $name)) + @(@($Bindings.includeRoots) | ForEach-Object { Join-Path $Root "$_/$name" }) |
                        ForEach-Object { [IO.Path]::GetRelativePath($Root, [IO.Path]::GetFullPath($_)).Replace('\', '/') })
                    foreach ($candidate in $ownedByLeaf[$leaf]) {
                        if ($candidate -cin $candidates -or $candidate -ceq $name -or $candidate.EndsWith('/' + $name, [StringComparison]::OrdinalIgnoreCase)) {
                            $found.Add([IO.Path]::GetFullPath((Join-Path $Root $candidate)))
                        }
                    }
                }
                $includes[$file] = $found.ToArray()
            }
            foreach ($next in $includes[$file]) { $stack.Push($next) }
        }
    }
    $paths = [string[]]@($owners.Keys)
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    foreach ($path in $paths) {
        [pscustomobject]@{ pattern = $path; scopes = @($owners[$path]); reason = 'current native project and transitive local-include consumers'; exclusive = $false; additive = $false; fallback = $false }
    }
    if ($unresolved) {
        [pscustomobject]@{ pattern = '**'; scopes = @('*'); reason = 'unresolved macro, wildcard or include in a bound native project; conservative full fallback'; exclusive = $false; additive = $false; fallback = $false }
    }
}

function New-ScopedRuleMatcher([object]$Manifest) {
    # Exact-path rules (most derived rules) by dictionary, globs by expression; matches keep the data's order.
    $exact = [Collections.Generic.Dictionary[string, Collections.Generic.List[object]]]::new([StringComparer]::OrdinalIgnoreCase)
    $globs = [Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($rule in @(@($Manifest.rules) + @($Manifest.liveRules))) {
        $entry = [pscustomobject]@{ Index = $index; Rule = $rule }
        $index++
        if ($rule.pattern -match '[*?]') { $globs.Add($entry); continue }
        if (-not $exact.ContainsKey($rule.pattern)) { $exact[$rule.pattern] = [Collections.Generic.List[object]]::new() }
        $exact[$rule.pattern].Add($entry)
    }
    return [pscustomobject]@{ Exact = $exact; Globs = $globs }
}

function New-ScopedPathClassifier([object]$Manifest) {
    # The classification of Resolve-ScopedPath reduced to what identities need over a whole tree: a dictionary lookup
    # and a few combined expressions per path. Exact-path flags: 1 exclusive, 2 maps, 4 maps a native scope from a
    # Markdown pattern, 8 the same from an additive rule, 16 a fallback match.
    $native = [Collections.Generic.HashSet[string]]::new([string[]]@(@($Manifest.scopes) | Where-Object { $_.native } | ForEach-Object { $_.name }), [StringComparer]::OrdinalIgnoreCase)
    $exact = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
    $mapping = [Collections.Generic.List[string]]::new()
    $markdown = [Collections.Generic.List[string]]::new()
    $markdownAdditive = [Collections.Generic.List[string]]::new()
    $fallback = [Collections.Generic.List[string]]::new()
    foreach ($rule in @(@($Manifest.rules) + @($Manifest.liveRules))) {
        $nativeRule = $false
        foreach ($scope in @($rule.scopes)) { if ($scope -ceq '*' -or $native.Contains($scope)) { $nativeRule = $true } }
        $markdownRule = $nativeRule -and $rule.pattern -match '\.md$'
        $flags = if ($rule.exclusive) { 1 } elseif ($rule.fallback) { 16 } elseif (-not $rule.additive) { 2 -bor $(if ($markdownRule) { 4 } else { 0 }) } elseif ($markdownRule) { 8 } else { 0 }
        if ($rule.pattern -notmatch '[*?]') {
            $previous = 0
            [void]$exact.TryGetValue($rule.pattern, [ref]$previous)
            $exact[$rule.pattern] = $previous -bor $flags
            continue
        }
        if ($flags -band 2) { $mapping.Add($rule.pattern) }
        if ($flags -band 4) { $markdown.Add($rule.pattern) }
        if ($flags -band 8) { $markdownAdditive.Add($rule.pattern) }
        if ($flags -band 16) { $fallback.Add($rule.pattern) }
    }
    return [pscustomobject]@{ Exact = $exact; Mapping = (New-ScopedAnyExpression $mapping.ToArray()); Markdown = (New-ScopedAnyExpression $markdown.ToArray())
        MarkdownAdditive = (New-ScopedAnyExpression $markdownAdditive.ToArray()); Prose = (New-ScopedAnyExpression @($Manifest.prose))
        Unscoped = (New-ScopedAnyExpression @($Manifest.unscoped)); Fallback = (New-ScopedAnyExpression $fallback.ToArray()) }
}

function Get-ScopedPathKind([object]$Classifier, [string]$Path) {
    # Prose mapped to a native scope is reported separately so compiled identity retains it.
    $flags = 0
    [void]$Classifier.Exact.TryGetValue($Path, [ref]$flags)
    if ($flags -band 1) { return 'exclusive' }
    $mapped = [bool]($flags -band 2) -or ($null -ne $Classifier.Mapping -and $Classifier.Mapping.IsMatch($Path))
    if ($null -ne $Classifier.Prose -and $Classifier.Prose.IsMatch($Path)) {
        if ($mapped -and ([bool]($flags -band 12) -or ($null -ne $Classifier.Markdown -and $Classifier.Markdown.IsMatch($Path)) -or
                ($null -ne $Classifier.MarkdownAdditive -and $Classifier.MarkdownAdditive.IsMatch($Path)))) { return 'native prose' }
        return 'prose'
    }
    if ($mapped) { return 'rule' }
    if ($null -ne $Classifier.Unscoped -and $Classifier.Unscoped.IsMatch($Path)) { return 'unscoped' }
    if (($flags -band 16) -or ($null -ne $Classifier.Fallback -and $Classifier.Fallback.IsMatch($Path))) { return 'fallback' }
    return 'unmapped'
}

function Resolve-ScopedPath([object]$Manifest, [object]$Matcher, [string]$Path, [string[]]$Names, [string[]]$NonNative) {
    # The one classification every plan and identity uses (Specs/ProjectCommands.md, Scoped testing):
    # Exact exclusive rules, prose, explicit mappings, unscoped paths, the first fallback, then the implicit full fallback.
    $entries = [Collections.Generic.List[object]]::new()
    $exactEntries = $null
    if ($Matcher.Exact.TryGetValue($Path, [ref]$exactEntries)) { $entries.AddRange($exactEntries) }
    foreach ($entry in $Matcher.Globs) { if ((Get-ScopedPatternExpression $entry.Rule.pattern).IsMatch($Path)) { $entries.Add($entry) } }
    $matched = @($entries | Sort-Object Index | ForEach-Object { $_.Rule })
    $expand = { param($Rule) if ('*' -cin @($Rule.scopes)) { $Names } else { @($Rule.scopes) } }
    $exclusive = @($matched | Where-Object { $_.exclusive })
    if ($exclusive.Count) {
        return [pscustomobject]@{ kind = 'exclusive'; reasons = @($exclusive | ForEach-Object { [pscustomobject]@{ scopes = @(& $expand $_); reason = $_.reason } }) }
    }
    $mapping = @($matched | Where-Object { -not $_.exclusive -and -not $_.fallback })
    if (-not @($mapping | Where-Object { -not $_.additive }).Count) { $mapping = @() }
    if (Test-ScopedAnyPattern $Path @($Manifest.prose)) {
        $reasons = @([pscustomobject]@{ scopes = $NonNative; reason = 'prose: validated by every non-native scope; no native test input' })
        # A rule that names Markdown explicitly declares a runtime document; broad folder rules do not.
        $reasons += @($mapping | Where-Object { $_.pattern -match '\.md$' } | ForEach-Object { [pscustomobject]@{ scopes = @(& $expand $_); reason = $_.reason } })
        return [pscustomobject]@{ kind = 'prose'; reasons = $reasons }
    }
    if ($mapping.Count) {
        return [pscustomobject]@{ kind = 'rule'; reasons = @($mapping | ForEach-Object { [pscustomobject]@{ scopes = @(& $expand $_); reason = $_.reason } }) }
    }
    if (Test-ScopedAnyPattern $Path @($Manifest.unscoped)) {
        return [pscustomobject]@{ kind = 'unscoped'; reasons = @([pscustomobject]@{ scopes = @(); reason = 'unscoped: no test input' }) }
    }
    foreach ($rule in $matched) {
        if ($rule.fallback) {
            return [pscustomobject]@{ kind = 'fallback'; reasons = @([pscustomobject]@{ scopes = @(& $expand $rule); reason = $rule.reason }) }
        }
    }
    return [pscustomobject]@{ kind = 'unmapped'; reasons = @([pscustomobject]@{ scopes = $Names; reason = 'unmapped input; conservative full fallback' }) }
}

function Assert-ScopedGitPath([string]$Path) {
    if ($Path -match '(^/|(^|/)\.\.(/|$)|:|\\)' -or $Path.Contains([char]0)) { throw "Expected a repository-relative Git path: $Path" }
}

function Get-ScopedTestPlan {
    <#
    .SYNOPSIS Selects scopes for changed paths, explicit scopes or every scope, with one reason per path and rule.
    .PARAMETER Configuration When given, drops (and lists in notApplicable) scopes whose configurations exclude it, and
    refuses an explicit scope that does not run in it.
    .OUTPUTS scopes (in data order), reasons {path, kind, scopes, reason}, full (every applicable scope), prose (only
    prose or unscoped paths and no native scope), notApplicable.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Manifest, [AllowEmptyCollection()][string[]]$ChangedPaths = @(),
        [AllowEmptyCollection()][string[]]$Scopes = @(), [switch]$Full, [string]$Configuration = '')
    $all = @($Manifest.scopes)
    $names = [string[]]@($all | ForEach-Object { $_.name })
    $nonNative = [string[]]@($all | Where-Object { -not $_.native } | ForEach-Object { $_.name })
    $applicable = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($scope in $all) { if (-not $Configuration -or -not $scope.configurations -or $Configuration -cin @($scope.configurations)) { [void]$applicable.Add($scope.name) } }
    $selected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $reasons = [Collections.Generic.List[object]]::new()
    $kinds = [Collections.Generic.List[string]]::new()
    foreach ($requested in $Scopes) {
        $scope = @($all | Where-Object { $_.name -ieq $requested })
        if (-not $scope.Count) { throw "Unknown test scope '$requested'. Available: $($names -join ', ')" }
        if (-not $applicable.Contains($scope[0].name)) { throw "Scope '$($scope[0].name)' does not run in $Configuration." }
        [void]$selected.Add($scope[0].name)
        $reasons.Add([pscustomobject]@{ path = '(explicit)'; kind = 'explicit'; scopes = @($scope[0].name); reason = 'explicit scope' })
    }
    if ($Full) {
        foreach ($name in $names) { [void]$selected.Add($name) }
        $reasons.Add([pscustomobject]@{ path = '(all)'; kind = 'full'; scopes = $names; reason = 'every scope' })
    }
    if (-not $Scopes.Count -and -not $Full) {
        $matcher = New-ScopedRuleMatcher $Manifest
        foreach ($path in $ChangedPaths) {
            Assert-ScopedGitPath $path
            $resolved = Resolve-ScopedPath $Manifest $matcher $path $names $nonNative
            $kinds.Add($resolved.kind)
            foreach ($entry in $resolved.reasons) {
                foreach ($name in $entry.scopes) { [void]$selected.Add($name) }
                $reasons.Add([pscustomobject]@{ path = $path; kind = $resolved.kind; scopes = @($entry.scopes); reason = $entry.reason })
            }
        }
    }
    $chosen = [string[]]@($names | Where-Object { $selected.Contains($_) -and $applicable.Contains($_) })
    $nativeChosen = @($all | Where-Object { $_.native -and $_.name -cin $chosen }).Count
    return [pscustomobject]@{
        scopes = $chosen
        reasons = $reasons.ToArray()
        full = $chosen.Count -gt 0 -and $chosen.Count -eq $applicable.Count
        prose = -not $Full -and -not $Scopes.Count -and $kinds.Contains('prose') -and -not $nativeChosen -and
            -not @($kinds | Where-Object { $_ -cnotin @('prose', 'unscoped') }).Count
        notApplicable = [string[]]@($names | Where-Object { $selected.Contains($_) -and -not $applicable.Contains($_) })
    }
}

function Get-ScopedInteractiveObligations {
    <# .SYNOPSIS The interactive suites a change (or a full run) obliges; scoped testing lists them and never runs them. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Manifest, [AllowEmptyCollection()][string[]]$ChangedPaths = @(), [switch]$Full)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($rule in @($Manifest.interactiveObligations)) {
        if (-not $Full -and -not @($ChangedPaths | Where-Object { Test-ScopedPattern $_ $rule.pattern }).Count) { continue }
        foreach ($suite in @($rule.suites)) {
            if ($seen.Add([string]$suite)) { [pscustomobject]@{ suite = [string]$suite; pattern = [string]$rule.pattern; reason = [string]$rule.reason } }
        }
    }
}

function Get-ScopedDigest {
    <# .SYNOPSIS Lowercase SHA-256 of UTF-8 text. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Get-ScopedSourceMap {
    <#
    .SYNOPSIS Path-to-SHA-256 of every tracked and non-ignored untracked file whose change can select a scope.
    .DESCRIPTION Leaves out .build and unscoped paths; -CompiledOnly also leaves out prose that selects no native scope.
    A listed path that is neither on disk nor a tracked deletion is refused. Read-only.
    .PARAMETER From A full map taken earlier by this command: -CompiledOnly then filters it without listing or reading
    the checkout again.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [object]$Manifest = $null, [switch]$CompiledOnly, [Collections.IDictionary]$From = $null)
    if (-not $Manifest) { $Manifest = Read-ScopedTestManifest $Root }
    $classifier = New-ScopedPathClassifier $Manifest
    $map = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    if ($null -ne $From) {
        foreach ($path in @($From.Keys)) {
            if ($CompiledOnly -and (Get-ScopedPathKind $classifier $path) -ceq 'prose') { continue }
            $map.Add($path, $From[$path])
        }
        return , $map
    }
    $deleted = $null
    foreach ($path in @(Get-ScopedTrackedPaths $Root)) {
        if ($path.StartsWith('.build/', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $kind = Get-ScopedPathKind $classifier $path
        if ($kind -ceq 'unscoped' -or ($CompiledOnly -and $kind -ceq 'prose')) { continue }
        $full = Join-Path $Root $path
        if (-not [IO.File]::Exists($full)) {
            # A nested repository is listed as its folder; its files are not inputs of this tree.
            if ([IO.Directory]::Exists($full)) { continue }
            if ($null -eq $deleted) { $deleted = [Collections.Generic.HashSet[string]]::new([string[]]@(Split-ScopedNul (Invoke-ScopedGit $Root @('ls-files', '--deleted', '-z'))), [StringComparer]::Ordinal) }
            if ($deleted.Contains($path)) { continue }
            throw "Source identity input '$path' is listed by Git but is neither on disk nor deleted. Run again once concurrent edits settle."
        }
        $map.Add($path, (Get-ScopedFileHash $full))
    }
    return , $map
}

function Get-ScopedMapIdentity {
    <# .SYNOPSIS Digest of a path map, ordinal by path. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$Map)
    $rows = foreach ($path in @(Get-ScopedOrdinalUniquePaths @($Map.Keys))) { "$path`0$($Map[$path])" }
    return Get-ScopedDigest (@($rows) -join "`n")
}

function Get-ScopedIndexMap {
    <# .SYNOPSIS Path to mode, blob and index flags of every index entry; refuses unresolved conflicts. Read-only. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    $map = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    # Assume-unchanged, skip-worktree and intent-to-add state (the -v tag) count as well as mode and blob.
    foreach ($entry in @(Split-ScopedNul (Invoke-ScopedGit $Root @('ls-files', '--stage', '-v', '-z')))) {
        if ($entry -cnotmatch '^([A-Za-z?]) (\d{6}) ([a-f0-9]+) ([0-3])\t([\s\S]+)$') { throw 'Unrecognized Git index record.' }
        if ($Matches[4] -cne '0') { throw 'Resolve Git conflicts before selecting affected tests.' }
        $map.Add($Matches[5], "$($Matches[2]) $($Matches[3]) $($Matches[1])")
    }
    return , $map
}

function Get-ScopedMapDelta {
    <# .SYNOPSIS Paths whose value differs between two maps, or that only one holds. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$Before, [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$After)
    return @(Get-ScopedOrdinalUniquePaths (@($Before.Keys) + @($After.Keys)) | Where-Object {
            -not $Before.Contains($_) -or -not $After.Contains($_) -or [string]$Before[$_] -cne [string]$After[$_]
        })
}

function Get-ScopedPendingIndexDelta {
    <#
    .SYNOPSIS Index changes that still need execution: staging already tested bytes needs none; a staged blob hidden by
    different working bytes, a mode or flag change and an index-only deletion do. Read-only.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$Before,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$After)
    $working = [Collections.Generic.HashSet[string]]::new([string[]]@(Split-ScopedNul (Invoke-ScopedGit $Root @('diff', '--name-only', '--no-renames', '-z', '--'))), [StringComparer]::Ordinal)
    foreach ($path in @(Get-ScopedMapDelta $Before $After)) {
        $old = if ($Before.Contains($path)) { @(([string]$Before[$path]).Split(' ')) } else { @() }
        $new = if ($After.Contains($path)) { @(([string]$After[$path]).Split(' ')) } else { @() }
        $oldMetadata = if ($old.Count) { "$($old[0]) $(if ($old.Count -gt 2) { $old[2] })" } else { '' }
        $newMetadata = if ($new.Count) { "$($new[0]) $(if ($new.Count -gt 2) { $new[2] })" } else { '' }
        if ($working.Contains($path) -or ($old.Count -and -not $new.Count) -or ($old.Count -and $new.Count -and $oldMetadata -cne $newMetadata)) { $path }
    }
}

function Get-ScopedEngineInputsIdentity([string]$Root) {
    # The pinned engine is ignored by product Git discovery but executes the governed tools: its actual raw bytes count,
    # through the product's own .ci-engine reader, apart from the file maps so it never looks like a changed product file.
    if (-not [IO.File]::Exists((Join-Path $Root '.ci/project.json'))) { return '' }
    $reader = [IO.Path]::GetFullPath((Join-Path $Root '.ci-engine/Tools/Modules/Ci.SourceInputs.psm1'))
    $module = @(Get-Module -Name 'Ci.SourceInputs' | Where-Object { [string]::Equals($_.Path, $reader, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
    if (-not $module) { $module = Import-Module $reader -PassThru -ErrorAction Stop }
    return & $module { param($ProductRoot) Get-CiPinnedEngineInputsIdentity -Root $ProductRoot } $Root
}

function Get-ScopedSourceIdentity {
    <#
    .SYNOPSIS Digest of the source map (-CompiledOnly: of native inputs) and of the pinned engine inputs. Read-only.
    .PARAMETER From A full map from Get-ScopedSourceMap to identify instead of listing the checkout again.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [object]$Manifest = $null, [switch]$CompiledOnly, [Collections.IDictionary]$From = $null)
    $map = if ($null -ne $From -and -not $CompiledOnly) { $From } else { Get-ScopedSourceMap -Root $Root -Manifest $Manifest -CompiledOnly:$CompiledOnly -From $From }
    $source = Get-ScopedMapIdentity $map
    $engine = Get-ScopedEngineInputsIdentity $Root
    if ($engine) { return Get-ScopedDigest ("$source`0$engine") }
    return $source
}

function Get-ScopedArtifactIdentity {
    <# .SYNOPSIS Digest of the profile's .exe, .dll, .lib and .pdb files under .build/<platform>/<configuration> and its runtimeFiles. Read-only. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Platform, [Parameter(Mandatory)][string]$Configuration, [object]$Manifest = $null)
    $directory = Join-Path $Root ".build/$Platform/$Configuration"
    if (-not [IO.Directory]::Exists($directory)) { throw "Missing build profile: $directory" }
    if (-not $Manifest) { $Manifest = Read-ScopedTestManifest $Root }
    $options = [IO.EnumerationOptions]::new()
    $options.RecurseSubdirectories = $true
    $options.AttributesToSkip = [IO.FileAttributes]::ReparsePoint
    $options.IgnoreInaccessible = $false
    $files = [Collections.Generic.SortedDictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($file in [IO.Directory]::EnumerateFiles($directory, '*', $options)) {
        if ([IO.Path]::GetExtension($file) -notin @('.exe', '.dll', '.lib', '.pdb')) { continue }
        $files[[IO.Path]::GetRelativePath($directory, $file).Replace('\', '/')] = $file
    }
    if (-not $files.Count) { throw 'No executable, library or debug-symbol build artifacts were found.' }
    foreach ($relative in @($Manifest.runtimeFiles)) {
        $path = Join-Path $directory $relative
        if (-not [IO.File]::Exists($path)) { throw "Missing deployed runtime input: $relative" }
        $files[$relative] = $path
    }
    $rows = foreach ($entry in $files.GetEnumerator()) { $entry.Key + ':' + (Get-ScopedFileHash $entry.Value) }
    return Get-ScopedDigest (@($rows) -join "`n")
}

function Get-ScopedGitVersion([string]$Path) {
    # Git for Windows can take most of a second to start; its version is read once per binary content.
    if (-not (Get-Variable -Name ScopedGitVersions -Scope Script -ErrorAction Ignore)) {
        $script:ScopedGitVersions = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    }
    $key = $Path + '|' + (Get-ScopedFileHash $Path)
    $version = $null
    if (-not $script:ScopedGitVersions.TryGetValue($key, [ref]$version)) {
        $version = (Invoke-CiProcess -FilePath $Path -Arguments @('--version') -WorkingDirectory ([IO.Path]::GetTempPath())).stdout.Trim()
        $script:ScopedGitVersions[$key] = $version
    }
    return $key + "`n" + $version
}

function Get-ScopedEnvironmentInputs {
    <#
    .SYNOPSIS The rows of the environment identity; only their digest is stored, never a secret.
    .DESCRIPTION Machine, OS build, PowerShell, sanitizer and CI variables, PATH, MSVC and Windows SDK selection, Git,
    installed Visual Studio and Windows Kits; with Root, the data's systemFiles and instrumentationVariables; with
    -Tooling, the tooling runtime and a clang-format on PATH. Read-only.
    #>
    [CmdletBinding()]
    param([string]$Root = '', [object]$Manifest = $null, [switch]$Tooling)
    $values = [Collections.Generic.List[string]]::new()
    foreach ($value in @([Environment]::MachineName, [Runtime.InteropServices.RuntimeInformation]::OSDescription,
            [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString(), $PSVersionTable.PSVersion.ToString(),
            $env:ASAN_OPTIONS, $env:CI, $env:GITHUB_ACTIONS, $env:PROCESSOR_IDENTIFIER, $env:PATH, $env:VCToolsVersion, $env:WindowsSDKVersion)) {
        $values.Add([string]$value)
    }
    $currentVersion = 'HKLM:/SOFTWARE/Microsoft/Windows NT/CurrentVersion'
    if ($IsWindows -and (Test-Path -LiteralPath $currentVersion)) {
        # The update revision changes with every cumulative update, including one that services only unhashed DLLs.
        $build = Get-ItemProperty -LiteralPath $currentVersion
        $values.Add("os-build=$($build.CurrentBuildNumber).$($build.UBR)")
    }
    if ($Root -and -not $Manifest) { $Manifest = Read-ScopedTestManifest $Root }
    if ($Manifest) {
        foreach ($file in @($Manifest.systemFiles)) {
            if (-not $env:SystemRoot) { continue }
            $path = Join-Path $env:SystemRoot "System32/$file"
            $values.Add("$file=" + $(if ([IO.File]::Exists($path)) { Get-ScopedFileHash $path } else { 'absent' }))
        }
        # Opt-in instrumentation changes test execution; its values count without recording local paths.
        foreach ($name in @($Manifest.instrumentationVariables)) {
            $value = [Environment]::GetEnvironmentVariable($name)
            $values.Add("$name=" + $(if ($null -eq $value) { 'unset' } else { Get-ScopedDigest $value }))
        }
    }
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $values.Add('git=' + $(if ($git) { Get-ScopedGitVersion $git.Source } else { 'absent' }))
    # Tooling fixtures can discover or invoke the installed compiler; an update invalidates their evidence too.
    $vswhere = @(${env:ProgramFiles(x86)}, $env:ProgramFiles | Where-Object { $_ } | ForEach-Object { Join-Path $_ 'Microsoft Visual Studio/Installer/vswhere.exe' } |
            Where-Object { [IO.File]::Exists($_) }) | Select-Object -First 1
    if ($vswhere) {
        $installations = (Invoke-CiProcess -FilePath $vswhere -Arguments @('-all', '-prerelease', '-products', '*', '-format', 'json', '-utf8') -WorkingDirectory ([IO.Path]::GetTempPath())).stdout
        $values.Add($installations)
        foreach ($installation in @(ConvertFrom-Json -InputObject $installations)) {
            $toolset = Join-Path $installation.installationPath 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'
            if ([IO.File]::Exists($toolset)) { $values.Add((Get-ScopedFileHash $toolset)) }
        }
    }
    $kits = 'HKLM:/SOFTWARE/Microsoft/Windows Kits/Installed Roots'
    if ($IsWindows -and (Test-Path -LiteralPath $kits)) { $values.Add((@(Get-ChildItem -LiteralPath $kits | ForEach-Object { $_.Name } | Sort-Object) -join "`n")) }
    if ($Tooling) {
        $values.Add('tooling-runtime=PowerShell')
        $formatter = Get-Command clang-format -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $values.Add('formatter=' + $(if ($formatter) { $formatter.Source + ':' + (Get-ScopedFileHash $formatter.Source) } else { 'absent' }))
    }
    return $values.ToArray()
}

function Get-ScopedEnvironmentIdentity {
    <# .SYNOPSIS Digest of Get-ScopedEnvironmentInputs. Read-only. #>
    [CmdletBinding()]
    param([string]$Root = '', [object]$Manifest = $null, [switch]$Tooling)
    return Get-ScopedDigest ((Get-ScopedEnvironmentInputs -Root $Root -Manifest $Manifest -Tooling:$Tooling) -join "`n")
}

function Get-ScopedToolIdentity {
    <# .SYNOPSIS Digest of the Git binary's bytes and version, which scope discovery and tooling fixtures run. Read-only. #>
    [CmdletBinding()]
    param()
    $command = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { return Get-ScopedDigest 'git:missing' }
    return Get-ScopedDigest ('git:' + (Get-ScopedGitVersion $command.Source))
}

function Get-ScopedInstrumentation {
    <# .SYNOPSIS The data's instrumentationVariables that are set; while any is, no receipt or baseline is written or reused. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Manifest)
    foreach ($name in @($Manifest.instrumentationVariables)) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) { $name }
    }
}

function Get-ScopedRunIdentity {
    <# .SYNOPSIS Identity of native results: checkout, profile, scope, options, compiled source, artifacts and environment. Read-only. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Platform, [Parameter(Mandatory)][string]$Configuration,
        [Parameter(Mandatory)][string]$Scope, [string]$Options = '', [object]$Manifest = $null)
    if (-not $Manifest) { $Manifest = Read-ScopedTestManifest $Root }
    return Get-ScopedDigest (@([IO.Path]::GetFullPath($Root), $Platform, $Configuration, $Scope, $Options,
            (Get-ScopedSourceIdentity -Root $Root -Manifest $Manifest -CompiledOnly), (Get-ScopedArtifactIdentity -Root $Root -Platform $Platform -Configuration $Configuration -Manifest $Manifest),
            (Get-ScopedEnvironmentIdentity -Root $Root -Manifest $Manifest)) -join "`n")
}

function Get-ScopedBuildAttestationKey {
    <# .SYNOPSIS Identity of a canonical product build, for a build.ps1 that attests its own outputs and a test.ps1 -SkipBuild that checks them. Read-only. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Platform, [Parameter(Mandatory)][string]$Configuration,
        [Parameter(Mandatory)][int]$BuildNumber, [bool]$EnableTests = $true, [object]$Manifest = $null)
    if (-not $Manifest) { $Manifest = Read-ScopedTestManifest $Root }
    return Get-ScopedDigest (@('canonical-build-v1', [IO.Path]::GetFullPath($Root), $Platform, $Configuration, $BuildNumber, ('tests-enabled=' + [string]$EnableTests),
            (Get-ScopedSourceIdentity -Root $Root -Manifest $Manifest -CompiledOnly), (Get-ScopedArtifactIdentity -Root $Root -Platform $Platform -Configuration $Configuration -Manifest $Manifest),
            (Get-ScopedEnvironmentIdentity -Root $Root -Manifest $Manifest)) -join "`n")
}

function Test-ScopedReceipt {
    <# .SYNOPSIS Whether a receipt proves a PASSED run with exactly this identity (and, with MaxAgeHours, a recent one). Read-only. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Identity, [ValidateRange(0, 8760)][int]$MaxAgeHours = 0)
    if (-not [IO.File]::Exists($Path)) { return $false }
    try {
        $receipt = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path))
        # PowerShell parses ISO JSON strings into DateTime; keep the canonical UTC spelling.
        $completed = if ($receipt.completedUtc -is [DateTime]) { $receipt.completedUtc.ToUniversalTime().ToString('o') } else { [string]$receipt.completedUtc }
        $age = [DateTime]::UtcNow - [DateTime]::Parse($completed, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        return $receipt.version -eq 1 -and $receipt.outcome -ceq 'PASSED' -and $receipt.identity -ceq $Identity -and
            $age.TotalHours -ge 0 -and ($MaxAgeHours -eq 0 -or $age.TotalHours -lt $MaxAgeHours) -and
            $receipt.digest -ceq (Get-ScopedDigest ($receipt.identity + "`n" + $completed + "`nPASSED"))
    } catch { return $false }
}

function Write-ScopedReceipt {
    <# .SYNOPSIS Atomically writes a PASSED receipt for an identity. Side effect: creates or replaces Path. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Identity)
    $completed = [DateTime]::UtcNow.ToString('o')
    $receipt = [ordered]@{ version = 1; outcome = 'PASSED'; identity = $Identity; completedUtc = $completed
        digest = (Get-ScopedDigest ($Identity + "`n" + $completed + "`nPASSED")) }
    [void][IO.Directory]::CreateDirectory((Split-Path $Path))
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $receipt), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $Path, $true)
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Get-ScopedReportRoot {
    <# .SYNOPSIS The profile's scoped evidence folder: .build/reports/scoped-tests/<platform>-<configuration without spaces>. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Platform, [Parameter(Mandatory)][string]$Configuration)
    return Join-Path $Root ".build/reports/scoped-tests/$Platform-$($Configuration.Replace(' ', ''))"
}

function Assert-ScopedIterationPath([string]$Path, [string]$Root) {
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $prefix = [IO.Path]::GetFullPath((Join-Path $base '.build/reports/scoped-tests')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $cursor = [IO.Path]::GetFullPath($Path)
    if (-not $cursor.StartsWith($prefix, $comparison)) { throw 'The iteration baseline escaped its report folder.' }
    while ($cursor.Length -gt $base.Length) {
        $attributes = $null
        try { $attributes = [IO.File]::GetAttributes($cursor) } catch [IO.FileNotFoundException] { } catch [IO.DirectoryNotFoundException] { }
        if ($null -ne $attributes -and ($attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse iteration baseline paths are unsupported.' }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}

function Get-ScopedIterationDigest([Collections.IDictionary]$State) {
    return Get-ScopedDigest (@($State.version, $State.root, $State.platform, $State.configuration, $State.environment, $State.options,
            $State.completedUtc, $State.artifact, (Get-ScopedMapIdentity $State.source), (Get-ScopedMapIdentity $State.index)) -join "`n")
}

function Read-ScopedIteration {
    <#
    .SYNOPSIS The last successful ordinary affected run of this checkout and profile, or $null.
    .DESCRIPTION Valid only for the same root, profile, environment and tool identity and options, with an intact
    digest, and for 24 hours. Read-only.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Platform,
        [Parameter(Mandatory)][string]$Configuration, [Parameter(Mandatory)][string]$Environment, [Parameter(Mandatory)][AllowEmptyString()][string]$Options)
    Assert-ScopedIterationPath $Path $Root
    if (-not [IO.File]::Exists($Path)) { return $null }
    try {
        if (([IO.FileInfo]::new($Path)).Length -gt 64MB) { return $null }
        $state = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -AsHashtable
        if ($state.completedUtc -is [DateTime]) { $state.completedUtc = $state.completedUtc.ToUniversalTime().ToString('o') }
        if ($state.version -ne 2 -or $state.root -cne [IO.Path]::GetFullPath($Root) -or $state.platform -cne $Platform -or
            $state.configuration -cne $Configuration -or $state.environment -cne $Environment -or $state.options -cne $Options -or
            $state.source -isnot [Collections.IDictionary] -or $state.index -isnot [Collections.IDictionary] -or $state.artifact -isnot [string] -or
            $state.digest -cne (Get-ScopedIterationDigest $state)) { return $null }
        $age = [DateTime]::UtcNow - [DateTime]::Parse($state.completedUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        if ($age.TotalHours -lt 0 -or $age.TotalHours -ge 24) { return $null }
        return $state
    } catch { return $null }
}

function Write-ScopedIteration {
    <# .SYNOPSIS Atomically records a successful ordinary affected run as the next run's baseline. Side effect: writes Path. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Platform,
        [Parameter(Mandatory)][string]$Configuration, [Parameter(Mandatory)][string]$Environment, [Parameter(Mandatory)][AllowEmptyString()][string]$Options,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$Source, [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$Index,
        [Parameter(Mandatory)][string]$Artifact)
    Assert-ScopedIterationPath $Path $Root
    $state = [ordered]@{ version = 2; root = [IO.Path]::GetFullPath($Root); platform = $Platform; configuration = $Configuration
        environment = $Environment; options = $Options; completedUtc = [DateTime]::UtcNow.ToString('o'); artifact = $Artifact; source = $Source; index = $Index }
    $state['digest'] = Get-ScopedIterationDigest $state
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    Assert-ScopedIterationPath $Path $Root
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $state -Depth 8), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $Path, $true)
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Remove-ScopedIteration {
    <# .SYNOPSIS Revokes the iteration baseline before any build or test, so a failed run never leaves one. Side effect: deletes Path. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
    Assert-ScopedIterationPath $Path $Root
    if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
}

function Get-ScopedLeaseVariable { return 'CI_SCOPED_TESTING_LEASE' }

function Test-ScopedLeaseHandoff([string]$Key) {
    # A child process of the lease owner (build.ps1, test.ps1 or a scope command started by the runner) re-enters
    # the owner's lease: the handoff names the key and an ancestor process by id and start time.
    $value = [Environment]::GetEnvironmentVariable((Get-ScopedLeaseVariable))
    if (-not $value) { return $false }
    $parts = $value.Split(';')
    $ownerId = 0
    if ($parts.Count -ne 3 -or $parts[0] -cne $Key -or -not [int]::TryParse($parts[1], [ref]$ownerId) -or
        $ownerId -le 0 -or -not $parts[2]) { return $false }
    $process = Get-Process -Id $PID
    for ($depth = 0; $depth -lt 32; $depth++) {
        try {
            $parent = $process.Parent
            if (-not $parent) { return $false }
            if ($parent.Id -eq $ownerId) { return (Get-CiProcessCreationIdentity -ProcessId $ownerId) -ceq $parts[2] }
        } catch { return $false }
        $process = $parent
    }
    return $false
}

function Enter-ScopedProfileLease {
    <#
    .SYNOPSIS Takes the fail-fast lease of one checkout output folder and profile.
    .DESCRIPTION Refuses at once when another operation owns it. Re-entrant on the owning thread and in the owner's
    child processes, which inherit the handoff variable CI_SCOPED_TESTING_LEASE. Side effects: a named mutex and that
    variable in this process until Exit-ScopedProfileLease.
    .OUTPUTS The lease to pass to Exit-ScopedProfileLease.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][ValidateSet('x64', 'ARM64')][string]$Platform,
        [Parameter(Mandatory)][ValidateSet('Debug', 'Release', 'ASan Debug')][string]$Configuration, [string]$OutputRoot = '')
    if (-not $OutputRoot) { $OutputRoot = Join-Path $Root '.build' }
    $identity = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\', '/')
    if ($IsWindows) { $identity = $identity.ToUpperInvariant() }
    $key = Get-ScopedDigest (@($identity, $Platform, $Configuration) -join "`n")
    $processIdentity = Get-CiProcessCreationIdentity -ProcessId $PID
    $mutex = [Threading.Mutex]::new($false, "Ci.ScopedProfile.$key")
    $owned = $false
    try {
        try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    } catch { $mutex.Dispose(); throw }
    if (-not $owned) {
        $mutex.Dispose()
        if (Test-ScopedLeaseHandoff $key) { return [pscustomobject]@{ Key = $key; Mutex = $null; Previous = $null; Nested = $true } }
        throw "Another test operation owns this checkout and profile ($Platform $Configuration). Retry when it completes."
    }
    $previous = [Environment]::GetEnvironmentVariable((Get-ScopedLeaseVariable))
    [Environment]::SetEnvironmentVariable((Get-ScopedLeaseVariable), "$key;$PID;$processIdentity")
    return [pscustomobject]@{ Key = $key; Mutex = $mutex; Previous = $previous; Nested = $false }
}

function Exit-ScopedProfileLease {
    <# .SYNOPSIS Releases a lease from Enter-ScopedProfileLease; a nested or absent lease is left to its owner. #>
    [CmdletBinding()]
    param([AllowNull()][object]$Lease)
    if ($null -eq $Lease -or $Lease.Nested) { return }
    try { $Lease.Mutex.ReleaseMutex() }
    finally {
        $Lease.Mutex.Dispose()
        [Environment]::SetEnvironmentVariable((Get-ScopedLeaseVariable), $Lease.Previous)
    }
}

Export-ModuleMember -Function Get-ScopedComparisonProblem, Get-ScopedChangedPaths, Get-ScopedBuildNumber, Assert-ScopedRuntimePlatform,
    Test-ScopedPattern, Read-ScopedTestManifest, Assert-ScopedTestNames, Get-ScopedProjectRules, Get-ScopedTestPlan,
    Get-ScopedInteractiveObligations, Get-ScopedDigest, Get-ScopedSourceMap, Get-ScopedMapIdentity, Get-ScopedIndexMap, Get-ScopedMapDelta,
    Get-ScopedPendingIndexDelta, Get-ScopedSourceIdentity, Get-ScopedArtifactIdentity, Get-ScopedEnvironmentInputs, Get-ScopedEnvironmentIdentity,
    Get-ScopedToolIdentity, Get-ScopedInstrumentation, Get-ScopedRunIdentity, Get-ScopedBuildAttestationKey, Test-ScopedReceipt, Write-ScopedReceipt,
    Get-ScopedReportRoot, Read-ScopedIteration, Write-ScopedIteration, Remove-ScopedIteration, Enter-ScopedProfileLease, Exit-ScopedProfileLease
