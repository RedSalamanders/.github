# Input freshness barrier after a shared native lane opens; never a native verdict.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Candidate.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.CandidateExecution.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.CandidateReadiness.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1')

function Assert-CiCandidateNativeStart {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][Collections.IDictionary]$Descriptor)
    $null=Assert-CiCandidateExecutionBatch -Descriptor $Descriptor
    $binding=$Descriptor.candidateExecution
    $frozen=$binding.candidate
    if(-not $frozen.nativeRequired -or (Resolve-CiCommit $Root HEAD) -cne $frozen.mergeCommit -or
        (Invoke-CiGit $Root @('status','--porcelain','--untracked-files=all')).stdout.Trim()){
        throw 'Queued native execution requires the exact clean frozen synthetic merge.'
    }
    # Reuse canonical Git/API acquisition, including its race and engine checks.
    # Repeat around readiness/ref reads: a queue grant is not evidence of freshness.
    for($pass=0;$pass -lt 2;$pass++){
        $current=Get-CiIntegrationCandidate -Root $Root -PullRequest $frozen.pullRequest
        if(($current|ConvertTo-Json -Depth 20 -Compress) -cne ($frozen|ConvertTo-Json -Depth 20 -Compress)){
            throw 'Candidate changed while waiting for native capacity; reacquire a new request.'
        }
        $reference=Invoke-CiApi ('repos/'+$frozen.repository+'/git/ref/'+$binding.context.ref.Substring(5)) -Method GET
        if($reference.ref -cne $binding.context.ref -or $reference.object.type -cne 'commit' -or
            $reference.object.sha -cne $frozen.baseCommit){throw 'Queued isolated controller ref moved.'}
        $catalog=Invoke-CiApi ('repos/'+$frozen.repository+'/commits/'+$frozen.headCommit+'/check-runs?per_page=100') -Method GET
        $null=Test-CiCandidateReadinessCatalog -Candidate $frozen -Catalog $catalog
    }
    return [ordered]@{role='CandidateNativeStartInputs';identity=$frozen.identity;nativeExecutions=0;suppliesNativeVerdict=$false}
}

Export-ModuleMember -Function Assert-CiCandidateNativeStart
