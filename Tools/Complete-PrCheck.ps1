<#
.SYNOPSIS
Completes the exact trusted manual PR recheck using its real read-only checks result.
.PARAMETER CheckId
Check id returned by Resolve-PrCheck.
.PARAMETER Result
Reusable compiler-free PR job result.
.PARAMETER Kind
CI aggregate, CodeQL analysis or dependency review. Completes only that exact named check.
.OUTPUTS
Completed GitHub check. No source execution or writes.
.NOTES
Requires a trusted main dispatch and checks write. A missing, skipped or cancelled check never passes.
.EXAMPLE
./Tools/Complete-PrCheck.ps1 -CheckId 123 -Result success
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[0-9]+$')][string]$CheckId,
    [Parameter(Mandatory)][ValidateSet('success','failure','cancelled','skipped')][string]$Result,
    [ValidateSet('CI','CodeQL','Dependency')][string]$Kind='CI')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.GitHub.psm1')
if($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/main'){throw 'Check completion requires a trusted main dispatch.'}
$repo=$env:GITHUB_REPOSITORY
$check=Invoke-CiApi "repos/$repo/check-runs/$CheckId"
$names=@{CI='checks / ci-gate';CodeQL='security / codeql';Dependency='security / dependency-review'}
if($check.external_id -cne "format-recheck-$($env:GITHUB_RUN_ID)" -or $check.name -cne $names[$Kind]){throw 'A manual recheck cannot complete another check.'}
$conclusion=if($Result -ceq 'success'){'success'}elseif($Result -ceq 'cancelled'){'cancelled'}else{'failure'}
$null=Invoke-CiApi "repos/$repo/check-runs/$CheckId" -Method PATCH -Body @{
    status='completed';conclusion=$conclusion;completed_at=[DateTimeOffset]::UtcNow.ToString('o')
    output=@{title="$Kind compiler-free checks: $conclusion";summary='The selected compiler-free formatting/tooling, CodeQL or dependency job was executed against this exact head. Native qualification occurs after main batching.'}}
if($conclusion -cne 'success'){throw "PR recheck $conclusion."}

