# Input acquisition only; this module grants no native, merge or adoption authority.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1')

function Get-CiMergeGroupMetadata {
    param([object]$Event,[string]$Repository)
    if($Repository -cnotmatch '^RedSalamanders/(RedSalamander|DxUi|RedXe|RedPrism|RedTilde|RedMonitor)$' -or
        $Event.repository.full_name -cne $Repository -or $Event.action -cne 'checks_requested' -or
        $Event.merge_group.base_ref -cne 'refs/heads/main') {throw 'Merge group requires an exact reviewed repository and main checks_requested event.'}
    $group=$Event.merge_group
    # Treat the queue suffix as an opaque ref, not a source of PR membership or authority.
    if([string]$group.head_ref -cnotmatch '^refs/heads/gh-readonly-queue/main/[A-Za-z0-9_-][A-Za-z0-9_/-]*$' -or
        [string]$group.head_ref -cmatch '//|/$') {throw 'Merge group queue ref is malformed or targets another branch.'}
    foreach($sha in @($group.base_sha,$group.head_sha)) {
        if([string]$sha -cnotmatch '^[a-f0-9]{40}$'){throw 'Merge group requires exact base and head commits.'}
    }
    return [ordered]@{baseCommit=[string]$group.base_sha;headCommit=[string]$group.head_sha;headRef=[string]$group.head_ref}
}

function Get-CiMergeGroupRefCommit {
    param([object]$Reference,[string]$ExpectedRef)
    if($Reference.ref -cne $ExpectedRef -or $Reference.object.type -cne 'commit' -or
        [string]$Reference.object.sha -cnotmatch '^[a-f0-9]{40}$'){throw 'Merge group ref API identity is missing or malformed.'}
    return [string]$Reference.object.sha
}

function New-CiMergeGroupInputs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][object]$Event,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$CurrentMainCommit,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$CurrentGroupCommit,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ControllerEngineRef)
    $group=Get-CiMergeGroupMetadata $Event $Repository
    if($group.baseCommit -cne $CurrentMainCommit -or $group.headCommit -cne $CurrentGroupCommit){throw 'Merge group event, current main and queue ref disagree.'}
    $base=Resolve-CiCommit $Root $CurrentMainCommit
    $head=Resolve-CiCommit $Root $CurrentGroupCommit
    if($head -ceq $base){throw 'Merge group has no proposed integration.'}
    $ancestry=Invoke-CiGit $Root @('merge-base','--is-ancestor',$base,$head) -AllowFailure
    if($ancestry.exitCode -ne 0){throw 'Merge group does not descend from the exact current main.'}
    $input=New-CiInputDescriptor -Root $Root -Ref $head
    $baseline=New-CiInputDescriptor -Root $Root -Ref $base
    if($input.repository -cne $Repository -or $baseline.repository -cne $Repository){throw 'Merge group source manifests belong to another repository.'}
    $descriptor=[ordered]@{schemaVersion=1;role='MergeGroupInputs';repository=$Repository;baseCommit=$base;
        groupCommit=$head;groupRef=$group.headRef;groupTree=(Invoke-CiGit $Root @('rev-parse',($head+'^{tree}'))).stdout.Trim();
        controllerEngineRef=$ControllerEngineRef;input=$input;baseNativeDigest=$baseline.nativeDigest;
        nativeRequired=($input.nativeDigest -cne $baseline.nativeDigest)}
    $descriptor.identity=Get-CiSha256 ($descriptor|ConvertTo-Json -Depth 15 -Compress)
    if(-not(Test-Json -Json ($descriptor|ConvertTo-Json -Depth 15) -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/merge-group-inputs.schema.json'))){throw 'Merge group descriptor violates its strict input-only schema.'}
    return $descriptor
}

function Assert-CiMergeGroupInputsCurrent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][Collections.IDictionary]$Descriptor,
        [Parameter(Mandatory)][object]$Event,[Parameter(Mandatory)][string]$CurrentMainCommit,[Parameter(Mandatory)][string]$CurrentGroupCommit,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ControllerEngineRef)
    $fresh=New-CiMergeGroupInputs -Root $Root -Repository $Descriptor.repository -Event $Event -CurrentMainCommit $CurrentMainCommit `
        -CurrentGroupCommit $CurrentGroupCommit -ControllerEngineRef $ControllerEngineRef
    if(($fresh|ConvertTo-Json -Depth 15 -Compress) -cne ($Descriptor|ConvertTo-Json -Depth 15 -Compress)){throw 'Merge group inputs changed or were modified.'}
}

function Get-CiMergeGroupInputs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object]$Event)
    $engine=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $controller=Resolve-CiCommit $engine HEAD
    if((Invoke-CiGit $engine @('status','--porcelain','--untracked-files=all')).stdout.Trim()){throw 'Use a clean committed merge group controller.'}
    $repo=(Read-CiProject $Root).repository
    $group=Get-CiMergeGroupMetadata $Event $repo
    $remote=(Invoke-CiGit $Root @('remote','get-url','origin')).stdout.Trim().TrimEnd('/')
    if($remote -ine "https://github.com/$repo" -and $remote -ine "https://github.com/$repo.git" -and
        $remote -ine "git@github.com:$repo.git" -and $remote -ine "ssh://git@github.com/$repo.git"){throw 'Merge group fetch requires the exact reviewed GitHub origin.'}
    $route='repos/'+$repo+'/git/ref/'+$group.headRef.Substring(5)
    $main=Get-CiMainHead $repo
    $head=Get-CiMergeGroupRefCommit (Invoke-CiApi $route -Method GET) $group.headRef
    if($main -cne $group.baseCommit -or $head -cne $group.headCommit){throw 'Merge group is stale before fetch.'}
    $prefix='refs/ci/merge-groups/'+[guid]::NewGuid().ToString('N')
    $savedPrompt=[Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT','Process')
    try {
        $env:GIT_TERMINAL_PROMPT='0'
        $null=Invoke-CiGit $Root @('fetch','--no-tags','origin',('refs/heads/main:'+$prefix+'/main'),($group.headRef+':'+$prefix+'/group'))
    } finally {[Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT',$savedPrompt,'Process')}
    if((Resolve-CiCommit $Root ($prefix+'/main')) -cne $main -or (Resolve-CiCommit $Root ($prefix+'/group')) -cne $head){throw 'Merge group refs moved during fetch; retained refs are diagnostic only.'}
    $descriptor=New-CiMergeGroupInputs -Root $Root -Repository $repo -Event $Event -CurrentMainCommit $main -CurrentGroupCommit $head -ControllerEngineRef $controller
    $afterMain=Get-CiMainHead $repo
    $afterHead=Get-CiMergeGroupRefCommit (Invoke-CiApi $route -Method GET) $group.headRef
    Assert-CiMergeGroupInputsCurrent -Root $Root -Descriptor $descriptor -Event $Event -CurrentMainCommit $afterMain -CurrentGroupCommit $afterHead -ControllerEngineRef $controller
    if((Resolve-CiCommit $engine HEAD) -cne $controller -or (Invoke-CiGit $engine @('status','--porcelain','--untracked-files=all')).stdout.Trim()){throw 'Merge group controller changed during acquisition.'}
    return $descriptor
}

Export-ModuleMember -Function New-CiMergeGroupInputs,Assert-CiMergeGroupInputsCurrent,Get-CiMergeGroupInputs
