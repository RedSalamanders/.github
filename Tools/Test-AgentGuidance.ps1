<#
.SYNOPSIS
Validates a repository's agent guidance without writing files.
.DESCRIPTION
Applies the agent-guidance contract G1 to G13 of Specs/ProjectCommands.md: the skill grammar of every
.agents/skills/<name>/SKILL.md, strict UTF-8 reading, Markdown fences and local references of the skill packages, the root
and scoped AGENTS.md files and the instruction pointers, reparse points below the root, harness files, the scoped-guidance
inventory .agents/guidance.json, the skill index and pointers, PowerShell examples in skill packages and the plan indexes
under Specs/Plans. Reports every problem at once.
.PARAMETER Root
Repository root of the checkout to validate. Products run this through their Tools/Test-AgentGuidance.ps1 shim, which
defaults Root to its own repository (Specs/ProjectCommands.md).
.PARAMETER Kind
Product (the default): every local reference stays inside the repository. Documentation (RedHome): references may name
sibling repositories in the folder that holds Root, and PowerShell examples may name product commands it lacks (G13).
.PARAMETER CheckSiblings
With Kind Documentation, also requires each sibling reference to exist, resolved against the folder that holds Root.
.OUTPUTS
One console summary line, "Agent guidance valid: <n> skills, <m> references."; no persistent files. Invalid guidance
raises a terminating error, "Agent guidance validation failed:" followed by one problem per line, and a nonzero process exit.
.NOTES
Requires PowerShell 7. Read-only; no network, build, Git or desktop access, and no referenced script or example is run.
Primary consumers: each product's validate-skills.ps1, repository validation, PrePush and the compiler-free CI phase.
.EXAMPLE
./.ci-engine/Tools/Test-AgentGuidance.ps1 -Root .
.EXAMPLE
./.ci-engine/Tools/Test-AgentGuidance.ps1 -Root ../RedHome -Kind Documentation -CheckSiblings
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string] $Root, [ValidateSet('Product', 'Documentation')][string] $Kind = 'Product', [switch] $CheckSiblings)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.AgentGuidance.psm1')
$Root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)
$result = Get-CiAgentGuidanceResult -Root $Root -Kind $Kind -CheckSiblings:$CheckSiblings
if ($result.Problems.Count) { throw "Agent guidance validation failed:`n$($result.Problems -join "`n")" }
Write-Host "Agent guidance valid: $($result.Skills) skills, $($result.References) references."
