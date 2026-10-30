<#
.SYNOPSIS
Starts a fresh PR check on an exact head after a manual formatting commit.
.PARAMETER PullRequest
Open same-repository PR number.
.PARAMETER ExpectedHead
Exact new head SHA.
.OUTPUTS
Verified base/head and new GitHub check id through GITHUB_OUTPUT.
.NOTES
Trusted default-branch dispatch only; executes no PR source. Requires checks write and contents read.
.EXAMPLE
./Tools/Resolve-PrCheck.ps1 -PullRequest 123 -ExpectedHead 0123456789012345678901234567890123456789
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequest,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedHead)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.GitHub.psm1')
if($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/main'){throw 'Fresh privileged reporting requires a trusted main dispatch.'}
$repo=$env:GITHUB_REPOSITORY
$pr=Invoke-CiApi "repos/$repo/pulls/$PullRequest"
if($pr.state -cne 'open' -or $pr.head.repo.full_name -cne $repo -or $pr.head.sha -cne $ExpectedHead -or $pr.base.ref -cne 'main'){throw 'The expected same-repository PR identity changed.'}
$created=[Collections.Generic.List[object]]::new()
try{
    foreach($entry in @(
        @{name='checks / ci-gate';output='check_id'},
        @{name='security / codeql';output='codeql_id'},
        @{name='security / dependency-review';output='dependency_id'}
    )){
        $check=Invoke-CiApi "repos/$repo/check-runs" -Method POST -Body @{
            name=$entry.name;head_sha=$ExpectedHead;status='in_progress'
            details_url="https://github.com/$repo/actions/runs/$($env:GITHUB_RUN_ID)"
            external_id="format-recheck-$($env:GITHUB_RUN_ID)"}
        $created.Add(@{id=$check.id;output=$entry.output})
    }
}catch{
    foreach($check in $created){
        $null=Invoke-CiApi "repos/$repo/check-runs/$($check.id)" -Method PATCH -Body @{status='completed';conclusion='failure'}
    }
    throw
}
if($env:GITHUB_OUTPUT){
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value @("head=$ExpectedHead",("base="+$pr.base.sha))
    foreach($check in $created){Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value ($check.output+'='+$check.id)}
}

