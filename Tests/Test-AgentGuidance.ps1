<#
.SYNOPSIS
Tests the shared agent-guidance validator (rules G1 to G13), its command and its product shim, without compilation.
.DESCRIPTION
Ports the behavior cases of the RedXe, RedTilde and RedPrism skill suites to Tools/Modules/Ci.AgentGuidance.psm1, adds
cases for every rule of Specs/ProjectCommands.md ("Agent guidance"), and runs Tools/Test-AgentGuidance.ps1 and the
Templates/Project/Tools/Test-AgentGuidance.ps1 shim against fixture products. Every case writes its fixture under its own
folder of the run's child. Junction and file-lock controls are Windows-only and report SKIP elsewhere; symbolic-link and
letter-case controls report SKIP where the host cannot create a link or has a case-sensitive file system.
.PARAMETER TestRoot
Existing marked RedSalamander.Perf root, or a hosted RUNNER_TEMP descendant. Creates one unique child only.
.OUTPUTS
Case results and results.json beneath the created child, which is retained. Nonzero exit on a failed case.
.NOTES
Requires PowerShell 7.4, and Git for the shim cases. No credentials, compiler, network or desktop input. No referenced
script or example is executed: the fixtures' scripts would write a marker that the cases look for.
.EXAMPLE
./Tests/Test-AgentGuidance.ps1 -TestRoot Z:/RedSalamander.Perf
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TestRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$engineRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$selected = [IO.Path]::GetFullPath($TestRoot).TrimEnd('\', '/')
$hosted = $env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted' -and $env:RUNNER_TEMP
if ($hosted) {
    $tempPrefix = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $selected.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Hosted guidance fixtures must remain under RUNNER_TEMP.' }
} elseif ($selected -notmatch '^[A-Za-z]:[\\/]RedSalamander\.Perf$' -or
    -not (Test-Path -LiteralPath (Join-Path $selected '.red-salamander-test-root')) -or
    [IO.File]::ReadAllText((Join-Path $selected '.red-salamander-test-root')).Trim() -cne 'red-salamander.test-sandbox-root.v1') {
    throw 'Guidance fixtures require the existing marked test root.'
}
$runRoot = Join-Path $selected ('unified-ci/guidance-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runRoot)
$guidanceModule = Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.AgentGuidance.psm1') -Force -PassThru
$command = Join-Path $engineRoot 'Tools/Test-AgentGuidance.ps1'
$rows = [Collections.Generic.List[object]]::new()
$links = [Collections.Generic.List[string]]::new()
$script:currentCase = ''
$script:fixtureIndex = 0

function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Skip([string]$Reason) { throw [OperationCanceledException]::new($Reason) }
function Case([string]$Name, [scriptblock]$Body) {
    $script:currentCase = $Name
    try {
        & $Body
        $rows.Add([ordered]@{ name = $Name; passed = $true }); Write-Host "PASS $Name"
    } catch [OperationCanceledException] {
        $rows.Add([ordered]@{ name = $Name; passed = $true; skipped = $_.Exception.Message }); Write-Host "SKIP $Name : $($_.Exception.Message)" -ForegroundColor Yellow
    } catch {
        $rows.Add([ordered]@{ name = $Name; passed = $false; error = $_.Exception.Message }); Write-Host "FAIL $Name : $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        # Links are removed after their case so the retained evidence never holds a loop or a link out of the run.
        foreach ($link in $links) {
            if ([IO.Directory]::Exists($link)) { [IO.Directory]::Delete($link) } elseif ([IO.File]::Exists($link)) { [IO.File]::Delete($link) }
        }
        $links.Clear()
    }
}
function Put([string]$Root, [string]$Path, [string]$Text) {
    $target = Join-Path $Root $Path
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    [IO.File]::WriteAllText($target, $Text, [Text.UTF8Encoding]::new($false))
}
function PutBytes([string]$Root, [string]$Path, [byte[]]$Bytes) {
    $target = Join-Path $Root $Path
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    [IO.File]::WriteAllBytes($target, $Bytes)
}
function Remove([string]$Root, [string]$Path) {
    $target = Join-Path $Root $Path
    if ([IO.Directory]::Exists($target)) { [IO.Directory]::Delete($target, $true) } else { [IO.File]::Delete($target) }
}
function New-CaseFolder {
    $script:fixtureIndex++
    $slug = ($script:currentCase -replace '[^A-Za-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).TrimEnd('-') }
    $folder = Join-Path $runRoot ('{0:D3}-{1}' -f $script:fixtureIndex, $slug)
    [void][IO.Directory]::CreateDirectory($folder)
    return $folder
}
function New-Junction([string]$Path, [string]$Target) {
    if (-not $IsWindows) { Skip 'junctions are a Windows control' }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [void](New-Item -ItemType Junction -Path $Path -Target $Target)
    $links.Add($Path)
}
function New-FileLink([string]$Path, [string]$Target) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    try { [void][IO.File]::CreateSymbolicLink($Path, $Target) }
    catch {
        $base = $_.Exception.GetBaseException()
        # ERROR_PRIVILEGE_NOT_HELD: this Windows host lets only elevated or developer-mode accounts create symbolic links.
        if ($base -is [UnauthorizedAccessException] -or ($base -is [IO.IOException] -and ($base.HResult -band 0xffff) -eq 1314)) { Skip 'this host cannot create a symbolic link' }
        throw
    }
    $links.Add($Path)
}

$utf8 = [Text.UTF8Encoding]::new($false)
$t = '`'
$f3 = '```'
$skillPath = '.agents/skills/example-skill/SKILL.md'
$prefix = "---`nname: example-skill`ndescription: Exercise the guidance checks. Use when testing the engine.`n---`n"
$contract = '[Contract](../../../Specs/contract%20with%20spaces.md#scope) [Web](https://example.invalid/) [Section](#local)'
$claude = "Read [AGENTS.md](AGENTS.md).`n"
$probeBody = "`n[IO.File]::WriteAllText((Join-Path `$PSScriptRoot 'executed.txt'), 'A referenced script ran.')"

function New-Product([string]$Folder = '') {
    # A product whose guidance passes every rule: one indexed skill, both pointers, the inventory and one indexed plan.
    $root = if ($Folder) { $Folder } else { New-CaseFolder }
    Put $root 'AGENTS.md' "# Fixture guidance`n`nSkills: [example-skill](.agents/skills/example-skill/SKILL.md).`n"
    Put $root 'CLAUDE.md' $claude
    Put $root '.github/copilot-instructions.md' "Read [../AGENTS.md](../AGENTS.md).`n"
    Put $root '.agents/guidance.json' '{"schemaVersion":1,"files":["AGENTS.md"]}'
    Put $root $skillPath ($prefix + $contract)
    Put $root 'Specs/contract with spaces.md' '# Owning contract'
    Put $root 'Specs/Plans/WIP/README.md' "# Plans`n`n- [Example plan](Example_2026-11-19.md)`n"
    Put $root 'Specs/Plans/WIP/Example_2026-11-19.md' '# Example plan'
    return $root
}
function Skill([string]$Root, [string]$Text) { Put $Root $skillPath ($prefix + $Text) }
function Get-Problems([string]$Root, [string]$Kind = 'Product', [switch]$CheckSiblings) {
    # Under PowerShell's default error preference, as products call it: a read failure must not hide behind Stop.
    $previous = $global:ErrorActionPreference
    $global:ErrorActionPreference = 'Continue'
    try { return , [string[]](Get-CiAgentGuidanceProblems -Root $Root -Kind $Kind -CheckSiblings:$CheckSiblings) }
    finally { $global:ErrorActionPreference = $previous }
}
function Valid([string]$Root, [string]$Kind = 'Product', [switch]$CheckSiblings) {
    $problems = Get-Problems $Root $Kind -CheckSiblings:$CheckSiblings
    Require (-not $problems.Count) "Expected valid guidance, received: $($problems -join ' | ')"
}
function Problem([string]$Root, [string]$Expected, [string]$Kind = 'Product', [switch]$CheckSiblings) {
    $problems = Get-Problems $Root $Kind -CheckSiblings:$CheckSiblings
    Require (@($problems | Where-Object { $_.Contains($Expected) }).Count -gt 0) "Expected a problem containing '$Expected', received: $($problems -join ' | ')"
    return , $problems
}
function ConvertTo-FileUri([string]$Path) {
    # An escaped file URI on every host: [Uri] of a Unix path would read a '#' in a file name as a fragment.
    $segments = [IO.Path]::GetFullPath($Path).Replace('\', '/').TrimStart('/').Split('/')
    return 'file:///' + (@(foreach ($segment in $segments) { if ($segment -match '^[A-Za-z]:$') { $segment } else { [Uri]::EscapeDataString($segment) } }) -join '/')
}
function Get-Snapshot([string]$Root) {
    # Every entry with its kind and attributes, and each file's write time and content hash: a validator run must change
    # none of them. A folder's write time is left out: NTFS updates it lazily after the fixture's own writes.
    return (@(Get-ChildItem -LiteralPath $Root -Force -Recurse | Sort-Object FullName | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($Root, $_.FullName)
        if ($_.PSIsContainer) { "D:${relative}:$($_.Attributes)" }
        else { "F:${relative}:$($_.Attributes):$($_.LastWriteTimeUtc.Ticks):$([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($_.FullName))))" }
    }) -join "`n")
}
function Assert-Unchanged([string]$Root, [string]$Before, [string]$What) {
    $after = Get-Snapshot $Root
    if ($after -ceq $Before) { return }
    $changed = @(Compare-Object ($Before -split "`n") ($after -split "`n") -CaseSensitive | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
    throw "$What changed the fixture: $($changed -join ' | ')"
}
$probeCase = Join-Path $runRoot 'case-probe'
Put $probeCase 'Probe.txt' 'Letter-case probe.'
$caseInsensitive = [IO.File]::Exists((Join-Path $probeCase 'probe.txt'))

#region G1, G3 and G4: the skill grammar (RedXe, RedPrism and RedTilde grammar suites)

function Front([string[]]$Lines) { return "---`n" + ($Lines -join "`n") + "`n---`n" }
$nameLine = 'name: example-skill'
$descriptionLine = 'description: Valid. Use when testing.'
$valid = Front @($nameLine, $descriptionLine)
$g4 = 'description does not say when to use the skill'
function Grammar([string]$GrammarName, [AllowNull()][AllowEmptyString()][string]$GrammarText, [string[]]$GrammarExpect = @(), [string[]]$GrammarAbsent = @()) {
    Case "G1 grammar: $GrammarName" {
        $problem = Get-CiSkillProblem -FolderName 'example-skill' -Text $GrammarText
        if (-not $GrammarExpect.Count) { Require (-not $problem) "Expected a valid skill, received: $problem" }
        foreach ($expected in $GrammarExpect) { Require ($problem -and $problem.Contains($expected)) "Expected '$expected', received: $problem" }
        foreach ($absent in $GrammarAbsent) { Require (-not ($problem -and $problem.Contains($absent))) "Did not expect '$absent': $problem" }
    }
}
Grammar 'plain' ($valid + 'Read the contract.')
Grammar 'CRLF' (($valid + 'Read.').Replace("`n", "`r`n"))
Grammar 'literal Unicode block' ((Front @($nameLine, "description: |`n  Validate français`n  and 日本語. Use when testing.")) + 'Read.')
Grammar 'folded block' ((Front @($nameLine, "description: >-`n  Validate français`n  and 日本語. Use when testing.")) + 'Read.')
Grammar 'optional metadata' ((Front @($nameLine, $descriptionLine, 'license: MIT', 'allowed-tools: Read Write', "metadata:`n  version: '1.0'`n  author: Example")) + 'Read.')
Grammar 'single-quoted apostrophe with a comment' ((Front @($nameLine, "description: 'It''s valid: yes. Use when testing.' # comment")) + 'Read.')
Grammar 'JSON-quoted escapes' ((Front @($nameLine, 'description: "Line\nDeux \u65e5. Use when testing."')) + 'Read.')
Grammar 'plain comments' ((Front @('# comment', $nameLine, 'description: Valid. Use when testing. # comment')) + 'Read.')
Grammar 'ordinary words that resemble types' ((Front @($nameLine, 'description: Notify owners of yesterday events. Use when testing.')) + 'Read.')
Grammar 'date-prefixed prose' ((Front @($nameLine, 'description: 2026-10-28 migration guidance. Use when migrating.')) + 'Read.')
Grammar 'timestamp-prefixed prose' ((Front @($nameLine, 'description: 2026-10-28T09:00:00Z migration guidance. Use when migrating.')) + 'Read.')
# A quoted typed value is a string: only G4 refuses it, never the grammar.
foreach ($quoted in @("'123'", '"2026-10-28"', '"2026-10-28T09:00:00Z"', '"2026-10-28T09:00:00+02:00"')) {
    Grammar "quoted $quoted is a string" ((Front @($nameLine, "description: $quoted")) + 'Read.') @($g4) @('invalid description')
}
Grammar 'missing file' $null @('missing SKILL.md or empty file')
Grammar 'missing delimiters' "$nameLine`n$descriptionLine`nRead." @('missing YAML front matter')
Grammar 'malformed YAML' "---`n[`n---`nRead." @('invalid YAML subset')
Grammar 'sequence mapping' "---`n- list`n---`nRead." @('invalid YAML subset')
Grammar 'wrong name' ((Front @('name: wrong-name', $descriptionLine)) + 'Read.') @('name must match the folder')
Grammar 'wrong name case' ((Front @('name: Example-Skill', $descriptionLine)) + 'Read.') @('name must match the folder')
Grammar 'duplicate name' ((Front @($nameLine, 'name: wrong', $descriptionLine)) + 'Read.') @("duplicate front matter key 'name'")
Grammar 'unsupported key' ((Front @($nameLine, $descriptionLine, 'unexpected: value')) + 'Read.') @("unsupported front matter key 'unexpected'")
Grammar 'empty description' ((Front @($nameLine, "description: ''")) + 'Read.') @('invalid description')
Grammar 'angle brackets' ((Front @($nameLine, 'description: <unsafe> Use when testing.')) + 'Read.') @('invalid description')
Grammar 'description over 1024 code points' ((Front @($nameLine, ('description: Use when ' + ('x' * 1016)))) + 'Read.') @('invalid description')
Grammar 'description at 1024 code points' ((Front @($nameLine, ('description: Use when ' + ('x' * 1015)))) + 'Read.')
$rune = [char]::ConvertFromUtf32(0x1f4d8)
Grammar 'Unicode code-point limit' ((Front @($nameLine, ('description: Use when ' + ($rune * 1015)))) + 'Read.')
Grammar 'Unicode code-point overflow' ((Front @($nameLine, ('description: Use when ' + ($rune * 1016)))) + 'Read.') @('invalid description')
Grammar 'empty instructions' $valid @('empty skill instructions')
Grammar 'unfinished description' ((Front @($nameLine, "description: '[TODO: finish] Use when testing.'")) + 'Read.') @('unfinished description')
Grammar 'unfinished body' ($valid + "[TODO: finish]`n") @('unfinished instructions')
Grammar 'TODO example in a fence' ($valid + $f3 + "text`n[TODO: example]`n" + $f3)
Grammar 'TODO after an example' ($valid + $f3 + "text`nexample`n" + $f3 + "`n[TODO: finish]") @('unfinished instructions')
Grammar 'TODO after line-leading inline code' ($valid + $f3 + 'literal' + $f3 + "`n`n[TODO: finish]") @('unfinished instructions')
Grammar 'line-leading same-line backtick span' ($valid + $f3 + '[TODO: example]' + $f3)
Grammar 'tilde info permits backticks' ($valid + "~~~info${t}literal`n[TODO: example]`n~~~")
Grammar 'four-space opener does not hide TODO' ($valid + '    ' + $f3 + "text`n`n[TODO: finish]") @('unfinished instructions')
Grammar 'tab opener does not hide TODO' ($valid + "`t" + $f3 + "text`n`n[TODO: finish]") @('unfinished instructions')
Grammar 'four-space closer leaves the fence open' ($valid + $f3 + "text`n    " + $f3 + "`n[TODO: example]`n" + $f3)
Grammar 'tab closer leaves the fence open' ($valid + $f3 + "text`n`t" + $f3 + "`n[TODO: example]`n" + $f3)
Grammar 'three-space fence boundary' ($valid + '   ' + $f3 + "text`n[TODO: example]`n   " + $f3)
Grammar 'tilde list fence' ($valid + "- ~~~~text`n[TODO: example]`n  ~~~~")
Grammar 'short fence stays open' ($valid + '````text' + "`n" + $f3 + "`n[TODO: example]`n" + '````')
Grammar 'nested mapping refused' ((Front @($nameLine, $descriptionLine, "metadata:`n  nested:`n    key: value")) + 'Read.') @('invalid YAML subset')
Grammar 'metadata scalar refused' ((Front @($nameLine, $descriptionLine, 'metadata: invalid-scalar')) + 'Read.') @('metadata requires an indented scalar mapping')
Grammar 'license mapping refused' ((Front @($nameLine, $descriptionLine, "license:`n  nested: value")) + 'Read.') @('invalid YAML subset')
Grammar 'mapping description refused' ((Front @($nameLine, "description:`n  nested: value")) + 'Read.') @('invalid YAML subset')
Grammar 'flow collection refused' ((Front @($nameLine, 'description: [one, two]')) + 'Read.') @('invalid YAML subset')
Grammar 'tag refused' ((Front @($nameLine, 'description: !!str unsafe')) + 'Read.') @('invalid YAML subset')
Grammar 'anchor refused' ((Front @($nameLine, 'description: &anchor text')) + 'Read.') @('invalid YAML subset')
Grammar 'alias refused' ((Front @($nameLine, 'description: *anchor')) + 'Read.') @('invalid YAML subset')
Grammar 'malformed quote' ((Front @($nameLine, "description: 'unclosed")) + 'Read.') @('invalid YAML subset')
Grammar 'bad JSON escape' ((Front @($nameLine, 'description: "bad\q"')) + 'Read.') @('invalid YAML subset')
Grammar 'invalid block indentation' ((Front @($nameLine, "description: |`n one space")) + 'Read.') @('invalid YAML subset')
foreach ($typed in @('123', 'true', 'yes', 'null', '2026-10-28', '2026-10-28T09:00:00Z', '2026-10-28 9:00:00 +02:30', '2026-10-28t09:00:00.25-08:00', '1.5', '0x10', '.inf', 'off')) {
    Grammar "typed $typed is not a string" ((Front @($nameLine, "description: $typed")) + 'Read.') @('invalid description')
}
# G3: an unclosed fence names its line in the file, and the text after it is still checked.
Grammar 'unclosed backtick fence' ($valid + $f3 + "text`nexample") @('SKILL.md:5: unclosed code fence (opened with ```)')
Grammar 'unclosed tilde fence' ($valid + "~~~~`nexample") @('SKILL.md:5: unclosed code fence (opened with ~~~~)')
Grammar 'unclosed fence names its own line' ($valid + "Intro.`n`n" + $f3 + "text`nexample") @('SKILL.md:7: unclosed code fence')
Grammar 'unclosed fence line after multi-line front matter' ("---`nname: example-skill`ndescription: >-`n  Folded`n  text. Use when testing.`n---`n" + $f3 + "`nexample") @('SKILL.md:7: unclosed code fence')
Grammar 'unclosed fence in CRLF text' (($valid + $f3 + "text`nexample").Replace("`n", "`r`n")) @('SKILL.md:5: unclosed code fence')
Grammar 'shorter closing marker leaves a fence unclosed' ($valid + '````text' + "`nexample`n" + $f3) @('SKILL.md:5: unclosed code fence')
Grammar 'placeholder after an unclosed fence is still reported' ($valid + $f3 + "text`nexample`n[TODO: finish]") @('SKILL.md:5: unclosed code fence', 'unfinished instructions')
Grammar 'fence closed by a longer marker' ($valid + $f3 + "text`n[TODO: example]`n" + '`````')
Grammar 'fences in sequence' ($valid + $f3 + "text`nexample`n" + $f3 + "`ntext`n~~~`n[TODO: example]`n~~~")
Grammar 'line-leading inline code is not an unclosed fence' ($valid + $f3 + 'literal' + $f3 + "`nRead.")
Grammar 'indented marker is not an unclosed fence' ($valid + '    ' + $f3 + "`nRead.")
# G4: the description contains the case-sensitive words "Use when".
Grammar 'G4 description without the clause' ((Front @($nameLine, 'description: Read the owning contract.')) + 'Read.') @($g4)
Grammar 'G4 lowercase use when' ((Front @($nameLine, 'description: Read it. use when testing.')) + 'Read.') @($g4)
Grammar 'G4 Use for is not Use when' ((Front @($nameLine, 'description: Read it. Use for testing.')) + 'Read.') @($g4)
Grammar 'G4 two spaces are not the clause' ((Front @($nameLine, 'description: Read it. Use  when testing.')) + 'Read.') @($g4)
Grammar 'G4 the clause may be followed by another sentence' ((Front @($nameLine, 'description: Use when testing. Then read the contract.')) + 'Read.')
Grammar 'G4 a folded block joins the clause' ((Front @($nameLine, "description: >-`n  Read the contract. Use`n  when testing.")) + 'Read.')
Grammar 'G4 a literal block keeps the break inside the clause' ((Front @($nameLine, "description: |`n  Read the contract. Use`n  when testing.")) + 'Read.') @($g4)
Grammar 'G4 is reported with the other problems' ((Front @('name: wrong-name', 'description: Read it.')) + "[TODO: finish]") @('name must match the folder', $g4, 'unfinished instructions')
foreach ($block in @(
        @{ Name = 'literal keeps one final newline'; Text = "description: |`n  first`n  second"; Expected = "first`nsecond`n" },
        @{ Name = 'literal strip'; Text = "description: |-`n  first`n  second"; Expected = "first`nsecond" },
        @{ Name = 'folded paragraphs'; Text = "description: >-`n  first`n  second`n`n  third"; Expected = "first second`nthird" },
        @{ Name = 'folded keeps more-indented lines'; Text = "description: >-`n  first`n`n    indented`n  last"; Expected = "first`n`n  indented`nlast" },
        @{ Name = 'literal keep'; Text = "description: |+`n  first`n`n"; Expected = "first`n`n`n" })) {
    $blockText = $block.Text
    $blockExpected = $block.Expected
    Case "G1 grammar: block scalar, $($block.Name)" {
        $metadata = & $guidanceModule { param($Text) ConvertFrom-SkillMetadata $Text } $blockText
        Require ($metadata.description -ceq $blockExpected) "The block scalar was read as '$($metadata.description)'."
    }
}

#endregion
#region Markdown structure and references (RedXe and RedTilde package suites)

Case 'G3 masked prose keeps every line number and length and hides only code' {
    $sample = "# Title ${t}x`n`n- item with ${t}code that spans`n  two lines${t} and ${t}more${t} [a](b.md)`n`n${f3}text`n[hidden](c.md)`n${f3}`nafter [d](e.md)`r`nend"
    $prose = & $guidanceModule { param($Text) Get-GuidanceProse $Text } $sample
    $source = $sample.Replace("`r`n", "`n") -split "`n"
    $masked = $prose.Text -split "`n"
    Require ($masked.Count -eq $source.Count -and -not @(0..($source.Count - 1) | Where-Object { $masked[$_].Length -ne $source[$_].Length }).Count) 'Masked prose changed the line structure.'
    Require (-not $prose.Text.Contains('hidden') -and -not $prose.Text.Contains('spans') -and -not $prose.Text.Contains('more') -and
        $prose.Text.Contains('[a](b.md)') -and $prose.Text.Contains('[d](e.md)') -and -not $prose.Unclosed.Count) "Masked prose hid or kept the wrong text: $($prose.Text)"
    $unclosed = & $guidanceModule { param($Text) Get-GuidanceProse $Text } "kept [a](b.md)`n${f3}text`nstill [c](d.md)"
    Require ($unclosed.Unclosed.Count -eq 1 -and $unclosed.Unclosed[0].Line -eq 2 -and $unclosed.Unclosed[0].Token -ceq $f3 -and $unclosed.Text.Contains('[c](d.md)')) 'An unclosed fence was not reported once with the text after it kept.'
}

Case 'G6 a valid product passes with its skill and reference counts' {
    $root = New-Product
    $result = Get-CiAgentGuidanceResult -Root $root
    Require (-not $result.Problems.Count) "Unexpected problems: $($result.Problems -join ' | ')"
    Require ($result.Skills -eq 1 -and $result.References -eq 4 -and $result.Guidance -eq 1) "Counted $($result.Skills) skills, $($result.References) references and $($result.Guidance) AGENTS.md files."
}
Case 'G6 balanced parentheses in a destination' { $r = New-Product; Put $r 'Specs/contract(v1).md' '# Versioned'; Skill $r '[Balanced](../../../Specs/contract(v1).md)'; Valid $r }
Case 'G6 escaped parentheses in a destination' { $r = New-Product; Put $r 'Specs/contract(v1).md' '# Versioned'; Skill $r '[Escaped](../../../Specs/contract\(v1\).md)'; Valid $r }
Case 'G6 a missing balanced destination is still checked' { $r = New-Product; Skill $r '[Missing](../../../Specs/missing(v1).md)'; [void](Problem $r 'missing local reference: ../../../Specs/missing(v1).md (G6)') }
Case 'G6 an inline-code pseudo-link is ignored' { $r = New-Product; Skill $r ("${t}[example](missing.md)${t} and " + $contract); Valid $r }
Case 'G6 double-backtick code spans hide pseudo-links' { $r = New-Product; Skill $r "The syntax is ${t}[example](missing.md)${t} or ${t}${t} ${t}[another](absent.md)${t} ${t}${t}."; Valid $r }
Case 'G6 a matching multi-line code span is ignored' { $r = New-Product; Skill $r ("${t}${t}inline ${t} [example](missing.md)`nstill code${t}${t} and " + $contract); Valid $r }
Case 'G6 a soft line break inside a code span hides a pseudo-link' { $r = New-Product; Skill $r "Read ${t}soft`n[example](missing.md)${t} within one paragraph."; Valid $r }
Case 'G6 line-leading triple backticks cannot hide later paragraphs' { $r = New-Product; Skill $r ($f3 + 'literal' + $f3 + "`n`n[Missing](missing.md)"); [void](Problem $r 'missing local reference: missing.md') }
Case 'G6 a line-leading triple-backtick code span stays inline code' { $r = New-Product; Skill $r ($f3 + '[example](missing.md)' + $f3 + "`n`n" + $contract); Valid $r }
Case 'G6 a tilde fence permits a backtick in its info string' { $r = New-Product; Skill $r ("~~~info${t}`n[Example](missing.md)`n~~~`n" + $contract); Valid $r }
Case 'G6 a four-space-indented marker does not open a fence over later prose' { $r = New-Product; Skill $r ('    ' + $f3 + "`n`n[Missing](missing.md)"); [void](Problem $r 'missing local reference: missing.md') }
Case 'G6 a tab-indented marker does not open a fence over later prose' { $r = New-Product; Skill $r ("`t" + $f3 + "`n`n[Missing](missing.md)"); [void](Problem $r 'missing local reference: missing.md') }
Case 'G6 an over-indented marker does not close a fence' { $r = New-Product; Skill $r ($f3 + "text`n    " + $f3 + "`n[Example](missing.md)`n" + $f3 + "`n" + $contract); Valid $r }
Case 'G6 a three-space fence boundary hides its example' { $r = New-Product; Skill $r ('   ' + $f3 + "text`n[Illustration](missing.md)`n   " + $f3); Valid $r }
Case 'G6 an illustrative markdown fence is not a reference' { $r = New-Product; Skill $r ($f3 + "markdown`n[illustrative](missing.md)`n" + $f3); Valid $r }
Case 'G6 unmatched code delimiters cannot cross a blank line' { $r = New-Product; Skill $r ("first ${t}`n`n[Missing](missing.md)`n`nlast ${t}"); [void](Problem $r 'missing local reference: missing.md') }
Case 'G6 unmatched code delimiters cannot cross a whitespace-only line' { $r = New-Product; Skill $r ("first ${t}`n `t`n[Missing](missing.md)`n`nlast ${t}"); [void](Problem $r 'missing local reference: missing.md') }
Case 'G6 a parenthesized title does not hide a missing target' { $r = New-Product; Skill $r '[Read](missing.md (Owning contract))'; [void](Problem $r 'missing local reference: missing.md') }
Case 'G6 a valid parenthesized title' { $r = New-Product; Put $r 'Specs/contract(v1).md' '# Versioned'; Skill $r '[Read](../../../Specs/contract(v1).md (Owning contract))'; Valid $r }
Case 'G6 a continued reference definition checks its target' { $r = New-Product; Skill $r "[procedure]:`n  references/missing.md`n[Read][procedure]"; [void](Problem $r 'missing local reference: references/missing.md') }
Case 'G6 a valid continued reference definition' { $r = New-Product; Skill $r "[procedure]:`n  <../../../Specs/contract with spaces.md>`n[Read][procedure]"; Valid $r }
Case 'G6 a continued definition with a parenthesized title' { $r = New-Product; Put $r 'Specs/contract.md' '# Contract'; Skill $r "[owner]:`n  ../../../Specs/contract.md (Owning contract)`nRead [owner][]."; Valid $r }
Case 'G6 an unused continued definition still checks its target' { $r = New-Product; Skill $r "[owner]:`n  missing.md"; [void](Problem $r 'missing local reference: missing.md') }
Case 'G6 a missing reference-style destination' { $r = New-Product; Skill $r '[contract]: references/missing.md'; [void](Problem $r 'missing local reference: references/missing.md') }
Case 'G6 a valid reference-style destination with spaces' { $r = New-Product; Skill $r ("[contract]: <../../../Specs/contract with spaces.md>`n[Named contract][contract]"); Valid $r }
Case 'G6 an encoded reference-style destination' { $r = New-Product; Skill $r "Read [contract][owner].`n[owner]: ../../../Specs/contract%20with%20spaces.md"; Valid $r }
Case 'G6 a collapsed reference with another letter case' { $r = New-Product; Skill $r "Read [OWNER][].`n[owner]: ../../../Specs/contract%20with%20spaces.md"; Valid $r }
Case 'G6 every reference definition is checked, even for a repeated label' {
    # RedPrism used the first definition of a label only; the RedXe parser checks every destination.
    $r = New-Product; Skill $r "Read [contract][owner].`n[owner]: ../../../Specs/contract%20with%20spaces.md`n[OWNER]: ../../../Specs/absent.md"
    [void](Problem $r 'missing local reference: ../../../Specs/absent.md')
}
foreach ($literalName in @('guide#v1.md', 'literal%20.md')) {
    $fileName = $literalName
    Case "G6 a file URI keeps the literal file name $fileName" {
        $r = New-Product; Put $r "Specs/$fileName" '# Literal'
        Skill $r ('[File](' + (ConvertTo-FileUri (Join-Path $r "Specs/$fileName")) + ')'); Valid $r
    }
}
Case 'G6 a protocol-relative URL is not a local target' { $r = New-Product; Skill $r '[Network](//example.invalid/reference)'; Valid $r }
Case 'G6 a footnote definition is not a reference' { $r = New-Product; Skill $r "Claim[^1].`n`n[^1]: See the note, not a path.`n"; Valid $r }
Case 'G6 an indented footnote definition is not a reference' { $r = New-Product; Skill $r "Claim[^note].`n`n   [^note]: Indented note.`n"; Valid $r }
Case 'G6 a link inside a footnote is still checked' { $r = New-Product; Skill $r "Claim[^1].`n`n[^1]: See [missing](missing.md).`n"; [void](Problem $r 'missing local reference: missing.md') }
Case 'G6 a reference definition that is not a footnote is checked' { $r = New-Product; Skill $r '[note]: missing.md'; [void](Problem $r 'missing local reference: missing.md') }
foreach ($suffixValue in @('?plain=1', '?plain=1#scope', '#scope?x', '?a=b&c=d')) {
    $suffix = $suffixValue
    Case "G6 the suffix $suffix is not part of the path" {
        $r = New-Product; Skill $r ('[Contract](../../../Specs/contract%20with%20spaces.md' + $suffix + ')')
        $result = Get-CiAgentGuidanceResult -Root $r
        Require (-not $result.Problems.Count -and $result.References -eq 4) "The suffix $suffix changed the result: $($result.References) references, $($result.Problems -join ' | ')"
    }
}
Case 'G6 a query suffix does not hide a missing target' { $r = New-Product; Skill $r '[Missing](references/missing.md?plain=1#scope)'; [void](Problem $r 'missing local reference: references/missing.md') }
Case 'G6 a query-only link names the same document' {
    $r = New-Product; Skill $r '[Same page](?tab=readme) [Section](#scope)'
    $result = Get-CiAgentGuidanceResult -Root $r
    Require (-not $result.Problems.Count -and $result.References -eq 3) 'A query-only link was counted as a local reference.'
}
Case 'G6 a directory target inside the repository is contained' { $r = New-Product; Skill $r 'Read [repository](../../..).'; Valid $r }
Case 'G6 a contained absolute path is checked' { $r = New-Product; Skill $r ('Read [contract](' + (Join-Path $r 'Specs/contract with spaces.md').Replace('\', '/').Replace(' ', '%20') + ').'); Valid $r }
Case 'G6 a contained file URI is checked' { $r = New-Product; Skill $r ('Read [contract](' + (ConvertTo-FileUri (Join-Path $r 'Specs/contract with spaces.md')) + ').'); Valid $r }
Case 'G6 a missing absolute path is refused' { $r = New-Product; Skill $r ('Read [missing](' + (Join-Path $r 'Specs/absent.md').Replace('\', '/') + ').'); [void](Problem $r 'missing local reference:') }
Case 'G6 a missing file URI is refused' { $r = New-Product; Skill $r ('Read [missing](' + (ConvertTo-FileUri (Join-Path $r 'Specs/absent.md')) + ').'); [void](Problem $r 'missing local reference:') }
Case 'G6 a missing skill reference' { $r = New-Product; Skill $r '[Missing](references/missing.md)'; [void](Problem $r '.agents/skills/example-skill/SKILL.md:5: missing local reference: references/missing.md (G6)') }
Case 'G6 a reference to another checkout escapes the repository' { $r = New-Product; Skill $r '[Foreign](../../../../foreign.md)'; [void](Problem $r 'reference escapes this repository: ../../../../foreign.md (G6)') }
Case 'G6 an absolute path outside the root escapes the repository' { $r = New-Product; Skill $r ('[Absolute](' + (Join-Path $runRoot 'foreign.md').Replace('\', '/') + ')'); [void](Problem $r 'reference escapes this repository') }
Case 'G6 a file URI outside the root escapes the repository' { $r = New-Product; Skill $r ('[File URI](' + (ConvertTo-FileUri (Join-Path $runRoot 'foreign.md')) + ')'); [void](Problem $r 'reference escapes this repository') }
Case 'G6 a fenced example is not a package reference' { $r = New-Product; Skill $r ($f3 + "text`n[Example](missing.md)`n" + $f3 + "`n" + $contract); Valid $r }
Case 'G6 supporting Markdown is checked from its own folder' {
    $r = New-Product; Put $r '.agents/skills/example-skill/references/procedure.md' '[Missing](missing-contract.md)'
    [void](Problem $r '.agents/skills/example-skill/references/procedure.md:1: missing local reference: missing-contract.md')
    Put $r '.agents/skills/example-skill/references/procedure.md' '[Contract](../../../../Specs/contract%20with%20spaces.md)'; Valid $r
}
Case 'G6 the root AGENTS.md is checked' { $r = New-Product; Put $r 'AGENTS.md' "[Missing](missing-guidance.md)`n[example-skill](.agents/skills/example-skill/SKILL.md)"; [void](Problem $r 'AGENTS.md:1: missing local reference: missing-guidance.md') }
Case 'G6 the pointers are checked' { $r = New-Product; Put $r 'CLAUDE.md' "Read [AGENTS.md](AGENTS.md) and [x](missing.md)."; [void](Problem $r 'CLAUDE.md:1: missing local reference: missing.md') }
foreach ($caseLink in @(
        @{ Name = 'file name'; Link = '../../../Specs/Contract%20With%20Spaces.md'; Requested = 'Specs/Contract With Spaces.md'; OnDisk = 'Specs/contract with spaces.md' },
        @{ Name = 'folder'; Link = '../../../specs/contract%20with%20spaces.md'; Requested = 'specs/contract with spaces.md'; OnDisk = 'Specs/contract with spaces.md' },
        @{ Name = 'folder link'; Link = '../../../specs/'; Requested = 'specs/'; OnDisk = 'Specs' },
        @{ Name = 'root file'; Link = '../../../agents.md'; Requested = 'agents.md'; OnDisk = 'AGENTS.md' })) {
    $caseValue = $caseLink
    Case "G6 a $($caseValue.Name) that differs only in letter case is refused" {
        if (-not $caseInsensitive) { Skip 'this file system is case-sensitive, where a wrong-case link is already missing' }
        $r = New-Product; Skill $r ('[Link](' + $caseValue.Link + ')')
        [void](Problem $r "local reference differs in case from the file on disk: $($caseValue.Requested) (on disk: $($caseValue.OnDisk))")
    }
}
Case 'G6 links that match the on-disk letter case are accepted' { $r = New-Product; Skill $r '[Folder](../../../Specs/) [File](../../../Specs/contract%20with%20spaces.md) [Root](../../../AGENTS.md)'; Valid $r }
foreach ($stray in @(
        @{ Name = 'list items'; Text = "- uses $t for quoting`n- see [x](missing.md) and ${t}code$t"; Line = 6 },
        @{ Name = 'ordered list items'; Text = "1. uses $t`n2. see [x](missing.md) and ${t}code$t"; Line = 6 },
        @{ Name = 'a heading'; Text = "# Heading with a $t stray`nsee [x](missing.md) and ${t}code$t"; Line = 6 },
        @{ Name = 'a table row'; Text = "| uses $t |`n| [x](missing.md) ${t}code$t |"; Line = 6 },
        @{ Name = 'a block quote edge'; Text = "uses $t`n> see [x](missing.md) and ${t}code$t"; Line = 6 },
        @{ Name = 'a thematic break'; Text = "uses $t`n***`nsee [x](missing.md) and ${t}code$t"; Line = 7 })) {
    $strayValue = $stray
    Case "G6 a stray backtick cannot pair across $($strayValue.Name)" { $r = New-Product; Skill $r $strayValue.Text; [void](Problem $r "SKILL.md:$($strayValue.Line): missing local reference: missing.md") }
}
foreach ($span in @(
        @{ Name = 'a list item'; Text = "- item with ${t}code that`n  continues [x](missing.md)$t still code`n- next" },
        @{ Name = 'a block quote'; Text = "> quote ${t}a`n> b [x](missing.md)$t c" },
        @{ Name = 'a paragraph'; Text = "plain ${t}a`nb [x](missing.md)$t c" },
        @{ Name = 'a heading'; Text = "# Heading ${t}a [x](missing.md)$t c" },
        @{ Name = 'a table row'; Text = "| ${t}a [x](missing.md)$t |" })) {
    $spanValue = $span
    Case "G6 a code span still hides a link inside $($spanValue.Name)" { $r = New-Product; Skill $r $spanValue.Text; Valid $r }
}

Case 'G3 an unclosed fence is reported once with its line, and the text after it is still checked' {
    $r = New-Product; Skill $r ($f3 + "text`nexample`n[Missing](missing.md)`n")
    $problems = Problem $r '.agents/skills/example-skill/SKILL.md:5: unclosed code fence (opened with ```) (G3)'
    Require (@($problems | Where-Object { $_.Contains('unclosed code fence') }).Count -eq 1) "The unclosed fence was reported more than once: $($problems -join ' | ')"
    [void](Problem $r '.agents/skills/example-skill/SKILL.md:7: missing local reference: missing.md')
}
Case 'G3 an unclosed fence in supporting Markdown names that file' {
    $r = New-Product; Put $r '.agents/skills/example-skill/references/procedure.md' ("Intro.`n`n~~~~`n[Example](missing.md)")
    [void](Problem $r 'references/procedure.md:3: unclosed code fence (opened with ~~~~)')
    Put $r '.agents/skills/example-skill/references/procedure.md' ("Intro.`n`n~~~~`n[Example](missing.md)`n~~~~"); Valid $r
}
Case 'G3 an unclosed fence in a scoped AGENTS.md and a plan index is reported' {
    $r = New-Product; Put $r 'Tests/AGENTS.md' ($f3 + "`nexample"); Put $r '.agents/guidance.json' '{"schemaVersion":1,"files":["AGENTS.md","Tests/AGENTS.md"]}'
    Put $r 'Specs/Plans/WIP/README.md' "- [Example plan](Example_2026-11-19.md)`n~~~`nopen"
    [void](Problem $r 'Tests/AGENTS.md:1: unclosed code fence'); [void](Problem $r 'Specs/Plans/WIP/README.md:2: unclosed code fence')
}

#endregion
#region G2: reading

$little = [Text.UnicodeEncoding]::new($false, $true)
$plainSkill = $prefix + $contract
foreach ($encoding in @(
        @{ Name = 'SKILL.md with a UTF-8 byte order mark'; Relative = $skillPath; Bytes = [byte[]](@(0xEF, 0xBB, 0xBF) + $utf8.GetBytes($plainSkill)); Expect = 'SKILL.md: expected UTF-8 without a byte order mark'; Valid = $plainSkill },
        @{ Name = 'SKILL.md in UTF-16'; Relative = $skillPath; Bytes = [byte[]]($little.GetPreamble() + $little.GetBytes($plainSkill)); Expect = 'SKILL.md: expected UTF-8 but found a UTF-16 or UTF-32 byte order mark'; Valid = $plainSkill },
        @{ Name = 'SKILL.md in UTF-16 without a byte order mark'; Relative = $skillPath; Bytes = [Text.UnicodeEncoding]::new($false, $false).GetBytes($plainSkill); Expect = 'SKILL.md: expected UTF-8 text but found NUL bytes'; Valid = $plainSkill },
        @{ Name = 'supporting Markdown in UTF-16'; Relative = '.agents/skills/example-skill/references/procedure.md'; Bytes = [byte[]]($little.GetPreamble() + $little.GetBytes('# Procedure')); Expect = 'procedure.md: expected UTF-8 but found a UTF-16 or UTF-32 byte order mark'; Valid = '# Procedure' },
        @{ Name = 'a pointer with invalid UTF-8'; Relative = 'CLAUDE.md'; Bytes = [byte[]](0x23, 0x20, 0xC3, 0x28); Expect = 'CLAUDE.md: expected UTF-8 but found invalid bytes'; Valid = $claude })) {
    $encodingValue = $encoding
    Case "G2 $($encodingValue.Name) is refused and named, and accepted as UTF-8" {
        $r = New-Product; PutBytes $r $encodingValue.Relative $encodingValue.Bytes
        [void](Problem $r "$($encodingValue.Expect)")
        Put $r $encodingValue.Relative $encodingValue.Valid; Valid $r
    }
}
foreach ($bomRelative in @('.agents/skills/example-skill/references/procedure.md', 'AGENTS.md')) {
    $bomPath = $bomRelative
    Case "G2 a UTF-8 byte order mark is harmless in $bomPath" {
        $r = New-Product
        $text = if ($bomPath -ceq 'AGENTS.md') { [IO.File]::ReadAllText((Join-Path $r 'AGENTS.md')) } else { '# Guidance' }
        PutBytes $r $bomPath ([byte[]](@(0xEF, 0xBB, 0xBF) + $utf8.GetBytes($text))); Valid $r
    }
}
Case 'G2 an unreadable file is reported by name and its text is never another file''s' {
    $r = New-Product; Skill $r '[Missing](missing.md)'; PutBytes $r 'AGENTS.md' ([byte[]](0xC3, 0x28))
    $problems = Problem $r 'AGENTS.md: expected UTF-8 but found invalid bytes'
    Require (-not @($problems | Where-Object { $_ -match '^AGENTS\.md:\d' }).Count) "An unreadable file was checked with another file's text: $($problems -join ' | ')"
}
Case 'G2 one unreadable skill does not stop the others' {
    $r = New-Product
    Put $r '.agents/skills/aaa-valid/SKILL.md' ($prefix.Replace('example-skill', 'aaa-valid') + 'Read.')
    PutBytes $r '.agents/skills/zzz-unreadable/SKILL.md' ([byte[]](0xC3, 0x28))
    Put $r '.agents/skills/mmm-wrong/SKILL.md' ($prefix + 'Read.')
    $problems = Problem $r '.agents/skills/zzz-unreadable/SKILL.md: expected UTF-8 but found invalid bytes'
    [void](Problem $r '.agents/skills/mmm-wrong/SKILL.md: name must match the folder')
    Require (-not @($problems | Where-Object { $_.StartsWith('.agents/skills/aaa-valid/SKILL.md', [StringComparison]::Ordinal) }).Count) "The valid skill was reported: $($problems -join ' | ')"
}
Case 'G2 an empty guidance file is refused' { $r = New-Product; Put $r '.agents/skills/example-skill/references/empty.md' " `n"; [void](Problem $r '.agents/skills/example-skill/references/empty.md: is empty (G2)') }
Case 'G2 a file in use is reported by name' {
    if (-not $IsWindows) { Skip 'an exclusive file share is a Windows lock' }
    $r = New-Product; Put $r '.agents/skills/example-skill/references/locked.md' '# Locked'
    $lease = [IO.File]::Open((Join-Path $r '.agents/skills/example-skill/references/locked.md'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { [void](Problem $r 'references/locked.md: cannot be read') } finally { $lease.Dispose() }
}

#endregion
#region G1 and G5: skills in the repository

Case 'G1 a hidden package is still validated' {
    $r = New-Product; Put $r '.agents/skills/hidden-skill/SKILL.md' 'Malformed hidden skill'
    [IO.File]::SetAttributes((Join-Path $r '.agents/skills/hidden-skill'), [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::Directory)
    [void](Problem $r '.agents/skills/hidden-skill/SKILL.md: missing YAML front matter (G1)')
}
Case 'G1 a hidden package without SKILL.md is refused, and a valid hidden one passes' {
    $r = New-Product; [void][IO.Directory]::CreateDirectory((Join-Path $r '.agents/skills/hidden-skill'))
    [IO.File]::SetAttributes((Join-Path $r '.agents/skills/hidden-skill'), [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::Directory)
    [void](Problem $r '.agents/skills/hidden-skill: missing SKILL.md or empty file (G1)')
    Put $r '.agents/skills/hidden-skill/SKILL.md' ($prefix.Replace('example-skill', 'hidden-skill') + '[Missing](missing.md)')
    Put $r 'AGENTS.md' "[example-skill](.agents/skills/example-skill/SKILL.md) [hidden-skill](.agents/skills/hidden-skill/SKILL.md)"
    [void](Problem $r '.agents/skills/hidden-skill/SKILL.md:5: missing local reference: missing.md')
    Put $r '.agents/skills/hidden-skill/SKILL.md' ($prefix.Replace('example-skill', 'hidden-skill') + 'Read.'); Valid $r
}
Case 'G1 empty instructions are refused through the repository check' { $r = New-Product; Put $r $skillPath $prefix; [void](Problem $r "$skillPath`: empty skill instructions (G1)") }
Case 'G1 an empty SKILL.md is one problem' {
    $r = New-Product; Put $r $skillPath ''
    $problems = Problem $r "$skillPath`: missing SKILL.md or empty file (G1)"
    Require ($problems.Count -eq 1) "An empty SKILL.md was reported more than once: $($problems -join ' | ')"
}
Case 'G4 is reported through the repository check' {
    $r = New-Product; Put $r $skillPath ("---`nname: example-skill`ndescription: Read the contract.`n---`n" + $contract)
    [void](Problem $r "$skillPath`: $g4; add a sentence that starts with 'Use when' (G4)")
}
Case 'G5 a missing .agents/skills folder is refused' { $r = New-Product; Remove $r '.agents/skills'; [void](Problem $r '.agents/skills: missing; skills live in .agents/skills (G5)') }
Case 'G5 an .agents/skills folder without a package is refused' { $r = New-Product; Remove $r '.agents/skills/example-skill'; [void](Problem $r '.agents/skills: holds no skill package (G5)') }
Case 'G5 a skill outside .agents/skills is refused' { $r = New-Product; Put $r '.github/skills/cpp-build/SKILL.md' ($prefix.Replace('example-skill', 'cpp-build') + 'Read.'); [void](Problem $r '.github/skills/cpp-build/SKILL.md: is a skill outside .agents/skills') }
Case 'G5 a SKILL.md below a skill folder is not a skill' { $r = New-Product; Put $r '.agents/skills/example-skill/nested/SKILL.md' ($prefix + 'Read.'); [void](Problem $r '.agents/skills/example-skill/nested/SKILL.md: is a skill outside .agents/skills') }

#endregion
#region G7: reparse points

Case 'G7 a linked SKILL.md is refused before it is read' {
    $r = New-Product; PutBytes $r 'fixtures/not-utf8.dat' ([byte[]]@(0xFF)); Remove $r $skillPath
    New-FileLink (Join-Path $r $skillPath) (Join-Path $r 'fixtures/not-utf8.dat')
    $problems = Problem $r "$skillPath`: is a reparse point; agent guidance is never read through a link (G7)"
    Require (-not @($problems | Where-Object { $_.Contains('expected UTF-8') }).Count) "The linked file was read: $($problems -join ' | ')"
}
Case 'G7 a linked root is refused before anything below it is listed' {
    $folder = New-CaseFolder; $real = New-Product (Join-Path $folder 'real'); PutBytes $real 'AGENTS.md' ([byte[]](0xC3, 0x28))
    New-Junction (Join-Path $folder 'alias') $real
    $result = Get-CiAgentGuidanceResult -Root (Join-Path $folder 'alias')
    Require ($result.Problems.Count -eq 1 -and $result.Problems[0].Contains('the repository root is a reparse point') -and $result.Skills -eq 0) "A linked root was traversed: $($result.Problems -join ' | ')"
}
Case 'G7 a junction above the root is accepted' {
    $folder = New-CaseFolder; [void](New-Product (Join-Path $folder 'real/product'))
    New-Junction (Join-Path $folder 'alias') (Join-Path $folder 'real')
    Valid (Join-Path $folder 'alias/product')
}
Case 'G7 a linked .agents/skills is refused and not listed' {
    $folder = New-CaseFolder; $source = New-Product (Join-Path $folder 'source'); $r = New-Product (Join-Path $folder 'product')
    Remove $r '.agents/skills'; New-Junction (Join-Path $r '.agents/skills') (Join-Path $source '.agents/skills')
    $result = Get-CiAgentGuidanceResult -Root $r
    Require ($result.Skills -eq 0 -and @($result.Problems | Where-Object { $_.StartsWith('.agents/skills: is a reparse point', [StringComparison]::Ordinal) }).Count) "A linked skills folder was traversed: $($result.Problems -join ' | ')"
}
Case 'G7 a link inside a skill package is refused' {
    $r = New-Product; Put $r 'outside-docs/procedure.md' '# Elsewhere'
    New-Junction (Join-Path $r '.agents/skills/example-skill/references') (Join-Path $r 'outside-docs')
    [void](Problem $r '.agents/skills/example-skill/references: is a reparse point')
}
Case 'G7 a reference through a linked folder is refused' {
    $r = New-Product; Put $r 'fixtures/docs/contract.md' '# Ordinary target'
    New-Junction (Join-Path $r 'Specs/mirror') (Join-Path $r 'fixtures/docs')
    Skill $r 'Read [contract](../../../Specs/mirror/contract.md).'
    [void](Problem $r 'SKILL.md:5: reference passes through the reparse point Specs/mirror: ../../../Specs/mirror/contract.md (G7)')
}
Case 'G7 a linked .github folder refuses the pointer behind it' {
    $folder = New-CaseFolder; $r = New-Product (Join-Path $folder 'product'); Put $folder 'pointer/copilot-instructions.md' "Read [../AGENTS.md](../AGENTS.md).`n"
    Remove $r '.github'; New-Junction (Join-Path $r '.github') (Join-Path $folder 'pointer')
    [void](Problem $r '.github: is a reparse point')
}
Case 'G7 the scoped-guidance walk does not enter a link outside .agents' {
    $folder = New-CaseFolder; $r = New-Product (Join-Path $folder 'product'); Put $folder 'elsewhere/AGENTS.md' '# Not this repository''s guidance'
    New-Junction (Join-Path $r 'linked') (Join-Path $folder 'elsewhere')
    Valid $r
}
Case 'G7 a linked AGENTS.md is refused' {
    $r = New-Product; Put $r 'fixtures/agents.txt' '# Elsewhere'
    New-FileLink (Join-Path $r 'Tests/AGENTS.md') (Join-Path $r 'fixtures/agents.txt')
    [void](Problem $r 'Tests/AGENTS.md: is a reparse point')
}

#endregion
#region G8: harness files

Case 'G8 agents/openai.yaml is refused, empty or not' {
    $r = New-Product; Put $r '.agents/skills/example-skill/agents/openai.yaml' ''
    [void](Problem $r '.agents/skills/example-skill/agents/openai.yaml: skill packages carry no harness UI metadata')
    Put $r '.agents/skills/example-skill/agents/openai.yaml' "interface:`n  display_name: Example"
    [void](Problem $r 'agents/openai.yaml: skill packages carry no harness UI metadata (register A-11); remove it (G8)')
    Remove $r '.agents/skills/example-skill/agents'; Valid $r
}
Case 'G8 only agents/openai.yaml of a package is a harness file' { $r = New-Product; Put $r '.agents/skills/example-skill/references/openai.yaml' 'data: 1'; Valid $r }

#endregion
#region G9: scoped-guidance inventory (RedTilde suite)

function New-ScopedProduct {
    $root = New-Product
    Put $root 'Tests/AGENTS.md' '# Scoped fixture guidance'
    Put $root '.agents/guidance.json' '{"schemaVersion":1,"files":["AGENTS.md","Tests/AGENTS.md"]}'
    return $root
}
Case 'G9 a valid inventory with scoped guidance' {
    $r = New-ScopedProduct; $result = Get-CiAgentGuidanceResult -Root $r
    Require (-not $result.Problems.Count -and $result.Guidance -eq 2) "Inventory accounting failed: $($result.Guidance), $($result.Problems -join ' | ')"
}
Case 'G9 a missing inventory is refused' { $r = New-Product; Remove $r '.agents/guidance.json'; [void](Problem $r '.agents/guidance.json: missing; the scoped-guidance inventory lists every AGENTS.md') }
Case 'G9 an inventory entry without its file is refused' { $r = New-ScopedProduct; Remove $r 'Tests/AGENTS.md'; [void](Problem $r '.agents/guidance.json: lists Tests/AGENTS.md, which is not an AGENTS.md of this repository (G9)') }
Case 'G9 an empty scoped guidance file is refused' { $r = New-ScopedProduct; Put $r 'Tests/AGENTS.md' ''; [void](Problem $r 'Tests/AGENTS.md: is empty (G2)') }
Case 'G9 a broken scoped-guidance route is refused' { $r = New-ScopedProduct; Put $r 'Tests/AGENTS.md' '[Missing](missing.md)'; [void](Problem $r 'Tests/AGENTS.md:1: missing local reference: missing.md (G6)') }
Case 'G9 new scoped guidance must enter the inventory' { $r = New-ScopedProduct; Put $r 'Common/AGENTS.md' '# Uninventoried scope'; [void](Problem $r 'Common/AGENTS.md: is not listed in the scoped-guidance inventory .agents/guidance.json (G9)') }
Case 'G9 the root AGENTS.md must be listed' { $r = New-ScopedProduct; Put $r '.agents/guidance.json' '{"schemaVersion":1,"files":["Tests/AGENTS.md"]}'; [void](Problem $r 'AGENTS.md: is not listed in the scoped-guidance inventory') }
Case 'G9 an inventoried scope path may contain spaces' {
    $r = New-ScopedProduct; Put $r 'Module Space/AGENTS.md' '# Scope with spaces'
    Put $r '.agents/guidance.json' '{"schemaVersion":1,"files":["AGENTS.md","Tests/AGENTS.md","Module Space/AGENTS.md"]}'; Valid $r
}
foreach ($badInventory in @(
        @{ Name = 'an escaping entry'; Json = '{"schemaVersion":1,"files":["AGENTS.md","../AGENTS.md"]}'; Expect = 'lists ../AGENTS.md, which is not a repository-relative path' },
        @{ Name = 'a backslash entry'; Json = '{"schemaVersion":1,"files":["AGENTS.md","Tests\\AGENTS.md"]}'; Expect = 'lists Tests\AGENTS.md, which is not a repository-relative path' },
        @{ Name = 'an entry that is not an AGENTS.md'; Json = '{"schemaVersion":1,"files":["AGENTS.md","Tests/README.md"]}'; Expect = 'lists Tests/README.md, which is not a repository-relative path' },
        @{ Name = 'a duplicate entry'; Json = '{"schemaVersion":1,"files":["AGENTS.md","AGENTS.md"]}'; Expect = 'lists AGENTS.md twice' },
        @{ Name = 'a string schema version'; Json = '{"schemaVersion":"1","files":["AGENTS.md"]}'; Expect = 'must be a JSON object with schemaVersion 1' },
        @{ Name = 'another schema version'; Json = '{"schemaVersion":2,"files":["AGENTS.md"]}'; Expect = 'must be a JSON object with schemaVersion 1' },
        @{ Name = 'an empty files array'; Json = '{"schemaVersion":1,"files":[]}'; Expect = 'must be a JSON object with schemaVersion 1' },
        @{ Name = 'files that are not an array'; Json = '{"schemaVersion":1,"files":"AGENTS.md"}'; Expect = 'must be a JSON object with schemaVersion 1' },
        @{ Name = 'invalid JSON'; Json = '{"schemaVersion":1,'; Expect = '.agents/guidance.json: is not valid JSON' })) {
    $inventoryValue = $badInventory
    Case "G9 the inventory refuses $($inventoryValue.Name)" { $r = New-Product; Put $r '.agents/guidance.json' $inventoryValue.Json; [void](Problem $r $inventoryValue.Expect) }
}
Case 'G9 generated trees and nested checkouts own no scoped guidance' {
    $r = New-Product; Put $r '.build/fixture/AGENTS.md' '# Generated, not owned guidance'
    Put $r 'nested/.git' 'gitdir: synthetic-fixture'; Put $r 'nested/AGENTS.md' '# Another checkout'
    Put $r 'other/.git/HEAD' 'ref: refs/heads/main'; Put $r 'other/AGENTS.md' '# Another checkout'
    Put $r '.git/AGENTS.md' '# Git metadata, not guidance'; Valid $r
}

#endregion
#region G10: index and pointers

Case 'G10 an unindexed skill is refused' { $r = New-Product; Put $r 'AGENTS.md' '# No index'; [void](Problem $r 'AGENTS.md: does not index the skill example-skill; link it as (.agents/skills/example-skill/SKILL.md) (G10)') }
Case 'G10 an index link in another form is refused' {
    $r = New-Product; Put $r 'AGENTS.md' '[example-skill](./.agents/skills/example-skill/SKILL.md)'
    [void](Problem $r 'AGENTS.md:1: links ./.agents/skills/example-skill/SKILL.md; the index links each skill as'); [void](Problem $r 'does not index the skill example-skill')
}
Case 'G10 the index links nothing else under .agents/skills' {
    $r = New-Product; Put $r '.agents/skills/example-skill/references/procedure.md' '# Procedure'
    Put $r 'AGENTS.md' "[example-skill](.agents/skills/example-skill/SKILL.md)`n[procedure](.agents/skills/example-skill/references/procedure.md) [skills](.agents/skills/)"
    [void](Problem $r 'AGENTS.md:2: links .agents/skills/example-skill/references/procedure.md;'); [void](Problem $r 'AGENTS.md:2: links .agents/skills/;')
}
Case 'G10 an index entry for a missing skill is a missing reference' {
    $r = New-Product; Put $r 'AGENTS.md' "[example-skill](.agents/skills/example-skill/SKILL.md) [ghost](.agents/skills/ghost/SKILL.md)"
    [void](Problem $r 'AGENTS.md:1: missing local reference: .agents/skills/ghost/SKILL.md (G6)')
}
Case 'G10 an index entry inside a code span does not count' { $r = New-Product; Put $r 'AGENTS.md' "${t}[example-skill](.agents/skills/example-skill/SKILL.md)${t}"; [void](Problem $r 'does not index the skill example-skill') }
Case 'G10 a reference-style index entry counts' { $r = New-Product; Put $r 'AGENTS.md' "[example-skill][skill]`n`n[skill]: .agents/skills/example-skill/SKILL.md"; Valid $r }
Case 'G10 a missing root AGENTS.md is refused' { $r = New-Product; Remove $r 'AGENTS.md'; [void](Problem $r 'AGENTS.md: missing; the root AGENTS.md is the canonical agent guidance') }
Case 'G10 a missing CLAUDE.md is refused' { $r = New-Product; Remove $r 'CLAUDE.md'; [void](Problem $r 'CLAUDE.md: missing; it is a thin pointer to the root AGENTS.md (G10)') }
Case 'G10 a missing Copilot pointer is refused' { $r = New-Product; Remove $r '.github'; [void](Problem $r '.github/copilot-instructions.md: missing; it is a thin pointer') }
Case 'G10 a pointer has at most six non-empty lines' {
    $r = New-Product; Put $r 'CLAUDE.md' ("Read [AGENTS.md](AGENTS.md).`n`n" + ((1..6 | ForEach-Object { "Line $_." }) -join "`n"))
    [void](Problem $r 'CLAUDE.md: has 7 non-empty lines; keep it a pointer of at most six')
    Put $r 'CLAUDE.md' ("Read [AGENTS.md](AGENTS.md).`n`n  `n" + ((1..5 | ForEach-Object { "Line $_.`n" }) -join "`n")); Valid $r
}
Case 'G10 a pointer that only names AGENTS.md in code is refused' { $r = New-Product; Put $r 'CLAUDE.md' "Read ${t}AGENTS.md${t}."; [void](Problem $r 'CLAUDE.md: does not link the root AGENTS.md; link it as [AGENTS.md](AGENTS.md) (G10)') }
Case 'G10 a plain-text Copilot pointer is refused' { $r = New-Product; Put $r '.github/copilot-instructions.md' 'Read AGENTS.md at the repository root.'; [void](Problem $r '.github/copilot-instructions.md: does not link the root AGENTS.md; link it as [../AGENTS.md](../AGENTS.md)') }
Case 'G10 a pointer link with other text or a fragment links AGENTS.md' {
    $r = New-Product; Put $r '.github/copilot-instructions.md' 'Read [AGENTS.md](../AGENTS.md).'; Put $r 'CLAUDE.md' 'Read [the rules](AGENTS.md#rules).'; Valid $r
}
Case 'G10 a Copilot pointer to its own folder does not link the root AGENTS.md' {
    $r = New-Product; Put $r '.github/copilot-instructions.md' 'Read [AGENTS.md](AGENTS.md).'
    [void](Problem $r '.github/copilot-instructions.md:1: missing local reference: AGENTS.md'); [void](Problem $r '.github/copilot-instructions.md: does not link the root AGENTS.md')
}

#endregion
#region G11: PowerShell examples (RedPrism suite)

function Example([string]$Root, [string]$Line, [string]$Language = 'powershell') { Skill $Root ($f3 + "$Language`n$Line`n" + $f3) }
Case 'G11 a literal signature is checked without running the script' {
    $r = New-Product; Put $r 'probe.ps1' ("[CmdletBinding()]param([string]`$Configuration,[switch]`$Check)" + $probeBody)
    Example $r './probe.ps1 -Configuration Release -Check -Verbose'
    $result = Get-CiAgentGuidanceResult -Root $r
    Require (-not $result.Problems.Count -and $result.Examples -eq 1) "Example check failed: $($result.Examples), $($result.Problems -join ' | ')"
    Require (-not [IO.File]::Exists((Join-Path $r 'executed.txt'))) 'A referenced script ran.'
}
Case 'G11 declared aliases and the ShouldProcess parameters' {
    $r = New-Product; Put $r 'probe.ps1' ("[CmdletBinding(SupportsShouldProcess=`$true)]param([Alias('cfg','c')][string]`$Configuration)" + $probeBody)
    Example $r './probe.ps1 -cfg Release -WhatIf -Confirm:$false'; Valid $r
}
Case 'G11 qualified attributes, implicit ShouldProcess and a common-parameter alias' {
    $r = New-Product; Put $r 'probe.ps1' ("[System.Management.Automation.CmdletBindingAttribute(SupportsShouldProcess)]param([System.Management.Automation.AliasAttribute('cfg')][string]`$Configuration)" + $probeBody)
    Example $r './probe.ps1 -cfg Release -WhatIf -Confirm:$false -ea Stop'; Valid $r
}
Case 'G11 WhatIf is refused when ShouldProcess is disabled' {
    $r = New-Product; Put $r 'probe.ps1' ("[CmdletBinding(SupportsShouldProcess=`$false)]param([Alias('cfg')][string]`$Configuration)" + $probeBody)
    Example $r './probe.ps1 -cfg Release -WhatIf'; [void](Problem $r 'PowerShell example passes -WhatIf, which ./probe.ps1 does not accept (G11)')
}
Case 'G11 an undeclared alias is refused' {
    $r = New-Product; Put $r 'probe.ps1' ("[CmdletBinding()]param([Alias('cfg')][string]`$Configuration)" + $probeBody)
    Example $r './probe.ps1 -undeclared Release'; [void](Problem $r 'SKILL.md:6: PowerShell example passes -undeclared, which ./probe.ps1 does not accept')
}
Case 'G11 an unknown parameter is refused' {
    $r = New-Product; Put $r 'probe.ps1' ("[CmdletBinding()]param([string]`$Configuration,[switch]`$Check)" + $probeBody)
    Example $r './probe.ps1 -Unknown Release'; [void](Problem $r 'passes -Unknown, which ./probe.ps1 does not accept')
}
Case 'G11 a script without CmdletBinding accepts no common parameter' {
    $r = New-Product; Put $r 'probe.ps1' ("param([string]`$Configuration)" + $probeBody)
    Example $r './probe.ps1 -Configuration Release -Verbose'; [void](Problem $r 'passes -Verbose, which ./probe.ps1 does not accept')
}
Case 'G11 a Parameter attribute makes a script advanced' {
    $r = New-Product; Put $r 'probe.ps1' ("param([Parameter(Mandatory)][string]`$Configuration)" + $probeBody)
    Example $r './probe.ps1 -Configuration Release -Verbose'; Valid $r
}
Case 'G11 a parameterless script is not run' { $r = New-Product; Put $r 'probe.ps1' $probeBody; Example $r './probe.ps1'; Valid $r; Require (-not [IO.File]::Exists((Join-Path $r 'executed.txt'))) 'A referenced script ran.' }
Case 'G11 a missing script is refused' { $r = New-Product; Example $r './missing.ps1 -Check'; [void](Problem $r 'SKILL.md:6: PowerShell example runs ./missing.ps1, which is not a script of this repository (G11)') }
Case 'G11 a script outside the repository is refused' {
    $folder = New-CaseFolder; $r = New-Product (Join-Path $folder 'product'); Put $folder 'outside.ps1' 'param()'
    Example $r './../outside.ps1'; [void](Problem $r 'runs ./../outside.ps1, which is not a script of this repository')
}
Case 'G11 a backslash path names the script from the root' {
    $r = New-Product; Put $r 'Tools/probe.ps1' ("[CmdletBinding()]param([switch]`$Check)" + $probeBody)
    Example $r '.\Tools\probe.ps1 -Check'; Valid $r
}
Case 'G11 a script that does not parse is refused' { $r = New-Product; Put $r 'probe.ps1' 'param([string]$Configuration'; Example $r './probe.ps1 -Configuration Release'; [void](Problem $r 'runs ./probe.ps1, which does not parse') }
Case 'G11 an example line that does not parse is refused' {
    $r = New-Product; Put $r 'probe.ps1' ("[CmdletBinding()]param([string]`$Configuration)" + $probeBody)
    Example $r './probe.ps1 -Configuration <name>'; [void](Problem $r 'PowerShell example does not parse')
}
Case 'G11 an example in another fence language is an illustration' { $r = New-Product; Example $r './missing.ps1 -Check' 'text'; Valid $r }
Case 'G11 examples outside skill packages are not checked' { $r = New-Product; Put $r 'AGENTS.md' ("[example-skill](.agents/skills/example-skill/SKILL.md)`n" + $f3 + "powershell`n./missing.ps1 -Check`n" + $f3); Valid $r }
Case 'G11 a linked script is refused before it is parsed' {
    $r = New-Product; PutBytes $r 'fixtures/not-a-script.dat' ([byte[]]@(0xFF))
    New-FileLink (Join-Path $r 'probe.ps1') (Join-Path $r 'fixtures/not-a-script.dat')
    Example $r './probe.ps1'; [void](Problem $r 'probe.ps1: is a reparse point')
}

#endregion
#region G12: plan indexes

Case 'G12 an unindexed plan is refused' { $r = New-Product; Put $r 'Specs/Plans/WIP/Second_2026-11-19.md' '# Second'; [void](Problem $r 'Specs/Plans/WIP/Second_2026-11-19.md: is not linked from Specs/Plans/WIP/README.md, which names each plan exactly once (G12)') }
Case 'G12 a plan indexed twice is refused' { $r = New-Product; Put $r 'Specs/Plans/WIP/README.md' "- [Example](Example_2026-11-19.md)`n- [Again](Example_2026-11-19.md)"; [void](Problem $r 'Specs/Plans/WIP/README.md: links Example_2026-11-19.md 2 times; name each plan exactly once') }
Case 'G12 a link into a plan section is not a second entry' { $r = New-Product; Put $r 'Specs/Plans/WIP/README.md' "See [the limits](Example_2026-11-19.md#limits).`n`n- [Example](Example_2026-11-19.md)"; Valid $r }
Case 'G12 a section link alone does not index a plan' { $r = New-Product; Put $r 'Specs/Plans/WIP/README.md' 'See [the limits](Example_2026-11-19.md#limits).'; [void](Problem $r 'Example_2026-11-19.md: is not linked') }
Case 'G12 a link to a plan that does not exist is refused' { $r = New-Product; Put $r 'Specs/Plans/WIP/README.md' "- [Example](Example_2026-11-19.md)`n- [Gone](Gone_2026-01-01.md#x)"; [void](Problem $r 'Specs/Plans/WIP/README.md:2: links Gone_2026-01-01.md, which is not a plan in Specs/Plans/WIP (G12)') }
Case 'G12 a ./ link and an angle link name the plan' { $r = New-Product; Put $r 'Specs/Plans/WIP/Second.md' '# Second'; Put $r 'Specs/Plans/WIP/README.md' "- [Example](./Example_2026-11-19.md)`n- [Second](<Second.md>)"; Valid $r }
Case 'G12 a link to another folder is not a plan entry' { $r = New-Product; Put $r 'Specs/Plans/Done/Old.md' '# Old'; Put $r 'Specs/Plans/WIP/README.md' "- [Example](Example_2026-11-19.md)`n- [Old](../Done/Old.md)"; Valid $r }
Case 'G12 an index entry inside code does not count' { $r = New-Product; Put $r 'Specs/Plans/WIP/README.md' "${t}[Example](Example_2026-11-19.md)${t}"; [void](Problem $r 'Example_2026-11-19.md: is not linked') }
Case 'G12 a missing WIP index is refused' { $r = New-Product; Remove $r 'Specs/Plans/WIP/README.md'; [void](Problem $r 'Specs/Plans/WIP/README.md: missing; it indexes the plans of Specs/Plans/WIP (G12)') }
Case 'G12 the Done index is checked when present' {
    $r = New-Product; Put $r 'Specs/Plans/Done/Old.md' '# Old'; Valid $r
    Put $r 'Specs/Plans/Done/README.md' '# Done'; [void](Problem $r 'Specs/Plans/Done/Old.md: is not linked from Specs/Plans/Done/README.md')
    Put $r 'Specs/Plans/Done/README.md' '- [Old](Old.md)'; Valid $r
}
Case 'G12 a repository without plan folders passes' { $r = New-Product; Remove $r 'Specs/Plans'; Valid $r }

#endregion
#region G13: documentation project

function New-DocumentationProduct {
    # RedHome beside a sibling: a shared skill's repository facts link the sibling's files.
    $folder = New-CaseFolder
    $root = New-Product (Join-Path $folder 'RedHome')
    Put $folder 'Sibling/Specs/Contract.md' '# Sibling contract'
    Put $root '.agents/skills/example-skill/references/repository-facts.md' "Read [the sibling contract](../../../../../Sibling/Specs/Contract.md)."
    return $root
}
Case 'G13 a sibling reference escapes a product' { $r = New-DocumentationProduct; [void](Problem $r 'repository-facts.md:1: reference escapes this repository: ../../../../../Sibling/Specs/Contract.md (G6)') }
Case 'G13 a documentation project may link a sibling repository' { $r = New-DocumentationProduct; Valid $r 'Documentation'; Valid $r 'Documentation' -CheckSiblings }
Case 'G13 without CheckSiblings a missing sibling is not checked' { $r = New-DocumentationProduct; Remove (Split-Path $r -Parent) 'Sibling'; Valid $r 'Documentation' }
Case 'G13 with CheckSiblings a missing sibling reference is refused' {
    $r = New-DocumentationProduct; Remove (Split-Path $r -Parent) 'Sibling'
    [void](Problem $r 'repository-facts.md:1: missing sibling reference: ../../../../../Sibling/Specs/Contract.md (expected' 'Documentation' -CheckSiblings)
}
Case 'G13 a reference beyond the folder of the siblings is refused' {
    $r = New-DocumentationProduct; Put $r '.agents/skills/example-skill/references/repository-facts.md' '[Far](../../../../../../far.md)'
    [void](Problem $r 'reference escapes the folder of the sibling repositories: ../../../../../../far.md (G13)' 'Documentation')
}
Case 'G13 with CheckSiblings a sibling reference must match the letter case on disk' {
    if (-not $caseInsensitive) { Skip 'this file system is case-sensitive, where a wrong-case link is already missing' }
    $r = New-DocumentationProduct; Put $r '.agents/skills/example-skill/references/repository-facts.md' '[Contract](../../../../../sibling/Specs/Contract.md)'
    [void](Problem $r 'sibling reference differs in case from the file on disk: ../sibling/Specs/Contract.md (on disk: ../Sibling/Specs/Contract.md) (G13)' 'Documentation' -CheckSiblings)
}
Case 'G13 a documentation project may show product commands it lacks, and its own are still checked' {
    $r = New-DocumentationProduct; Example $r './build.ps1 -Configuration Release'; Valid $r 'Documentation'
    Put $r 'validate.ps1' ("[CmdletBinding()]param([switch]`$CheckSiblings)" + $probeBody); Example $r './validate.ps1 -Unknown'
    [void](Problem $r 'passes -Unknown, which ./validate.ps1 does not accept (G11)' 'Documentation')
}
Case 'G13 every other rule still applies to a documentation project' { $r = New-DocumentationProduct; Remove $r '.agents/guidance.json'; Remove $r 'CLAUDE.md'; [void](Problem $r '.agents/guidance.json: missing' 'Documentation'); [void](Problem $r 'CLAUDE.md: missing' 'Documentation') }

#endregion
#region Collection, the command and the product shim

Case 'every rule reports in one run, each problem once' {
    $r = New-Product
    Put $r $skillPath ("---`nname: wrong-name`ndescription: Read it.`n---`n[Missing](missing.md)`n" + $f3 + "`nopen")
    Put $r '.agents/skills/example-skill/agents/openai.yaml' 'interface: {}'
    Put $r '.github/skills/other/SKILL.md' 'Misplaced'
    Put $r 'Tests/AGENTS.md' '# Scoped'
    Put $r 'CLAUDE.md' 'No link.'
    Put $r 'Specs/Plans/WIP/Second.md' '# Second'
    Put $r $skillPath ("---`nname: wrong-name`ndescription: Read it.`n---`n[Missing](missing.md)`n" + $f3 + "powershell`n./missing.ps1`n" + $f3 + "`n~~~`nopen")
    $problems = Get-Problems $r
    foreach ($rule in @('G1', 'G3', 'G4', 'G5', 'G6', 'G8', 'G9', 'G10', 'G11', 'G12')) {
        Require (@($problems | Where-Object { $_.EndsWith("($rule)", [StringComparison]::Ordinal) }).Count) "No $rule problem in: $($problems -join ' | ')"
    }
    Require (@($problems | Select-Object -Unique).Count -eq $problems.Count) 'A problem was reported twice.'
}
Case 'the problems are one string array, empty when valid' {
    $r = New-Product
    $none = Get-CiAgentGuidanceProblems -Root $r
    Require ($none -is [string[]] -and $none.Count -eq 0) "A valid repository returned $($none.GetType().Name) with $(@($none).Count) items."
    Remove $r 'CLAUDE.md'
    $one = Get-CiAgentGuidanceProblems -Root $r
    Require ($one -is [string[]] -and $one.Count -eq 1) "One problem was returned as $($one.GetType().Name) with $(@($one).Count) items."
}
Case 'a missing root is a caller error, not a content problem' {
    $message = ''
    try { [void](Get-CiAgentGuidanceProblems -Root (Join-Path $runRoot 'absent-root')) } catch { $message = $_.Exception.Message }
    Require ($message.Contains('Agent guidance root is not a folder')) "A missing root was not refused: $message"
}
Case 'a relative root means the PowerShell location, not the process directory' {
    $folder = New-CaseFolder; $r = New-Product (Join-Path $folder 'parent/product')
    $process = [Environment]::CurrentDirectory
    Push-Location (Join-Path $folder 'parent')
    try {
        [Environment]::CurrentDirectory = $engineRoot
        Valid 'product'
        & $command -Root 'product' 6>$null
        [Environment]::CurrentDirectory = $r
        [void](Problem '.' '.agents/skills: missing')
    } finally { [Environment]::CurrentDirectory = $process; Pop-Location }
}
Case 'the command prints one summary line for valid guidance' {
    $r = New-Product
    $records = @(& $command -Root $r 6>&1)
    Require ($records.Count -eq 1 -and "$($records[0])" -ceq 'Agent guidance valid: 1 skills, 4 references.') "The command printed: $($records -join ' | ')"
    $records = @(& $command -Root (New-DocumentationProduct) -Kind Documentation -CheckSiblings 6>&1)
    Require ("$($records[-1])".StartsWith('Agent guidance valid: 1 skills,', [StringComparison]::Ordinal)) "The documentation command printed: $($records -join ' | ')"
}
Case 'the command throws every problem, one per line' {
    $r = New-Product; Remove $r 'CLAUDE.md'; Remove $r '.agents/guidance.json'
    $message = ''
    try { & $command -Root $r 6>$null } catch { $message = $_.Exception.Message }
    $lines = $message -split "`n"
    Require ($lines[0] -ceq 'Agent guidance validation failed:' -and $lines.Count -eq 3 -and $lines[1].EndsWith('(G9)') -and $lines[2].StartsWith('CLAUDE.md: missing')) "The command failed with: $message"
}
Case 'the command and the validator write nothing and run no referenced script' {
    $r = New-DocumentationProduct
    Put $r 'probe.ps1' ("[CmdletBinding()]param([string]`$Configuration)" + $probeBody)
    Example $r './probe.ps1 -Configuration Release'
    $folder = Split-Path $r -Parent
    # A passing run, then failing runs: the product kind refuses the sibling reference, and an unindexed plan fails both.
    $before = Get-Snapshot $folder
    & $command -Root $r -Kind Documentation -CheckSiblings 6>$null
    $failures = 0
    try { & $command -Root $r 6>$null } catch { $failures++ }
    Require ($failures -eq 1) 'The product kind accepted a sibling reference.'
    Assert-Unchanged $folder $before 'A validation run'
    Put $r 'Specs/Plans/WIP/Second.md' '# Second'
    $before = Get-Snapshot $folder
    try { & $command -Root $r -Kind Documentation -CheckSiblings 6>$null } catch { $failures++ }
    [void](Get-CiAgentGuidanceResult -Root $r -Kind Documentation -CheckSiblings)
    Require ($failures -eq 2) 'An unindexed plan was accepted.'
    Assert-Unchanged $folder $before 'A failing validation run'
    Require (-not [IO.File]::Exists((Join-Path $r 'executed.txt'))) 'A referenced script ran.'
}

function Invoke-FixtureGit([string]$Root, [string[]]$Arguments) {
    $output = @(& git -C $Root @Arguments 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE) { throw "git $($Arguments -join ' ') failed in ${Root}: $($output -join ' ')" }
    return , $output
}
function New-Repository([string]$Root) {
    [void][IO.Directory]::CreateDirectory($Root)
    [void](Invoke-FixtureGit $Root @('init', '-q', '-b', 'main'))
    foreach ($setting in @(@('user.name', 'Guidance fixture'), @('user.email', 'guidance@fixture.invalid'), @('commit.gpgsign', 'false'),
            @('core.autocrlf', 'false'), @('core.longpaths', 'true'), @('core.hooksPath', (Join-Path $Root '.no-hooks')))) {
        [void](Invoke-FixtureGit $Root (@('config') + $setting))
    }
}
function New-ShimProduct {
    # A product with this engine's Test-AgentGuidance shim and a .ci-engine checkout of this engine's files at its pin.
    $root = New-Product (Join-Path (New-CaseFolder) 'product')
    New-Repository $root
    $engine = Join-Path $root '.ci-engine'
    New-Repository $engine
    foreach ($relative in @('Schemas/project.schema.json', 'Tools/Modules/Ci.Policy.psm1', 'Tools/Modules/Ci.EngineBinding.psm1',
            'Tools/Modules/Ci.AgentGuidance.psm1', 'Tools/Test-AgentGuidance.ps1')) {
        Put $engine $relative ([IO.File]::ReadAllText((Join-Path $engineRoot $relative)))
    }
    [void](Invoke-FixtureGit $engine @('add', '--all'))
    [void](Invoke-FixtureGit $engine @('commit', '-q', '-m', 'Fixture engine'))
    $pin = (Invoke-FixtureGit $engine @('rev-parse', 'HEAD'))[0].Trim()
    $manifest = [ordered]@{ schemaVersion = 1; policyVersion = '1'; repository = 'RedSalamanders/RedMonitor';
        engine = [ordered]@{ repository = 'RedSalamanders/.github'; ref = $pin }; kind = 'application';
        adapter = 'Tools/Invoke-ProjectCi.ps1'; include = @('Tests/fixtures/**'); exclude = @('CHANGELOG.md', 'Changes/**');
        formatRoots = @('src'); versionBase = '0.1';
        winget = [ordered]@{ identifier = 'RedSalamanders.RedMonitor'; executable = 'RedMonitor.exe'; alias = 'redmonitor' } }
    Put $root '.ci/project.json' ($manifest | ConvertTo-Json -Depth 8)
    Put $root '.gitignore' ".ci-engine/`n"
    Put $root 'Tools/Test-AgentGuidance.ps1' ([IO.File]::ReadAllText((Join-Path $engineRoot 'Templates/Project/Tools/Test-AgentGuidance.ps1')))
    [void](Invoke-FixtureGit $root @('add', '--all'))
    [void](Invoke-FixtureGit $root @('commit', '-q', '-m', 'Fixture product'))
    return [pscustomobject]@{ Root = $root; Engine = $engine; Pin = $pin }
}
function Invoke-Shim([string]$Path, [string[]]$Arguments = @()) {
    # The shim runs in its own PowerShell process, as products run it, so its engine import never replaces this suite's.
    $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $Path) + $Arguments) { $start.ArgumentList.Add($argument) }
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.Environment['NO_COLOR'] = '1'
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { $process.Kill($true); throw "The shim timed out: $Path" }
        $process.WaitForExit()
        # A host may still color the error view (ANSI), and it wraps long lines with a '|' gutter: the color codes go
        # first, then one space per break keeps messages searchable.
        $plain = [regex]::Replace($stdout.Result + $stderr.Result, "`e\[[0-9;?]*[ -/]*[@-~]", '')
        $output = [regex]::Replace($plain, '[ \t]*\r?\n[ \t]*(?:\|[ \t]*)?', ' ')
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
    } finally { $process.Dispose() }
}
Case 'the product shim validates its own repository by default' {
    $product = New-ShimProduct
    $shim = Join-Path $product.Root 'Tools/Test-AgentGuidance.ps1'
    $run = Invoke-Shim $shim
    Require ($run.ExitCode -eq 0 -and $run.Output.Contains('Agent guidance valid: 1 skills, 4 references.')) "The shim failed on valid guidance: $($run.Output)"
    Remove $product.Root 'CLAUDE.md'
    $run = Invoke-Shim $shim
    Require ($run.ExitCode -ne 0 -and $run.Output.Contains('Agent guidance validation failed:') -and $run.Output.Contains('CLAUDE.md: missing')) "The shim accepted invalid guidance: $($run.Output)"
}
Case 'the product shim passes Kind and CheckSiblings to the engine' {
    $product = New-ShimProduct
    Put (Split-Path $product.Root -Parent) 'Sibling/Contract.md' '# Sibling'
    Put $product.Root '.agents/skills/example-skill/references/repository-facts.md' '[Sibling](../../../../../Sibling/Contract.md)'
    $shim = Join-Path $product.Root 'Tools/Test-AgentGuidance.ps1'
    $run = Invoke-Shim $shim
    Require ($run.ExitCode -ne 0 -and $run.Output.Contains('reference escapes this repository')) "A product accepted a sibling reference: $($run.Output)"
    $run = Invoke-Shim $shim @('-Kind', 'Documentation', '-CheckSiblings')
    Require ($run.ExitCode -eq 0 -and $run.Output.Contains('Agent guidance valid:')) "The documentation kind did not reach the engine: $($run.Output)"
    Remove (Split-Path $product.Root -Parent) 'Sibling'
    $run = Invoke-Shim $shim @('-Kind', 'Documentation', '-CheckSiblings')
    Require ($run.ExitCode -ne 0 -and $run.Output.Contains('missing sibling reference')) "CheckSiblings did not reach the engine: $($run.Output)"
}
Case 'the product shim refuses a missing or other-commit engine' {
    $product = New-ShimProduct
    $shim = Join-Path $product.Root 'Tools/Test-AgentGuidance.ps1'
    Put $product.Engine 'README.md' 'A later engine commit.'
    [void](Invoke-FixtureGit $product.Engine @('add', '--all'))
    [void](Invoke-FixtureGit $product.Engine @('commit', '-q', '-m', 'Later'))
    $run = Invoke-Shim $shim
    Require ($run.ExitCode -ne 0 -and $run.Output.Contains('runs the shared CI engine') -and $run.Output.Contains("checkout --detach $($product.Pin)")) "Another engine commit was accepted: $($run.Output)"
    [void](Invoke-FixtureGit $product.Engine @('checkout', '-q', '--detach', $product.Pin))
    Move-Item -LiteralPath $product.Engine -Destination (Join-Path $product.Root 'engine-away')
    $run = Invoke-Shim $shim
    Require ($run.ExitCode -ne 0 -and $run.Output.Contains('is missing or predates engine shims')) "A missing engine was accepted: $($run.Output)"
}

#endregion

$failed = @($rows | Where-Object { -not $_.passed }).Count
$skipped = @($rows | Where-Object { $_.Contains('skipped') }).Count
[IO.File]::WriteAllText((Join-Path $runRoot 'results.json'), ([ordered]@{ schemaVersion = 1; passed = $failed -eq 0; executed = $rows.Count; failed = $failed; skipped = $skipped; cases = $rows.ToArray() } | ConvertTo-Json -Depth 6), $utf8)
Write-Host "Agent guidance: $($rows.Count - $failed - $skipped) passed, $skipped skipped, $failed failed. Results: $runRoot"
if ($failed) { throw "$failed guidance case(s) failed; preserve $runRoot." }
