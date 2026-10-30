<#
.SYNOPSIS
Atomically admits an exact main candidate in the serialized native workflow lane.
.PARAMETER Root
Candidate checkout.
.PARAMETER Commit
Expected immutable source commit.
.PARAMETER EngineRef
Expected pinned engine commit.
.PARAMETER RunId
Native workflow run identifier.
.PARAMETER Mode
Automatic quiet-window batch or explicit manual qualification.
.PARAMETER Retry
Explicitly retry already admitted inputs.
.PARAMETER CoordinatorRun
Exact main push coordinator run; automatic admission verifies its server timestamp.
.OUTPUTS
Writes .build/ci/batch.json and GitHub job outputs after admission.
.NOTES
Requires PowerShell 7.4, Git, GH_TOKEN, serialized workflow concurrency and repository
contents/status write plus Actions read. Updates only ci-state and qualification status; never compiles.
.EXAMPLE
./Tools/Invoke-Admission.ps1 -Root . -Commit $env:GITHUB_SHA -EngineRef $env:CI_ENGINE_REF -RunId $env:GITHUB_RUN_ID -Mode manual
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$EngineRef, [Parameter(Mandatory)][string]$RunId,
    [ValidateSet('automatic','manual')][string]$Mode = 'automatic', [switch]$Retry, [string]$CoordinatorRun = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Policy.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.GitHub.psm1') -ErrorAction Stop
if ($env:GITHUB_RUN_ATTEMPT -and $env:GITHUB_RUN_ATTEMPT -ne '1') { throw 'Dispatch an explicit fresh qualification retry; rerunning an old admission cannot reuse its artifacts.' }
$result = Invoke-CiAdmission -Root $Root -Commit $Commit -EngineRef $EngineRef -RunId $RunId -Mode $Mode -Retry:$Retry -CoordinatorRun $CoordinatorRun
if ($result.admitted) {
    $path = Assert-CiContainedPath $Root (Join-Path $Root '.build/ci/batch.json')
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, ($result.descriptor | ConvertTo-Json -Depth 15), [Text.UTF8Encoding]::new($false))
    if ($env:GITHUB_OUTPUT) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value @('admitted=true', ('commit=' + $Commit), ('build_number=' + $result.descriptor.buildNumber), ('version=' + $result.descriptor.version))
    }
} else {
    if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value 'admitted=false' }
    if ($result.decision.action -ceq 'retain' -and $result.decision.outcome -cne 'succeeded') {
        throw "Native work was not repeated; retained real qualification outcome: $($result.decision.outcome)."
    }
}
