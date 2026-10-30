Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function Invoke-CiApi {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Route, [ValidateSet('GET','POST','PUT','PATCH','DELETE')][string]$Method = 'GET',
        [AllowNull()][object]$Body, [switch]$AllowNotFound)
    if ($Route -notmatch '^repos/RedSalamanders/(\.github|RedSalamander|DxUi|RedXe|RedPrism|RedTilde|RedMonitor)(?:/[A-Za-z0-9_./?=&%+-]+)?$') { throw 'API route is outside the reviewed organization/repositories.' }
    if (-not $env:GH_TOKEN) { throw 'GH_TOKEN is required for this GitHub operation.' }
    $arguments = @{ Uri = ('https://api.github.com/' + $Route); Method = $Method; TimeoutSec = 60;
        Headers = @{ Authorization = ('Bearer ' + $env:GH_TOKEN); Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2026-03-10' } }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $arguments.ContentType = 'application/json'
        $arguments.Body = $Body | ConvertTo-Json -Depth 30 -Compress
    }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try { return Invoke-RestMethod @arguments }
        catch [Microsoft.PowerShell.Commands.HttpResponseException] {
            $status = [int]$_.Exception.Response.StatusCode
            if ($AllowNotFound -and $status -eq 404) { return $null }
            if ($status -in @(429,502,503,504) -and $attempt -lt 2) { Start-Sleep -Seconds ($attempt + 1); continue }
            throw "GitHub $Method $Route refused with HTTP $status. Original state is retained."
        }
    }
}

function Get-CiMainHead {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository)
    $ref = Invoke-CiApi "repos/$Repository/git/ref/heads/main"
    if ($ref.object.sha -notmatch '^[a-f0-9]{40}$') { throw 'Invalid current main identity.' }
    return [string]$ref.object.sha
}

function Read-CiState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository)
    $ref = Invoke-CiApi "repos/$Repository/git/ref/heads/ci-state" -AllowNotFound
    if ($null -eq $ref) { return @{ head = ''; state = $null } }
    $head = [string]$ref.object.sha
    if ($head -notmatch '^[a-f0-9]{40}$') { throw 'Invalid CI-state ref identity.' }
    $file = Invoke-CiApi "repos/$Repository/contents/state.json?ref=$head"
    if ($file.encoding -cne 'base64') { throw 'CI state is not an ordinary JSON blob.' }
    $json = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String($file.content))
    $state = $json | ConvertFrom-Json -AsHashtable
    if ($state.schemaVersion -ne 1 -or $state.repository -cne $Repository -or
        $state.nativeDigest -notmatch '^[a-f0-9]{64}$' -or $state.commit -notmatch '^[a-f0-9]{40}$' -or
        $state.runId -notmatch '^\d+$' -or $state.outcome -notin @('running','succeeded','failed','cancelled')) { throw 'Invalid persistent CI state; qualification cannot be inferred.' }
    return @{ head = $head; state = $state }
}

function Write-CiState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [AllowEmptyString()][Parameter(Mandatory)][string]$ExpectedHead)
    $current = Read-CiState $Repository
    if ($current.head -cne $ExpectedHead) { throw 'CI-state lease changed before publication; refuse a concurrent overwrite.' }
    $blob = Invoke-CiApi "repos/$Repository/git/blobs" -Method POST -Body @{ content = ($State | ConvertTo-Json -Depth 20 -Compress); encoding = 'utf-8' }
    $tree = Invoke-CiApi "repos/$Repository/git/trees" -Method POST -Body @{ tree = @(@{ path = 'state.json'; mode = '100644'; type = 'blob'; sha = $blob.sha }) }
    $parent = if ($ExpectedHead) { $ExpectedHead } else { $State.commit }
    $commit = Invoke-CiApi "repos/$Repository/git/commits" -Method POST -Body @{
        message = "CI admission $($State.runId): $($State.outcome)"; tree = $tree.sha; parents = @($parent) }
    if ($ExpectedHead) {
        # Both contenders have the captured parent. Only one sibling can fast-forward the ref.
        $null = Invoke-CiApi "repos/$Repository/git/refs/heads/ci-state" -Method PATCH -Body @{ sha = $commit.sha; force = $false }
    } else {
        # A concurrent initial creation receives 422; it must not consume the candidate.
        $null = Invoke-CiApi "repos/$Repository/git/refs" -Method POST -Body @{ ref = 'refs/heads/ci-state'; sha = $commit.sha }
    }
    return [string]$commit.sha
}

function Resolve-CiStateOutcome {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)
    $result = [ordered]@{}
    foreach ($key in $State.Keys) { $result[$key] = $State[$key] }
    if ($State.outcome -eq 'running') {
        $run = Invoke-CiApi "repos/$($State.repository)/actions/runs/$($State.runId)"
        if ($run.status -eq 'completed') {
            # Workflow success alone cannot replace the missing qualification receipt.
            $result.outcome = if ($run.conclusion -eq 'cancelled') { 'cancelled' } else { 'failed' }
            $result.recoveryReason = 'The admitted workflow ended without a recorded successful qualification.'
        }
    }
    return $result
}

function Set-CiQualificationStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Commit,
        [ValidateSet('pending','success','failure','error')][string]$Status,
        [Parameter(Mandatory)][string]$Description, [Parameter(Mandatory)][string]$RunId)
    if ($Commit -notmatch '^[a-f0-9]{40}$' -or $RunId -notmatch '^\d+$') { throw 'Invalid qualification status identity.' }
    $null = Invoke-CiApi "repos/$Repository/statuses/$Commit" -Method POST -Body @{
        state = $Status; context = 'main-qualification'; description = $Description.Substring(0, [Math]::Min(140, $Description.Length));
        target_url = "https://github.com/$Repository/actions/runs/$RunId" }
}

function Wait-CiMainQuiet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Commit)
    $observedAt = [DateTimeOffset]::UtcNow
    while ($true) {
        $head = Get-CiMainHead $Repository
        if ($head -cne $Commit) { return $false }
        $decision = Get-CiQuietDecision $Commit $observedAt $head ([DateTimeOffset]::UtcNow)
        if ($decision.quiet) { return $true }
        Write-Host "Waiting for five quiet minutes: $($decision.remainingSeconds) seconds remain."
        Start-Sleep -Seconds ([Math]::Min(15, $decision.remainingSeconds))
    }
}

function Invoke-CiCoordinator {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RunId)
    $candidate = New-CiInputDescriptor $Root
    if ($env:GITHUB_REPOSITORY -cne $candidate.repository -or $env:GITHUB_REF -cne 'refs/heads/main') { throw 'Main coordination is restricted to this repository default branch.' }
    $record = Read-CiState $candidate.repository
    $state = if ($record.state) { Resolve-CiStateOutcome $record.state } else { $null }
    if ($state -and $state.nativeDigest -ceq $candidate.nativeDigest) {
        $status = switch ($state.outcome) { 'succeeded' { 'success' }; 'running' { 'pending' }; default { 'failure' } }
        Set-CiQualificationStatus $candidate.repository $candidate.commit $status "Native inputs unchanged; original outcome: $($state.outcome)." ([string]$state.runId)
        Write-Host "Retained native qualification from run $($state.runId): $($state.outcome). No native work dispatched."
        return
    }
    Set-CiQualificationStatus $candidate.repository $candidate.commit pending 'Meaningful inputs pending the five-minute quiet window.' $RunId
    if (-not (Wait-CiMainQuiet $candidate.repository $candidate.commit)) {
        Write-Host 'Coordinator superseded; pending meaningful inputs remain unconsumed.'
        return
    }
    $null = Invoke-CiApi "repos/$($candidate.repository)/actions/workflows/qualify.yml/dispatches" -Method POST -Body @{
        ref = 'main'; inputs = @{ commit = $candidate.commit; mode = 'automatic'; retry = 'false'; profile = 'Release'; coordinator_run = $RunId } }
    Write-Host "Submitted native admission for $($candidate.commit); admission will recheck current main."
}

function Invoke-CiAdmission {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$EngineRef, [Parameter(Mandatory)][string]$RunId,
        [ValidateSet('automatic','manual')][string]$Mode = 'automatic', [switch]$Retry,
        [string]$CoordinatorRun = '')
    $candidate = New-CiInputDescriptor $Root
    if ($candidate.commit -cne $Commit -or $candidate.engine.ref -cne $EngineRef -or $env:GITHUB_REPOSITORY -cne $candidate.repository) { throw 'Admission source, repository or engine identity mismatch.' }
    $run = Invoke-CiApi "repos/$($candidate.repository)/actions/runs/$RunId"
    if ($run.path -cne '.github/workflows/qualify.yml' -or $run.event -cne 'workflow_dispatch' -or
        $run.head_branch -cne 'main' -or $run.head_sha -cne $Commit) { throw 'Admission requires the exact source of its trusted main workflow.' }
    $head = Get-CiMainHead $candidate.repository
    $record = Read-CiState $candidate.repository
    $state = if ($record.state) { Resolve-CiStateOutcome $record.state } else { $null }
    $decision = Get-CiAdmissionDecision $candidate $state $head $true -Retry:$Retry
    if ($decision.action -ne 'admit') {
        if ($decision.action -eq 'retain') {
            $status = switch ($decision.outcome) { 'succeeded' { 'success' }; 'running' { 'pending' }; default { 'failure' } }
            Set-CiQualificationStatus $candidate.repository $candidate.commit $status "Inputs already admitted; retained $($decision.outcome)." ([string]$state.runId)
        }
        Write-Host "No native admission: $($decision.action), $($decision.reason)."
        return @{ admitted = $false; decision = $decision }
    }
    if ($Mode -eq 'automatic') {
        # The coordinator already waited five minutes. Verify its server timestamp rather
        # than imposing a second five-minute delay or trusting an input timestamp.
        if ($CoordinatorRun -notmatch '^\d+$') { throw 'Automatic admission requires its exact push coordinator run.' }
        $coordinator = Invoke-CiApi "repos/$($candidate.repository)/actions/runs/$CoordinatorRun"
        if ($coordinator.event -cne 'push' -or $coordinator.head_branch -cne 'main' -or $coordinator.head_sha -cne $Commit -or
            $coordinator.path -cne '.github/workflows/ci.yml' -or
            ([DateTimeOffset]::UtcNow - [DateTimeOffset]$coordinator.created_at).TotalSeconds -lt 300) {
            throw 'The server-side coordinator identity or five-minute window is invalid.'
        }
        if ((Get-CiMainHead $candidate.repository) -cne $Commit) { throw 'Main moved at the admission boundary.' }
    }
    if ($state -and $record.state.outcome -cne $state.outcome) {
        $record.head = Write-CiState $candidate.repository $state $record.head
    }
    $candidate.runId = $RunId
    $candidate.outcome = 'running'
    $candidate.admittedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $candidate.mode = $Mode
    $stateHead = Write-CiState $candidate.repository $candidate $record.head
    Set-CiQualificationStatus $candidate.repository $candidate.commit pending 'Admitted: both native test branches must pass before production.' $RunId
    return @{ admitted = $true; descriptor = $candidate; stateHead = $stateHead }
}

function Complete-CiBatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Descriptor,
        [Parameter(Mandatory)][string]$Root,
        [ValidateSet('succeeded','failed','cancelled')][string]$Outcome)
    $record = Read-CiState $Descriptor.repository
    if (-not $record.state -or $record.state.runId -cne $Descriptor.runId -or $record.state.nativeDigest -cne $Descriptor.nativeDigest) { throw 'Batch completion cannot overwrite another admitted run.' }
    $state = $record.state
    $state.outcome = $Outcome
    $state.finishedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $null = Write-CiState $Descriptor.repository $state $record.head
    $status = if ($Outcome -eq 'succeeded') { 'success' } else { 'failure' }
    Set-CiQualificationStatus $Descriptor.repository $Descriptor.commit $status "Native qualification $Outcome; run $($Descriptor.runId)." ([string]$Descriptor.runId)
    # Complete a prose-only head's pending status only after matching its native inputs.
    $head = Get-CiMainHead $Descriptor.repository
    if ($head -cne $Descriptor.commit) {
        $null = Invoke-CiGit $Root @('fetch','--no-tags','origin',$head)
        $current = New-CiInputDescriptor $Root -Ref $head
        if ($current.nativeDigest -ceq $Descriptor.nativeDigest) {
            Set-CiQualificationStatus $Descriptor.repository $head $status "Unchanged native inputs; qualification $Outcome." ([string]$Descriptor.runId)
        }
    }
}

Export-ModuleMember -Function Invoke-CiApi, Get-CiMainHead, Read-CiState, Write-CiState, Resolve-CiStateOutcome, Set-CiQualificationStatus, Wait-CiMainQuiet, Invoke-CiCoordinator, Invoke-CiAdmission, Complete-CiBatch
