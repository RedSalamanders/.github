# Shared agent-guidance validator, contract version 1 (Specs/ProjectCommands.md, "Agent guidance", rules G1 to G13): the
# skill grammar, strict reading, Markdown fences and references, reparse points, harness files, the scoped-guidance
# inventory, the skill index and instruction pointers, PowerShell examples and the plan indexes. Products run it through
# their Tools/Test-AgentGuidance.ps1 shim. Read-only and local to the given root (and, for a documentation project, the
# folder of its sibling repositories): it never writes, fetches, evaluates YAML or Markdown, or runs a referenced script.
Set-StrictMode -Version Latest
# A module function sees this module's preference, not its caller's, so a read failure is terminating here and becomes a
# reported problem instead of a silently skipped file.
$ErrorActionPreference = 'Stop'

$script:FrontMatterKeys = @('name', 'description', 'license', 'allowed-tools', 'metadata')
$script:Pointers = @('CLAUDE.md', '.github/copilot-instructions.md')
$script:RootGuidanceMaximumBytes = 24000
$script:CommonParameterNames = $null

#region Reading and Markdown structure (G2, G3)

function Get-GuidanceFailureDetail([Management.Automation.ErrorRecord] $ErrorRecord) {
    # PowerShell wraps a .NET method failure; the inner exception holds the useful sentence.
    $inner = $ErrorRecord.Exception.InnerException
    if ($inner) { return $inner.Message }
    return $ErrorRecord.Exception.Message
}

function Read-GuidanceText([string] $Path, [switch] $RejectByteOrderMark, [int] $MaximumBytes) {
    # G2: strict UTF-8 text of one file. A failure throws a message that reads after "<file>: ". UTF-16/32 text and NUL
    # bytes are always refused, because .NET would otherwise decode a UTF-16 file without a word. A UTF-8 byte order mark
    # is dropped unless RejectByteOrderMark is set: SKILL.md front matter must start at byte 0.
    try { $bytes = [IO.File]::ReadAllBytes($Path) }
    catch [Management.Automation.RuntimeException] { throw "cannot be read: $(Get-GuidanceFailureDetail $_)" }
    if ($MaximumBytes -gt 0 -and $bytes.Length -gt $MaximumBytes) {
        throw "exceeds the $MaximumBytes-byte root guidance limit ($($bytes.Length) bytes)"
    }
    $head = [BitConverter]::ToString($bytes, 0, [Math]::Min(4, $bytes.Length))
    if ($head -match '^(?:FF-FE|FE-FF|00-00-FE-FF)') { throw 'expected UTF-8 but found a UTF-16 or UTF-32 byte order mark; save the file as UTF-8' }
    $start = 0
    if ($head.StartsWith('EF-BB-BF', [StringComparison]::Ordinal)) {
        if ($RejectByteOrderMark) { throw 'expected UTF-8 without a byte order mark; remove the UTF-8 byte order mark' }
        $start = 3
    }
    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { throw 'expected UTF-8 text but found NUL bytes (UTF-16 without a byte order mark, or binary data)' }
    try { return [Text.UTF8Encoding]::new($false, $true).GetString($bytes, $start, $bytes.Length - $start) }
    catch [Management.Automation.RuntimeException] { throw "expected UTF-8 but found invalid bytes: $(Get-GuidanceFailureDetail $_)" }
}

function Get-GuidanceFence([AllowEmptyString()][string] $Text) {
    # The fenced-code map of Markdown text: Lines, Hidden (a fence marker or fenced content), Info (the info string of the
    # fence that holds each content line) and Unclosed (one-based Line and Token of each opening fence no marker closes). A
    # fence closes at a marker of the same character, at least as long and with nothing after it. Markers use zero to three
    # leading spaces (optionally after a list marker), so indented code never opens or closes one, and a backtick fence's
    # info string holds no backtick, so a line-leading code span is prose. G3: an unclosed fence hides only its own line,
    # so the text after it stays prose and keeps being checked.
    $lines = $Text.Replace("`r`n", "`n") -split "`n"
    $markers = @(foreach ($line in $lines) { [regex]::Match($line, '^ {0,3}(?:(?:[-+*]|\d+[.)])[ \t]+)?(?<fence>`{3,}|~{3,})(?<rest>.*)$') })
    $hidden = [bool[]]::new($lines.Length)
    $info = [string[]]::new($lines.Length)
    $unclosed = [Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $opening = $markers[$i]
        if (-not $opening.Success) { continue }
        $token = $opening.Groups['fence'].Value
        if ($token[0] -ceq '`' -and $opening.Groups['rest'].Value.Contains('`')) { continue }
        $hidden[$i] = $true
        $closing = -1
        for ($j = $i + 1; $j -lt $lines.Length -and $closing -lt 0; $j++) {
            $candidate = $markers[$j]
            if ($candidate.Success -and $candidate.Groups['fence'].Value[0] -ceq $token[0] -and
                $candidate.Groups['fence'].Value.Length -ge $token.Length -and -not $candidate.Groups['rest'].Value.Trim()) { $closing = $j }
        }
        if ($closing -lt 0) { $unclosed.Add([pscustomobject]@{ Line = $i + 1; Token = $token }); continue }
        for ($j = $i; $j -le $closing; $j++) { $hidden[$j] = $true }
        for ($j = $i + 1; $j -lt $closing; $j++) { $info[$j] = $opening.Groups['rest'].Value.Trim() }
        $i = $closing
    }
    return [pscustomobject]@{ Lines = $lines; Hidden = $hidden; Info = $info; Unclosed = $unclosed.ToArray() }
}

function Hide-GuidanceCodeSpan([string] $Block) {
    # Blank every inline code span of one block, keeping each newline. A backtick run opens a span that the next run of the
    # same length closes; an odd number of backslashes before a backtick escapes it, and an unmatched run is prose.
    $characters = $Block.ToCharArray()
    for ($i = 0; $i -lt $characters.Length; $i++) {
        if ($characters[$i] -ne '`') { continue }
        $slashes = 0
        for ($j = $i - 1; $j -ge 0 -and $characters[$j] -eq '\'; $j--) { $slashes++ }
        if ($slashes % 2) { continue }
        $length = 1
        while ($i + $length -lt $characters.Length -and $characters[$i + $length] -eq '`') { $length++ }
        $closing = -1
        for ($j = $i + $length; $j -lt $characters.Length; $j++) {
            if ($characters[$j] -ne '`') { continue }
            $run = 1
            while ($j + $run -lt $characters.Length -and $characters[$j + $run] -eq '`') { $run++ }
            if ($run -eq $length) { $closing = $j + $run; break }
            $j += $run - 1
        }
        if ($closing -ge 0) {
            for ($j = $i; $j -lt $closing; $j++) { if ($characters[$j] -ne "`n") { $characters[$j] = ' ' } }
            $i = $closing - 1
        } else { $i += $length - 1 }
    }
    return [string]::new($characters)
}

function Get-GuidanceProse([AllowEmptyString()][string] $Text) {
    # The text with fenced code and inline code spans replaced by spaces, so every line keeps its number and length, plus
    # the Unclosed fences and the Fence map of Get-GuidanceFence. A code span pairs only inside one block: a blank line,
    # list item, heading, setext underline, thematic break, table row or block-quote edge ends the search, so a stray
    # backtick cannot hide the links after it. This is a bounded block scan, not a Markdown evaluator.
    $fence = Get-GuidanceFence $Text
    # A copy: the fence map keeps the original lines for the PowerShell example check (G11).
    $lines = [string[]]$fence.Lines.Clone()
    for ($i = 0; $i -lt $lines.Length; $i++) { if ($fence.Hidden[$i]) { $lines[$i] = ' ' * $lines[$i].Length } }
    $blockStart = -1
    $afterSingleLine = $false
    $afterQuote = $false
    for ($i = 0; $i -le $lines.Length; $i++) {
        $line = if ($i -lt $lines.Length) { $lines[$i] } else { '' }
        $boundary = -not $line.Trim()
        $singleLine = $false
        $quote = $false
        if (-not $boundary) {
            # One-line blocks: ATX heading, setext underline, thematic break and table row. A list item starts a block too.
            $singleLine = $line -cmatch '^ {0,3}(?:#{1,6}(?:[ \t]|$)|=+[ \t]*$|(?:\*[ \t]*){3,}$|(?:-[ \t]*){3,}$|(?:_[ \t]*){3,}$)|^[ \t]*\|'
            $quote = $line -cmatch '^ {0,3}>'
            $boundary = $singleLine -or $afterSingleLine -or $quote -ne $afterQuote -or $line -cmatch '^[ \t]*(?:[-+*]|\d{1,9}[.)])(?:[ \t]|$)'
        }
        if ($boundary -and $blockStart -ge 0) {
            $block = $lines[$blockStart..($i - 1)] -join "`n"
            if ($block.Contains('`')) {
                $masked = (Hide-GuidanceCodeSpan $block) -split "`n"
                for ($j = 0; $j -lt $masked.Length; $j++) { $lines[$blockStart + $j] = $masked[$j] }
            }
            $blockStart = -1
        }
        if ($line.Trim() -and $blockStart -lt 0) { $blockStart = $i }
        $afterSingleLine = $singleLine
        $afterQuote = $quote
    }
    return [pscustomobject]@{ Text = $lines -join "`n"; Unclosed = $fence.Unclosed; Fence = $fence }
}

function Read-GuidanceDestination([string] $Text, [int] $Start) {
    # One link destination from Start: <angle> form, or a run with balanced parentheses and Markdown punctuation escapes.
    $position = $Start
    while ($position -lt $Text.Length -and [char]::IsWhiteSpace($Text[$position])) { $position++ }
    $angle = $position -lt $Text.Length -and $Text[$position] -eq '<'
    if ($angle) { $position++ }
    $value = [Text.StringBuilder]::new()
    $depth = 0
    while ($position -lt $Text.Length) {
        $character = $Text[$position]
        if ($character -eq '\' -and $position + 1 -lt $Text.Length -and $Text[$position + 1] -in @('\', '(', ')', '[', ']', '<', '>')) {
            [void]$value.Append($Text[$position + 1]); $position += 2; continue
        }
        if ($angle) {
            if ($character -eq '>') { return [pscustomobject]@{ Target = $value.ToString(); End = $position + 1 } }
            if ($character -eq "`n") { return $null }
        } else {
            if ([char]::IsWhiteSpace($character) -or ($character -eq ')' -and $depth -eq 0)) { break }
            if ($character -eq '(') { $depth++ }
            elseif ($character -eq ')') { $depth-- }
        }
        [void]$value.Append($character); $position++
    }
    if ($angle -or $depth -ne 0) { return $null }
    return [pscustomobject]@{ Target = $value.ToString(); End = $position }
}

function Get-GuidanceLink([string] $Text) {
    # G6: bounded Markdown parsing of text that Get-GuidanceProse already stripped of fenced and code-span content. Reads
    # inline destinations and reference definitions (also one continued on the next line); a footnote definition is text,
    # not a reference definition. Emits Target and one-based Line. Never evaluates text.
    $lines = $Text -split "`n"
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        $definition = [regex]::Match($line, '^[ \t]{0,3}\[(?!\^)[^\]]+\]:[ \t]*')
        if ($definition.Success) {
            $destination = Read-GuidanceDestination $line $definition.Length
            if (($null -eq $destination -or -not $destination.Target) -and $lineIndex + 1 -lt $lines.Count -and $lines[$lineIndex + 1].Trim()) {
                $destination = Read-GuidanceDestination $lines[$lineIndex + 1] 0
            }
            if ($null -ne $destination -and $destination.Target) { [pscustomobject]@{ Target = $destination.Target; Line = $lineIndex + 1 } }
        }
    }
    $brackets = [Collections.Generic.Stack[int]]::new()
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $character = $Text[$i]
        if ($character -eq '\' -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -in @('\', '[', ']')) { $i++; continue }
        if ($character -eq '[') { $brackets.Push($i); continue }
        if ($character -ne ']' -or -not $brackets.Count) { continue }
        $start = $brackets.Pop()
        if ($i + 1 -ge $Text.Length -or $Text[$i + 1] -ne '(') { continue }
        $destination = Read-GuidanceDestination $Text ($i + 2)
        if ($null -eq $destination -or -not $destination.Target) { continue }
        $end = $destination.End
        while ($end -lt $Text.Length -and [char]::IsWhiteSpace($Text[$end])) { $end++ }
        if ($end -lt $Text.Length -and $Text[$end] -in @('"', "'", '(')) {
            $quote = if ($Text[$end] -eq '(') { ')' } else { $Text[$end] }; $end++
            while ($end -lt $Text.Length -and $Text[$end] -ne $quote) { if ($Text[$end] -eq '\') { $end++ }; $end++ }
            $end++
            while ($end -lt $Text.Length -and [char]::IsWhiteSpace($Text[$end])) { $end++ }
        }
        if ($end -lt $Text.Length -and $Text[$end] -eq ')') {
            [pscustomobject]@{ Target = $destination.Target; Line = ($Text.Substring(0, $start) -split "`n").Length }
            $i = $end
        }
    }
}

#endregion
#region Skill grammar (G1, G4)

function ConvertFrom-SkillScalar([AllowEmptyString()][string] $Value) {
    if (-not $Value) { return $null }
    if ($Value.StartsWith("'")) {
        $match = [regex]::Match($Value, "^'(?<text>(?:[^']|'')*)'(?: +#.*)?$")
        if (-not $match.Success) { throw 'invalid single-quoted scalar' }
        return $match.Groups['text'].Value.Replace("''", "'")
    }
    if ($Value.StartsWith('"')) {
        $match = [regex]::Match($Value, '^(?<quoted>"(?:[^"\\]|\\.)*")(?: +#.*)?$')
        if (-not $match.Success) { throw 'invalid double-quoted scalar' }
        # JsonDocument preserves strings on every supported PowerShell 7 runtime, including ISO dates.
        $document = [Text.Json.JsonDocument]::Parse($match.Groups['quoted'].Value)
        try { return $document.RootElement.GetString() } finally { $document.Dispose() }
    }
    $plain = [regex]::Replace($Value, ' +#.*$', '')
    if ($plain -match '^[-?:,\[\]{}#&*!|>''"%@`]' -or $plain.Contains(': ') -or $plain.EndsWith(':') -or $plain -match '[\x00-\x1f]') {
        throw 'unsupported plain scalar; quote the value'
    }
    # YAML 1.1 typed plain values are not strings, so a name or description written that way is refused.
    if ($plain -cmatch '^(?:~|null|Null|NULL|yes|Yes|YES|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF|=|<<)$' -or
        $plain -cmatch '^[-+]?(?:[0-9][0-9_:]*(?:\.[0-9_]*)?(?:[eE][-+]?[0-9]+)?|\.[0-9_]+(?:[eE][-+]?[0-9]+)?|0b[01_]+|0x[0-9a-fA-F_]+|\.(?:inf|Inf|INF|nan|NaN|NAN))$' -or
        $plain -cmatch '^(?:[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?:[Tt]|[ \t]+)[0-9]{1,2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]*)?(?:[ \t]*(?:Z|[-+][0-9]{1,2}(?::[0-9]{2})?))?)$') {
        return [pscustomobject]@{ NonStringScalar = $plain }
    }
    return $plain
}

function ConvertFrom-SkillMetadata([string] $Text) {
    # G1: the front matter subset. Top-level keys from the allowlist, one-level metadata, literal and folded block scalars.
    # Tags, anchors, aliases, flow collections, sequences and deeper mappings are refused, never evaluated.
    $values = [ordered]@{}
    $lines = $Text -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
        $match = [regex]::Match($line, '^(?<key>[a-z][a-z-]*):(?: +(?<value>.*?))? *$')
        if (-not $match.Success) { throw "unsupported mapping at line $($i + 1)" }
        $key = $match.Groups['key'].Value
        if ($key -cnotin $script:FrontMatterKeys) { throw "unsupported front matter key '$key'" }
        if ($values.Contains($key)) { throw "duplicate front matter key '$key'" }
        $raw = $match.Groups['value'].Value
        if ($key -ceq 'metadata') {
            if ($raw -and -not $raw.StartsWith('#')) { throw 'metadata requires an indented scalar mapping' }
            $nested = [ordered]@{}
            while ($i + 1 -lt $lines.Count -and ($lines[$i + 1] -match '^ ' -or -not $lines[$i + 1].Trim())) {
                $i++
                if (-not $lines[$i].Trim() -or $lines[$i].TrimStart().StartsWith('#')) { continue }
                $item = [regex]::Match($lines[$i], '^  (?<key>[A-Za-z_][A-Za-z0-9_-]*): +(?<value>.*?) *$')
                if (-not $item.Success) { throw 'metadata supports two-space-indented scalar values only' }
                $nestedKey = $item.Groups['key'].Value
                if ($nested.Contains($nestedKey)) { throw "duplicate metadata key '$nestedKey'" }
                $nested[$nestedKey] = ConvertFrom-SkillScalar $item.Groups['value'].Value
            }
            $values[$key] = $nested
        } elseif ($raw -match '^(?<style>[|>])(?<chomp>[-+]?)(?: +#.*)?$') {
            $style = $Matches.style
            $chomp = $Matches.chomp
            $block = [Collections.Generic.List[string]]::new()
            while ($i + 1 -lt $lines.Count -and ($lines[$i + 1] -match '^ ' -or -not $lines[$i + 1].Trim())) {
                $i++
                if ($lines[$i] -match '^  (?<content>.*)$') { $block.Add($Matches.content) }
                elseif (-not $lines[$i].Trim()) { $block.Add('') }
                else { throw 'block scalars require two-space indentation' }
            }
            # Fold only adjacent ordinary lines; blank and more-indented lines keep their breaks.
            $builder = [Text.StringBuilder]::new()
            for ($j = 0; $j -lt $block.Count; $j++) {
                [void]$builder.Append($block[$j])
                $fold = $style -ceq '>' -and $j + 1 -lt $block.Count -and $block[$j] -and $block[$j + 1] -and
                    -not $block[$j].StartsWith(' ') -and -not $block[$j + 1].StartsWith(' ')
                # One empty line between ordinary paragraphs stands for one newline. Breaks around more-indented text and
                # leading or trailing blank lines are kept.
                $paragraphBreak = $false
                if ($style -ceq '>' -and $block[$j] -and -not $block[$j].StartsWith(' ') -and $j + 1 -lt $block.Count -and -not $block[$j + 1]) {
                    $next = $j + 1
                    while ($next -lt $block.Count -and -not $block[$next]) { $next++ }
                    $paragraphBreak = $next -lt $block.Count -and -not $block[$next].StartsWith(' ')
                }
                [void]$builder.Append($(if ($fold) { ' ' } elseif ($paragraphBreak) { '' } else { "`n" }))
            }
            $value = $builder.ToString()
            if ($chomp -cne '+') { $value = $value.TrimEnd("`n") + $(if ($chomp -ceq '-' -or -not $value) { '' } else { "`n" }) }
            $values[$key] = $value
        } else {
            $values[$key] = ConvertFrom-SkillScalar $raw
        }
    }
    return $values
}

function New-SkillProblem([string] $Rule, [string] $Message, [int] $Line = 0) {
    return [pscustomobject]@{ Rule = $Rule; Message = $Message; Line = $Line }
}

function Get-SkillProblemList([string] $FolderName, [AllowNull()][AllowEmptyString()][string] $Text, [switch] $NoFence) {
    # Every problem of one SKILL.md text, each with its rule and, for an unclosed fence, its line in the file. NoFence leaves
    # out the fences, which the repository check reports for every scanned Markdown file (G3).
    $problems = [Collections.Generic.List[object]]::new()
    if (-not $Text) { $problems.Add((New-SkillProblem 'G1' 'missing SKILL.md or empty file')); return , $problems.ToArray() }
    $normalized = $Text.Replace("`r`n", "`n")
    $match = [regex]::Match($normalized, '\A---\n(?<metadata>.*?)\n---(?:\n|$)(?<body>[\s\S]*)\z', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { $problems.Add((New-SkillProblem 'G1' 'missing YAML front matter')); return , $problems.ToArray() }
    try { $metadata = ConvertFrom-SkillMetadata $match.Groups['metadata'].Value }
    catch [Management.Automation.RuntimeException] { $problems.Add((New-SkillProblem 'G1' "invalid YAML subset: $($_.Exception.Message)")); return , $problems.ToArray() }
    catch [ArgumentException] { $problems.Add((New-SkillProblem 'G1' "invalid YAML subset: $($_.Exception.Message)")); return , $problems.ToArray() }
    $name = if ($metadata.Contains('name')) { $metadata['name'] } else { $null }
    if ($name -isnot [string] -or $name -cne $FolderName -or $name.Length -gt 64 -or $name -cnotmatch '\A[a-z0-9]+(?:-[a-z0-9]+)*\z') {
        $problems.Add((New-SkillProblem 'G1' 'name must match the folder and use lowercase hyphen-separated words'))
    }
    $description = if ($metadata.Contains('description')) { $metadata['description'] } else { $null }
    if ($description -isnot [string] -or -not $description.Trim() -or $description.Contains('<') -or $description.Contains('>')) {
        $problems.Add((New-SkillProblem 'G1' 'invalid description'))
    } else {
        # The limit counts Unicode code points, not UTF-16 code units.
        $length = 0
        foreach ($rune in $description.EnumerateRunes()) { $length++ }
        if ($length -gt 1024) { $problems.Add((New-SkillProblem 'G1' 'invalid description')) }
        elseif ($description.TrimStart().StartsWith('[TODO:', [StringComparison]::Ordinal)) { $problems.Add((New-SkillProblem 'G1' 'unfinished description')) }
        # G4: the description says when an agent should load the skill, in these exact words (String.Contains is ordinal).
        if (-not $description.Contains('Use when')) {
            $problems.Add((New-SkillProblem 'G4' "description does not say when to use the skill; add a sentence that starts with 'Use when'"))
        }
    }
    $body = $match.Groups['body'].Value
    if (-not $body.Trim()) { $problems.Add((New-SkillProblem 'G1' 'empty skill instructions')); return , $problems.ToArray() }
    # Fenced examples may hold placeholders; an unclosed fence is reported and the text after it is still checked.
    $fence = Get-GuidanceFence $body
    if (-not $NoFence) {
        $frontMatterLines = $normalized.Substring(0, $match.Groups['body'].Index).Split("`n").Length - 1
        foreach ($open in $fence.Unclosed) { $problems.Add((New-SkillProblem 'G3' "unclosed code fence (opened with $($open.Token))" ($frontMatterLines + $open.Line))) }
    }
    for ($i = 0; $i -lt $fence.Lines.Length; $i++) {
        if (-not $fence.Hidden[$i] -and $fence.Lines[$i] -cmatch '\A[ ]{0,3}\[TODO:[^\n]*\][ \t]*\z') { $problems.Add((New-SkillProblem 'G1' 'unfinished instructions')); break }
    }
    return , $problems.ToArray()
}

function Get-CiSkillProblem {
    <#
    .SYNOPSIS
        Returns the problems of one SKILL.md text as one string, or $null when it is valid (G1, G3 and G4).
    .DESCRIPTION
        The shared skill grammar of RedHome, RedXe and RedPrism: front matter at byte 0 with the keys name, description,
        license, allowed-tools and one-level metadata; block scalars; YAML 1.1 typed plain values are not strings. The name
        equals the folder, has at most 64 characters and uses lowercase hyphen-separated words. The description has at
        most 1024 code points, no angle brackets, does not start with [TODO: and contains the case-sensitive words
        "Use when". The instructions are not empty and hold no [TODO: ...] line outside fenced code; an unclosed fence is
        reported as SKILL.md:<line>. Several problems are joined with "; ". Pure: reads and writes nothing.
    .PARAMETER FolderName
        Name of the skill folder, which the name field must equal.
    .PARAMETER Text
        Text of the SKILL.md file; $null or empty for a missing or empty file.
    .OUTPUTS
        One problem string, or $null.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $FolderName, [AllowNull()][AllowEmptyString()][string] $Text)
    $list = Get-SkillProblemList $FolderName $Text
    $messages = @(foreach ($problem in $list) { if ($problem.Line) { "SKILL.md:$($problem.Line): $($problem.Message)" } else { $problem.Message } })
    if ($messages.Count) { return $messages -join '; ' }
    return $null
}

#endregion
#region Repository paths (G6, G7, G13)

function Test-GuidanceOutside([string] $Relative) {
    # A path relative to a base that leaves it.
    return [IO.Path]::IsPathRooted($Relative) -or $Relative -eq '..' -or $Relative.StartsWith('../', [StringComparison]::Ordinal) -or
        $Relative.StartsWith('..\', [StringComparison]::Ordinal)
}

function Test-GuidanceEntry([string] $Path) { return [IO.File]::Exists($Path) -or [IO.Directory]::Exists($Path) }

function Get-GuidanceReparsePoint([string] $Path, [string] $Root) {
    # G7: the first reparse point from the root down to Path, as a root-relative path ('.' for the root), or $null. Only
    # the root and what is below it count: a junction above the root, where a checkout is kept, is accepted.
    $relative = [IO.Path]::GetRelativePath($Root, $Path)
    if (Test-GuidanceOutside $relative) { return $null }
    $component = $Root
    foreach ($segment in @('.') + @($relative -split '[\\/]' | Where-Object { $_ -and $_ -ne '.' })) {
        if ($segment -ne '.') { $component = [IO.Path]::Combine($component, $segment) }
        if (-not (Test-GuidanceEntry $component)) { return $null }
        if ([IO.File]::GetAttributes($component) -band [IO.FileAttributes]::ReparsePoint) { return [IO.Path]::GetRelativePath($Root, $component).Replace('\', '/') }
    }
    return $null
}

function Get-GuidanceCaseMismatch([string] $Resolved, [string] $Root, [hashtable] $Listings) {
    # A case-insensitive host opens a link that GitHub cannot. Compares each existing component below Root, ordinally, with
    # the spelling on disk: returns the on-disk relative path when one differs, otherwise $null. Listings caches folders.
    $current = $Root
    $actual = [Collections.Generic.List[string]]::new()
    $differs = $false
    foreach ($segment in @([IO.Path]::GetRelativePath($Root, $Resolved) -split '[\\/]' | Where-Object { $_ -and $_ -ne '.' })) {
        if (-not $Listings.ContainsKey($current)) {
            $names = [string[]]@([IO.Directory]::EnumerateFileSystemEntries($current) | ForEach-Object { [IO.Path]::GetFileName($_) })
            $Listings[$current] = [Collections.Generic.HashSet[string]]::new($names, [StringComparer]::Ordinal)
        }
        $name = $segment
        if (-not $Listings[$current].Contains($segment)) {
            $name = $Listings[$current] | Where-Object { $_ -ieq $segment } | Select-Object -First 1
            if (-not $name) { return $null }
            $differs = $true
        }
        $actual.Add($name)
        $current = [IO.Path]::Combine($current, $name)
    }
    if ($differs) { return $actual -join '/' }
    return $null
}

function Resolve-GuidanceReference([string] $Target, [string] $Directory) {
    # G6: the local path a Markdown destination names, relative to the folder of its file, or $null for a fragment, a
    # query-only link, a protocol-relative URL or another scheme. A fragment and then a query end the path (GitHub's
    # ?plain=1) and the rest is percent-decoded; a file URI names its LocalPath. Path is the decoded target as written.
    if ($Target.StartsWith('#') -or $Target.StartsWith('//')) { return $null }
    if ($Target -match '^[A-Za-z][A-Za-z0-9+.-]*:' -and -not [IO.Path]::IsPathRooted($Target)) {
        if (-not $Target.StartsWith('file:', [StringComparison]::OrdinalIgnoreCase)) { return $null }
        try { $path = ([Uri]$Target).LocalPath }
        catch [Management.Automation.RuntimeException] { return [pscustomobject]@{ Path = $Target; Resolved = $null; Invalid = "invalid file URI: $Target" } }
    } else {
        $path = [Uri]::UnescapeDataString($Target.Split('#', 2)[0].Split('?', 2)[0])
    }
    if (-not $path) { return $null }
    try { $resolved = [IO.Path]::GetFullPath([IO.Path]::Combine($Directory, $path)) }
    catch [Management.Automation.RuntimeException] { return [pscustomobject]@{ Path = $path; Resolved = $null; Invalid = "invalid local reference: $Target" } }
    return [pscustomobject]@{ Path = $path; Resolved = $resolved; Invalid = $null }
}

#endregion
#region Repository checks

function ConvertTo-GuidanceLabel([pscustomobject] $Context, [string] $Path) {
    return [IO.Path]::GetRelativePath($Context.Root, $Path).Replace('\', '/')
}

function Add-GuidanceProblem([pscustomobject] $Context, [string] $Location, [string] $Message, [string] $Rule) {
    # One line per problem: where, what, and the rule of Specs/ProjectCommands.md. The same defect found twice is kept once.
    $line = "${Location}: $Message ($Rule)"
    if ($Context.Seen.Add($line)) { $Context.Problems.Add($line) }
}

function Add-GuidanceReparseProblem([pscustomobject] $Context, [string] $Relative) {
    Add-GuidanceProblem $Context $Relative 'is a reparse point; agent guidance is never read through a link' 'G7'
}

function Read-GuidanceFile([pscustomobject] $Context, [string] $Path) {
    # Each file is read once; one that cannot be read is reported once (G2), and its text is never another file's.
    $Path = [IO.Path]::GetFullPath($Path)
    if ($Context.Texts.ContainsKey($Path)) { return $Context.Texts[$Path] }
    $text = $null
    $maximum = if ($Path -ceq (Join-Path $Context.Root 'AGENTS.md')) { $script:RootGuidanceMaximumBytes } else { 0 }
    try {
        $text = Read-GuidanceText $Path -MaximumBytes $maximum -RejectByteOrderMark:([IO.Path]::GetFileName($Path) -ceq 'SKILL.md')
    }
    catch [Management.Automation.RuntimeException] { Add-GuidanceProblem $Context (ConvertTo-GuidanceLabel $Context $Path) $_.Exception.Message 'G2' }
    $Context.Texts[$Path] = $text
    return $text
}

function Get-GuidanceTree([pscustomobject] $Context) {
    # One walk of the repository: every AGENTS.md (G9), the skill folders (G5) and the Markdown of .agents/skills (G6).
    # It does not enter .git, .build, a nested checkout or a reparse point. A reparse point under .agents, or one named
    # AGENTS.md or SKILL.md, is refused (G7); a SKILL.md outside a skill folder (G5) and agents/openai.yaml (G8) too.
    $tree = [pscustomobject]@{
        Agents = [Collections.Generic.List[string]]::new(); Skills = [Collections.Generic.List[string]]::new()
        Markdown = [Collections.Generic.List[string]]::new()
    }
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($Context.Root)
    while ($pending.Count) {
        $directory = $pending.Pop()
        try { $entries = [IO.FileSystemInfo[]]@([IO.DirectoryInfo]::new($directory).EnumerateFileSystemInfos()) }
        catch [Management.Automation.RuntimeException] {
            Add-GuidanceProblem $Context (ConvertTo-GuidanceLabel $Context $directory) "cannot be listed: $(Get-GuidanceFailureDetail $_)" 'G2'
            continue
        }
        # Ordinal order, and folders pushed last-first, so problems come out in the same order on every host.
        [Array]::Sort([string[]]@($entries | ForEach-Object Name), $entries, [StringComparer]::Ordinal)
        $folders = [Collections.Generic.List[string]]::new()
        foreach ($entry in $entries) {
            $relative = ConvertTo-GuidanceLabel $Context $entry.FullName
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                if ($relative -ceq '.agents' -or $relative.StartsWith('.agents/', [StringComparison]::Ordinal) -or
                    $entry.Name -ceq 'AGENTS.md' -or $entry.Name -ceq 'SKILL.md') { Add-GuidanceReparseProblem $Context $relative }
                continue
            }
            if ($entry -is [IO.DirectoryInfo]) {
                if ($entry.Name -ceq '.git' -or $entry.Name -ceq '.build' -or (Test-GuidanceEntry (Join-Path $entry.FullName '.git'))) { continue }
                if ($relative -cmatch '\A\.agents/skills/[^/]+\z') { $tree.Skills.Add($entry.FullName) }
                $folders.Add($entry.FullName)
                continue
            }
            if ($entry.Name -ceq 'AGENTS.md') { $tree.Agents.Add($relative) }
            if ($entry.Name -ceq 'SKILL.md' -and $relative -cnotmatch '\A\.agents/skills/[^/]+/SKILL\.md\z') {
                Add-GuidanceProblem $Context $relative 'is a skill outside .agents/skills; each skill is a folder .agents/skills/<name> with its SKILL.md' 'G5'
            }
            if ($relative.StartsWith('.agents/skills/', [StringComparison]::Ordinal) -and $entry.Extension -ieq '.md') { $tree.Markdown.Add($entry.FullName) }
            if ($relative -cmatch '\A\.agents/skills/[^/]+/agents/openai\.yaml\z') {
                Add-GuidanceProblem $Context $relative 'skill packages carry no harness UI metadata (register A-11); remove it' 'G8'
            }
        }
        for ($i = $folders.Count - 1; $i -ge 0; $i--) { $pending.Push($folders[$i]) }
    }
    foreach ($list in @($tree.Agents, $tree.Skills, $tree.Markdown)) { $list.Sort([StringComparer]::Ordinal) }
    return $tree
}

function Get-GuidanceParameterNames([Management.Automation.Language.ScriptBlockAst] $Ast) {
    # The parameter names a script accepts: declared names and aliases and, for an advanced script, the common parameters
    # and their aliases, plus WhatIf and Confirm under SupportsShouldProcess. Read from the syntax tree only.
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $block = $Ast.ParamBlock
    if ($null -eq $block) { return , $names }
    $advanced = $false
    foreach ($parameter in $block.Parameters) {
        [void]$names.Add($parameter.Name.VariablePath.UserPath)
        foreach ($attribute in @($parameter.Attributes | Where-Object { $_ -is [Management.Automation.Language.AttributeAst] })) {
            $type = $attribute.TypeName.Name
            if ($type -iin @('Alias', 'AliasAttribute', 'System.Management.Automation.AliasAttribute')) {
                foreach ($argument in $attribute.PositionalArguments) {
                    if ($argument -is [Management.Automation.Language.StringConstantExpressionAst]) { [void]$names.Add($argument.Value) }
                }
            }
            # A [Parameter()] attribute makes the script advanced even without [CmdletBinding()], as PowerShell does.
            if ($type -iin @('Parameter', 'ParameterAttribute', 'System.Management.Automation.ParameterAttribute')) { $advanced = $true }
        }
    }
    $bindings = @($block.Attributes | Where-Object { $_.TypeName.Name -iin @('CmdletBinding', 'CmdletBindingAttribute', 'System.Management.Automation.CmdletBindingAttribute') })
    if (-not $bindings.Count -and -not $advanced) { return , $names }
    if ($null -eq $script:CommonParameterNames) {
        # The common parameters and their aliases, from the engine's own parameter classes; no command is looked up.
        $common = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $shouldProcess = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($pair in @(@([Management.Automation.Internal.CommonParameters], $common), @([Management.Automation.Internal.ShouldProcessParameters], $shouldProcess))) {
            foreach ($property in $pair[0].GetProperties()) {
                [void]$pair[1].Add($property.Name)
                foreach ($alias in $property.GetCustomAttributes([Management.Automation.AliasAttribute], $true)) { foreach ($name in $alias.AliasNames) { [void]$pair[1].Add($name) } }
            }
        }
        $script:CommonParameterNames = [pscustomobject]@{ Common = $common; ShouldProcess = $shouldProcess }
    }
    $names.UnionWith($script:CommonParameterNames.Common)
    foreach ($binding in $bindings) {
        foreach ($argument in $binding.NamedArguments) {
            if ($argument.ArgumentName -ine 'SupportsShouldProcess') { continue }
            $enabled = $argument.ExpressionOmitted -or
                ($argument.Argument -is [Management.Automation.Language.VariableExpressionAst] -and $argument.Argument.VariablePath.UserPath -ieq 'true') -or
                ($argument.Argument -is [Management.Automation.Language.ConstantExpressionAst] -and $argument.Argument.Value -is [bool] -and $argument.Argument.Value)
            if ($enabled) { $names.UnionWith($script:CommonParameterNames.ShouldProcess) }
        }
    }
    return , $names
}

function Test-GuidanceExamples([pscustomobject] $Context, [string] $Label, [pscustomobject] $Fence) {
    # G11: in a powershell fence, a line that starts with ./<script>.ps1 names a script of the repository (resolved from the
    # root, as commands run there) that parses, and passes only parameters it accepts. Nothing is executed. A shared skill
    # of a documentation project names the commands of the product it is used in, so a script it lacks is not reported.
    for ($i = 0; $i -lt $Fence.Lines.Length; $i++) {
        $info = $Fence.Info[$i]
        if (-not $info -or ($info -split '\s+', 2)[0] -ine 'powershell') { continue }
        $match = [regex]::Match($Fence.Lines[$i], '^\s*\.[\\/](?<script>[A-Za-z0-9_.\\/-]+\.ps1)(?:\s|$)')
        if (-not $match.Success) { continue }
        $location = "${Label}:$($i + 1)"
        $script = $match.Groups['script'].Value.Replace('\', '/')
        $resolved = [IO.Path]::GetFullPath([IO.Path]::Combine($Context.Root, $script))
        $outside = Test-GuidanceOutside ([IO.Path]::GetRelativePath($Context.Root, $resolved))
        if (-not $outside) {
            $reparse = Get-GuidanceReparsePoint $resolved $Context.Root
            if ($reparse) { Add-GuidanceReparseProblem $Context $reparse; continue }
        }
        if ($outside -or -not [IO.File]::Exists($resolved)) {
            if (-not $Context.Documentation) { Add-GuidanceProblem $Context $location "PowerShell example runs ./$script, which is not a script of this repository" 'G11' }
            continue
        }
        $onDisk = Get-GuidanceCaseMismatch $resolved $Context.Root $Context.Listings
        if ($onDisk) { Add-GuidanceProblem $Context $location "PowerShell example runs ./$script, which differs in case from the script on disk: $onDisk" 'G11'; continue }
        $tokens = $null
        $errors = $null
        $example = [Management.Automation.Language.Parser]::ParseInput($Fence.Lines[$i], [ref]$tokens, [ref]$errors)
        if ($errors.Count) { Add-GuidanceProblem $Context $location "PowerShell example does not parse: $($errors[0].Message)" 'G11'; continue }
        $ast = [Management.Automation.Language.Parser]::ParseFile($resolved, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { Add-GuidanceProblem $Context $location "PowerShell example runs ./$script, which does not parse: $($errors[0].Message)" 'G11'; continue }
        $names = Get-GuidanceParameterNames $ast
        $commands = @($example.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $false))
        if (-not $commands.Count) { continue }
        foreach ($parameter in @($commands[0].CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] })) {
            if (-not $names.Contains($parameter.ParameterName)) {
                Add-GuidanceProblem $Context $location "PowerShell example passes -$($parameter.ParameterName), which ./$script does not accept" 'G11'
            }
        }
        $Context.Examples++
    }
}

function Test-GuidanceReference([pscustomobject] $Context, [string] $Location, [pscustomobject] $Reference) {
    # G6 for one local reference, G13 for one that leaves a documentation project, G7 for one through a reparse point.
    $relative = [IO.Path]::GetRelativePath($Context.Root, $Reference.Resolved)
    if (Test-GuidanceOutside $relative) {
        if (-not $Context.Documentation) { Add-GuidanceProblem $Context $Location "reference escapes this repository: $($Reference.Path)" 'G6'; return }
        if (Test-GuidanceOutside ([IO.Path]::GetRelativePath($Context.Workspace, $Reference.Resolved))) {
            Add-GuidanceProblem $Context $Location "reference escapes the folder of the sibling repositories: $($Reference.Path)" 'G13'
            return
        }
        if (-not $Context.CheckSiblings) { return }
        if (-not (Test-GuidanceEntry $Reference.Resolved)) {
            Add-GuidanceProblem $Context $Location "missing sibling reference: $($Reference.Path) (expected $($Reference.Resolved))" 'G13'
            return
        }
        $onDisk = Get-GuidanceCaseMismatch $Reference.Resolved $Context.Workspace $Context.Listings
        if ($onDisk) {
            $requested = [IO.Path]::GetRelativePath($Context.Workspace, $Reference.Resolved).Replace('\', '/')
            Add-GuidanceProblem $Context $Location "sibling reference differs in case from the file on disk: ../$requested (on disk: ../$onDisk)" 'G13'
        }
        return
    }
    $reparse = Get-GuidanceReparsePoint $Reference.Resolved $Context.Root
    if ($reparse) { Add-GuidanceProblem $Context $Location "reference passes through the reparse point ${reparse}: $($Reference.Path)" 'G7'; return }
    if (-not (Test-GuidanceEntry $Reference.Resolved)) { Add-GuidanceProblem $Context $Location "missing local reference: $($Reference.Path)" 'G6'; return }
    $onDisk = Get-GuidanceCaseMismatch $Reference.Resolved $Context.Root $Context.Listings
    if ($onDisk) {
        Add-GuidanceProblem $Context $Location "local reference differs in case from the file on disk: $($relative.Replace('\', '/')) (on disk: $onDisk)" 'G6'
    }
}

function Test-GuidanceMarkdown([pscustomobject] $Context, [string] $Path) {
    # G2, G3, G6, G7, G13 and, in a skill package, G11 for one Markdown file. Returns its local references (Target, Line
    # and Resolved), or $null when the file cannot be read.
    $label = ConvertTo-GuidanceLabel $Context $Path
    $text = Read-GuidanceFile $Context $Path
    if ($null -eq $text) { return $null }
    # An empty SKILL.md is already a skill grammar problem (G1).
    if (-not $text.Trim()) {
        if ([IO.Path]::GetFileName($Path) -cne 'SKILL.md') { Add-GuidanceProblem $Context $label 'is empty' 'G2' }
        return , @()
    }
    $prose = Get-GuidanceProse $text
    foreach ($fence in $prose.Unclosed) { Add-GuidanceProblem $Context "${label}:$($fence.Line)" "unclosed code fence (opened with $($fence.Token))" 'G3' }
    $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    $links = [Collections.Generic.List[object]]::new()
    foreach ($link in @(Get-GuidanceLink $prose.Text)) {
        $location = "${label}:$($link.Line)"
        $reference = Resolve-GuidanceReference $link.Target $directory
        if ($null -eq $reference) { continue }
        if ($reference.Invalid) { Add-GuidanceProblem $Context $location $reference.Invalid 'G6'; continue }
        $Context.References++
        $links.Add([pscustomobject]@{ Target = $link.Target; Line = $link.Line; Resolved = $reference.Resolved })
        Test-GuidanceReference $Context $location $reference
    }
    if ($label.StartsWith('.agents/skills/', [StringComparison]::Ordinal)) { Test-GuidanceExamples $Context $label $prose.Fence }
    return , $links.ToArray()
}

function Test-GuidanceInventory([pscustomobject] $Context, [string[]] $Found) {
    # G9: .agents/guidance.json is {"schemaVersion":1,"files":[...]} and lists exactly the AGENTS.md files of the walk.
    $label = '.agents/guidance.json'
    $path = [IO.Path]::GetFullPath((Join-Path $Context.Root $label))
    $reparse = Get-GuidanceReparsePoint $path $Context.Root
    if ($reparse) { Add-GuidanceReparseProblem $Context $reparse; return }
    if (-not [IO.File]::Exists($path)) {
        Add-GuidanceProblem $Context $label 'missing; the scoped-guidance inventory lists every AGENTS.md of the repository: {"schemaVersion":1,"files":["AGENTS.md"]}' 'G9'
        return
    }
    $text = Read-GuidanceFile $Context $path
    if ($null -eq $text) { return }
    try { $inventory = ConvertFrom-Json -InputObject $text -AsHashtable -ErrorAction Stop }
    catch { Add-GuidanceProblem $Context $label "is not valid JSON: $($_.Exception.Message)" 'G9'; return }
    # Assigned in the branch: an if expression would unroll a one-entry files array into its string.
    $version = $null
    $files = $null
    if ($inventory -is [Collections.IDictionary]) {
        if ($inventory.Contains('schemaVersion')) { $version = $inventory['schemaVersion'] }
        if ($inventory.Contains('files')) { $files = $inventory['files'] }
    }
    if (-not ($version -is [long] -or $version -is [int]) -or $version -ne 1 -or $files -isnot [array] -or -not $files.Count) {
        Add-GuidanceProblem $Context $label 'must be a JSON object with schemaVersion 1 and a non-empty files array of repository-relative AGENTS.md paths' 'G9'
        return
    }
    $listed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $files) {
        $valid = $entry -is [string] -and -not [IO.Path]::IsPathRooted($entry) -and -not $entry.Contains('\')
        if ($valid) {
            $segments = $entry.Split('/')
            $valid = $segments[-1] -ceq 'AGENTS.md'
            foreach ($segment in $segments) {
                if (-not $segment -or $segment -in @('.', '..') -or $segment.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $segment -match '[<>:"|?*]') { $valid = $false }
            }
        }
        if (-not $valid) { Add-GuidanceProblem $Context $label "lists $entry, which is not a repository-relative path of an AGENTS.md (forward slashes, no . or .. segments)" 'G9'; continue }
        if (-not $listed.Add($entry)) { Add-GuidanceProblem $Context $label "lists $entry twice" 'G9' }
    }
    $actual = [Collections.Generic.HashSet[string]]::new([string[]]$Found, [StringComparer]::Ordinal)
    foreach ($relative in $Found) {
        if (-not $listed.Contains($relative)) { Add-GuidanceProblem $Context $relative "is not listed in the scoped-guidance inventory $label" 'G9' }
    }
    foreach ($entry in $listed) {
        if (-not $actual.Contains($entry)) { Add-GuidanceProblem $Context $label "lists $entry, which is not an AGENTS.md of this repository" 'G9' }
    }
}

function Test-GuidanceIndex([pscustomobject] $Context, [pscustomobject] $Tree, [hashtable] $Links) {
    # G10: the root AGENTS.md links each skill as (.agents/skills/<name>/SKILL.md) and nothing else under that folder; each
    # pointer exists, has at most six non-empty lines and links the root AGENTS.md.
    $agents = [IO.Path]::GetFullPath((Join-Path $Context.Root 'AGENTS.md'))
    if (-not $Links.ContainsKey('AGENTS.md')) {
        if (-not [IO.File]::Exists($agents)) { Add-GuidanceProblem $Context 'AGENTS.md' 'missing; the root AGENTS.md is the canonical agent guidance and indexes every skill' 'G10' }
    } elseif ($null -ne $Links['AGENTS.md']) {
        $indexed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($link in $Links['AGENTS.md']) {
            $relative = (ConvertTo-GuidanceLabel $Context $link.Resolved).TrimEnd('/')
            if ($relative -cne '.agents/skills' -and -not $relative.StartsWith('.agents/skills/', [StringComparison]::Ordinal)) { continue }
            $canonical = [regex]::Match($link.Target, '\A\.agents/skills/(?<name>[^/]+)/SKILL\.md\z')
            if ($canonical.Success) { [void]$indexed.Add($canonical.Groups['name'].Value); continue }
            Add-GuidanceProblem $Context "AGENTS.md:$($link.Line)" "links $($link.Target); the index links each skill as (.agents/skills/<name>/SKILL.md) and nothing else under .agents/skills" 'G10'
        }
        foreach ($folder in $Tree.Skills) {
            $name = [IO.Path]::GetFileName($folder)
            if (-not $indexed.Contains($name)) { Add-GuidanceProblem $Context 'AGENTS.md' "does not index the skill $name; link it as (.agents/skills/$name/SKILL.md)" 'G10' }
        }
    }
    foreach ($relative in $script:Pointers) {
        $path = [IO.Path]::GetFullPath((Join-Path $Context.Root $relative))
        if (-not $Links.ContainsKey($relative)) {
            if (-not [IO.File]::Exists($path)) { Add-GuidanceProblem $Context $relative 'missing; it is a thin pointer to the root AGENTS.md' 'G10' }
            continue
        }
        if ($null -eq $Links[$relative]) { continue }
        $count = @($Context.Texts[$path].Replace("`r`n", "`n") -split "`n" | Where-Object { $_.Trim() }).Count
        if ($count -gt 6) { Add-GuidanceProblem $Context $relative "has $count non-empty lines; keep it a pointer of at most six that links AGENTS.md" 'G10' }
        if (-not @($Links[$relative] | Where-Object { [string]::Equals($_.Resolved, $agents, [StringComparison]::Ordinal) }).Count) {
            $form = if ($relative -ceq 'CLAUDE.md') { '[AGENTS.md](AGENTS.md)' } else { '[../AGENTS.md](../AGENTS.md)' }
            Add-GuidanceProblem $Context $relative "does not link the root AGENTS.md; link it as $form" 'G10'
        }
    }
}

function Test-GuidancePlanIndex([pscustomobject] $Context) {
    # G12: Specs/Plans/WIP/README.md links each plan of that folder exactly once, and only plans that exist; so does
    # Specs/Plans/Done/README.md when it is present. A plan is a Markdown file directly in the folder, other than README.md.
    # The index entry is a link to the plan itself: a link with a fragment or query points into a plan and does not count,
    # though one to a plan that does not exist is still reported.
    foreach ($state in @('WIP', 'Done')) {
        $relative = "Specs/Plans/$state"
        $directory = [IO.Path]::GetFullPath((Join-Path $Context.Root $relative))
        if (-not [IO.Directory]::Exists($directory)) { continue }
        $index = Join-Path $directory 'README.md'
        $reparse = Get-GuidanceReparsePoint $index $Context.Root
        if ($reparse) { Add-GuidanceReparseProblem $Context $reparse; continue }
        if (-not [IO.File]::Exists($index)) {
            if ($state -ceq 'WIP') { Add-GuidanceProblem $Context "$relative/README.md" "missing; it indexes the plans of $relative" 'G12' }
            continue
        }
        $text = Read-GuidanceFile $Context $index
        if ($null -eq $text) { continue }
        $prose = Get-GuidanceProse $text
        foreach ($fence in $prose.Unclosed) { Add-GuidanceProblem $Context "$relative/README.md:$($fence.Line)" "unclosed code fence (opened with $($fence.Token))" 'G3' }
        $plans = [string[]]@([IO.Directory]::EnumerateFiles($directory) | ForEach-Object { [IO.Path]::GetFileName($_) } |
            Where-Object { [IO.Path]::GetExtension($_) -ieq '.md' -and $_ -cne 'README.md' })
        [Array]::Sort($plans, [StringComparer]::Ordinal)
        $counts = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
        $lines = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
        foreach ($link in @(Get-GuidanceLink $prose.Text)) {
            $reference = Resolve-GuidanceReference $link.Target $directory
            if ($null -eq $reference -or $reference.Invalid) { continue }
            if (-not [string]::Equals([IO.Path]::GetDirectoryName($reference.Resolved), $directory, [StringComparison]::Ordinal)) { continue }
            $name = [IO.Path]::GetFileName($reference.Resolved)
            if ([IO.Path]::GetExtension($name) -ine '.md' -or $name -ceq 'README.md') { continue }
            if (-not $lines.ContainsKey($name)) { $lines[$name] = $link.Line }
            if ($link.Target.IndexOfAny([char[]]@('#', '?')) -ge 0) { continue }
            if ($counts.ContainsKey($name)) { $counts[$name] = $counts[$name] + 1 } else { $counts[$name] = 1 }
        }
        foreach ($plan in $plans) {
            if (-not $counts.ContainsKey($plan)) { Add-GuidanceProblem $Context "$relative/$plan" "is not linked from $relative/README.md, which names each plan exactly once" 'G12' }
            elseif ($counts[$plan] -gt 1) { Add-GuidanceProblem $Context "$relative/README.md" "links $plan $($counts[$plan]) times; name each plan exactly once" 'G12' }
        }
        foreach ($name in $lines.Keys) {
            if ($name -cnotin $plans) { Add-GuidanceProblem $Context "$relative/README.md:$($lines[$name])" "links $name, which is not a plan in $relative" 'G12' }
        }
    }
}

function Get-CiAgentGuidanceResult {
    <#
    .SYNOPSIS
        Validates a repository's agent guidance and returns every problem with the counts (G1 to G13).
    .DESCRIPTION
        Applies the agent-guidance contract of Specs/ProjectCommands.md to the skills under .agents/skills, the root
        AGENTS.md, CLAUDE.md, .github/copilot-instructions.md, every scoped AGENTS.md, .agents/guidance.json and the plan
        indexes under Specs/Plans. Collects every problem; never throws for a content problem. Read-only: it writes,
        fetches and executes nothing, and reads only below Root and, for a documentation project with CheckSiblings, the
        sibling paths that its references name.
    .PARAMETER Root
        Repository root. A relative path means the caller's PowerShell location.
    .PARAMETER Kind
        Product (the default): every local reference stays inside the repository. Documentation (RedHome): a reference may
        name a sibling repository in the folder that holds Root (G13), and a PowerShell example may name a product command
        the documentation project lacks (G11).
    .PARAMETER CheckSiblings
        With Kind Documentation, also requires each sibling reference to exist, resolved against the folder that holds Root.
    .OUTPUTS
        Problems (string array, one "<path>[:<line>]: <problem> (<rule>)" each), Skills, References (local references
        checked), Examples (PowerShell examples checked) and Guidance (AGENTS.md files).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Root, [ValidateSet('Product', 'Documentation')][string] $Kind = 'Product', [switch] $CheckSiblings)
    $rootPath = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)))
    if (-not [IO.Directory]::Exists($rootPath)) { throw "Agent guidance root is not a folder: $rootPath" }
    $workspace = [IO.Path]::GetDirectoryName($rootPath)
    if (-not $workspace) { $workspace = $rootPath }
    $context = [pscustomobject]@{
        Root = $rootPath; Workspace = $workspace; Documentation = $Kind -eq 'Documentation'; CheckSiblings = [bool]$CheckSiblings
        Problems = [Collections.Generic.List[string]]::new(); Seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        Texts = @{}; Listings = @{}; References = 0; Examples = 0
    }
    # G7: a linked root is refused before anything below it is listed or read.
    if ([IO.File]::GetAttributes($rootPath) -band [IO.FileAttributes]::ReparsePoint) {
        Add-GuidanceProblem $context '.' 'the repository root is a reparse point; validate the folder it links to' 'G7'
        return [pscustomobject]@{ Problems = $context.Problems.ToArray(); Skills = 0; References = 0; Examples = 0; Guidance = 0 }
    }
    $tree = Get-GuidanceTree $context
    # G5, then G1, G2 and G4 for each skill.
    if (-not [IO.Directory]::Exists((Join-Path $rootPath '.agents/skills'))) { Add-GuidanceProblem $context '.agents/skills' 'missing; skills live in .agents/skills' 'G5' }
    elseif (-not $tree.Skills.Count) { Add-GuidanceProblem $context '.agents/skills' 'holds no skill package' 'G5' }
    foreach ($folder in $tree.Skills) {
        $name = [IO.Path]::GetFileName($folder)
        $path = Join-Path $folder 'SKILL.md'
        # A linked SKILL.md is already refused by the walk (G7) and is never read.
        if (Get-GuidanceReparsePoint $path $rootPath) { continue }
        if (-not [IO.File]::Exists($path)) { Add-GuidanceProblem $context ".agents/skills/$name" 'missing SKILL.md or empty file' 'G1'; continue }
        $text = Read-GuidanceFile $context $path
        if ($null -eq $text) { continue }
        foreach ($problem in (Get-SkillProblemList $name $text -NoFence)) { Add-GuidanceProblem $context ".agents/skills/$name/SKILL.md" $problem.Message $problem.Rule }
    }
    # G2, G3, G6, G7, G11 and G13 for the root guidance, every scoped AGENTS.md and the Markdown of the skill packages.
    $links = @{}
    foreach ($relative in @('AGENTS.md') + $script:Pointers) {
        $path = [IO.Path]::GetFullPath((Join-Path $rootPath $relative))
        $reparse = Get-GuidanceReparsePoint $path $rootPath
        if ($reparse) { Add-GuidanceReparseProblem $context $reparse; $links[$relative] = $null; continue }
        if ([IO.File]::Exists($path)) { $links[$relative] = Test-GuidanceMarkdown $context $path }
    }
    foreach ($relative in $tree.Agents) { if ($relative -cne 'AGENTS.md') { [void](Test-GuidanceMarkdown $context (Join-Path $rootPath $relative)) } }
    foreach ($path in $tree.Markdown) { [void](Test-GuidanceMarkdown $context $path) }
    Test-GuidanceInventory $context $tree.Agents.ToArray()
    Test-GuidanceIndex $context $tree $links
    Test-GuidancePlanIndex $context
    return [pscustomobject]@{
        Problems = $context.Problems.ToArray(); Skills = $tree.Skills.Count; References = $context.References
        Examples = $context.Examples; Guidance = $tree.Agents.Count
    }
}

function Get-CiAgentGuidanceProblems {
    <#
    .SYNOPSIS
        Returns every agent-guidance problem of a repository as one string array (G1 to G13).
    .DESCRIPTION
        The Problems of Get-CiAgentGuidanceResult: empty when the guidance is valid. Never throws for a content problem.
        Read-only.
    .PARAMETER Root
        Repository root. A relative path means the caller's PowerShell location.
    .PARAMETER Kind
        Product (the default) or Documentation (sibling references allowed, G13).
    .PARAMETER CheckSiblings
        With Kind Documentation, also requires each sibling reference to exist.
    .OUTPUTS
        String array, one "<path>[:<line>]: <problem> (<rule>)" per problem.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Root, [ValidateSet('Product', 'Documentation')][string] $Kind = 'Product', [switch] $CheckSiblings)
    $resolved = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)
    return , [string[]](Get-CiAgentGuidanceResult -Root $resolved -Kind $Kind -CheckSiblings:$CheckSiblings).Problems
}

#endregion

Export-ModuleMember -Function Get-CiSkillProblem, Get-CiAgentGuidanceResult, Get-CiAgentGuidanceProblems
