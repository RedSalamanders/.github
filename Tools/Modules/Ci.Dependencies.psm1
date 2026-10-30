Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1') -Scope Local

function Get-CiDependencyReport {
    <#
    .SYNOPSIS
        Inventory declared native/source/engine pins without restoring or compiling.
    .DESCRIPTION
        Reads immutable default-branch trees and selected JSON blobs from the six
        reviewed repositories. Compares source locks with upstream main only as an
        advisory; no commit or successful workflow is treated as qualification.
    #>
    [CmdletBinding()]
    param([scriptblock]$ReadApi={param($Route) Invoke-CiApi -Route $Route -Method GET})
    $names=@('RedSalamander','DxUi','RedXe','RedPrism','RedTilde','RedMonitor')
    $cache=@{}
    function Read-Metadata([string]$Route) {
        if(-not $cache.ContainsKey($Route)){
            $response=& $ReadApi $Route
            if($null -eq $response){throw "Missing metadata: $Route"}
            $cache[$Route]=$response|ConvertTo-Json -Depth 50|ConvertFrom-Json -AsHashtable
        }
        return $cache[$Route]
    }
    function Read-Head([string]$Repository) {
        $value=Read-Metadata "repos/$Repository/git/ref/heads/main"
        if($value.object.sha -cnotmatch '^[a-f0-9]{40}$'){throw "Malformed main identity: $Repository"}
        return [string]$value.object.sha
    }
    function Read-JsonBlob([string]$Repository,[System.Collections.IDictionary]$Entry) {
        if($Entry.type -cne 'blob' -or $Entry.sha -cnotmatch '^[a-f0-9]{40}$' -or $Entry.size -gt 262144){
            throw "Unreviewed or oversized dependency metadata: $($Entry.path)"
        }
        $blob=Read-Metadata "repos/$Repository/git/blobs/$($Entry.sha)"
        if($blob.encoding -cne 'base64' -or $blob.sha -cne $Entry.sha){throw "Dependency blob identity mismatch: $($Entry.path)"}
        $bytes=[Convert]::FromBase64String($blob.content)
        if($bytes.Length -gt 262144){throw 'Dependency metadata exceeds the size bound.'}
        return [Text.UTF8Encoding]::new($false,$true).GetString($bytes)|ConvertFrom-Json -AsHashtable
    }
    $projects=[Collections.Generic.List[object]]::new()
    $errors=[Collections.Generic.List[object]]::new()
    $latestEngine=$null
    try {
        $tags=@(Read-Metadata 'repos/RedSalamanders/.github/git/matching-refs/tags/v')
        $versions=@(foreach($tag in $tags){
            $versionMatch=[regex]::Match($tag.ref,'^refs/tags/v([0-9]+\.[0-9]+\.[0-9]+)$')
            if(-not $versionMatch.Success){continue}
            $object=$tag.object
            for($depth=0;$object.type -ceq 'tag' -and $depth -lt 4;$depth++){
                if($object.sha -cnotmatch '^[a-f0-9]{40}$'){throw 'Malformed engine tag identity.'}
                $annotated=Read-Metadata "repos/RedSalamanders/.github/git/tags/$($object.sha)"
                $object=$annotated.object
            }
            if($object.type -cne 'commit' -or $object.sha -cnotmatch '^[a-f0-9]{40}$'){throw 'Engine version tag does not resolve to a commit.'}
            @{version=[version]$versionMatch.Groups[1].Value;commit=[string]$object.sha}
        })
        if(-not $versions.Count){throw 'No immutable supported engine version tags are available.'}
        $latestEngine=$versions|Sort-Object version -Descending|Select-Object -First 1
    } catch {$errors.Add(@{repository='RedSalamanders/.github';message=$_.Exception.Message})}
    foreach($name in $names){
        $repository='RedSalamanders/'+$name
        $project=[ordered]@{repository=$repository;status='unavailable';source='';engine=$null;vcpkg=$null;sourceLocks=@();limitations=@(
            'Inventory/advisories do not establish vulnerability coverage for every native/transitive/vendored dependency.',
            'Upstream-main differences can be prose only; source updates require the producer and consumer qualification contracts.')}
        try {
            $head=Read-Head $repository
            $tree=Read-Metadata "repos/$repository/git/trees/$($head)?recursive=1"
            if($tree.truncated){throw 'A truncated tree cannot establish complete dependency inventory.'}
            $entries=@{}
            foreach($entry in $tree.tree){$entries[[string]$entry.path]=$entry}
            $project.source=$head
            if(-not $entries.ContainsKey('.ci/project.json')){throw 'Shared CI adapter manifest is not deployed on this default branch.'}
            $manifest=Read-JsonBlob $repository $entries['.ci/project.json']
            if($manifest.repository -cne $repository -or $manifest.engine.repository -cne 'RedSalamanders/.github' -or
                $manifest.engine.ref -cnotmatch '^[a-f0-9]{40}$'){throw 'Invalid declared shared-engine identity.'}
            $project.engine=@{commit=$manifest.engine.ref;latestTag=$null;updateAvailable=$null;
                updateProcedure='Use Tools/Update-ProjectPin.ps1; review manifest and all callers together.'}
            if($latestEngine){
                $project.engine.latestTag='v'+$latestEngine.version.ToString()
                $project.engine.updateAvailable=$manifest.engine.ref -cne $latestEngine.commit
            }
            if($entries.ContainsKey('vcpkg.json')){
                $ports=Read-JsonBlob $repository $entries['vcpkg.json']
                if($ports['builtin-baseline'] -cnotmatch '^[a-f0-9]{40}$'){throw 'Invalid vcpkg baseline identity.'}
                $tool=$null
                if($entries.ContainsKey('vcpkg-tool.json')){
                    $tool=Read-JsonBlob $repository $entries['vcpkg-tool.json']
                    if($tool.commit -cnotmatch '^[a-f0-9]{40}$' -or $tool.repository -cne 'https://github.com/microsoft/vcpkg'){throw 'Invalid declared vcpkg tool identity.'}
                }
                $project.vcpkg=@{baseline=$ports['builtin-baseline'];toolCommit=$(if($tool){$tool.commit}else{$null});
                    dependencies=@($ports.dependencies);overrides=@(if($ports.Contains('overrides')){$ports.overrides});
                    advisoryUrl='https://github.com/microsoft/vcpkg/security/advisories';
                    updateProcedure='Review baseline, executable, port floors and audited overrides together; never adopt a baseline-only proposal.'}
            } else {$project.limitations+= 'No root vcpkg manifest; source dependencies retain their own restore/port inventories.'}
            $locks=[Collections.Generic.List[object]]::new()
            foreach($path in @($entries.Keys|Where-Object{$_ -cmatch '^Dependencies/[^/]+\.lock\.json$'}|Sort-Object)){
                $pin=Read-JsonBlob $repository $entries[$path]
                if($pin.commit -cnotmatch '^[a-f0-9]{40}$' -or $pin.repository -cnotmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'){
                    throw "Malformed source lock identity: $path"
                }
                $lock=[ordered]@{path=$path;repository=$pin.repository;commit=$pin.commit;upstreamMain=$null;mainDiffers=$null;
                    qualification='not-evaluated';usage='declared-lock; active caller scope is owned by the project';
                    advisoryUrl=($pin.repository+'/security/advisories')}
                $own=$pin.repository -creplace '^https://github\.com/',''
                if($own -cmatch '^RedSalamanders/(DxUi|RedMonitor)$'){
                    try {$lock.upstreamMain=Read-Head $own;$lock.mainDiffers=$pin.commit -cne $lock.upstreamMain}
                    catch {$project.limitations+= "Upstream metadata unavailable for $own; qualification remains not evaluated."}
                } else {$project.limitations+='External source lock is inventoried; upstream/security review is manual through its advisory URL.'}
                $locks.Add($lock)
            }
            $project.sourceLocks=$locks.ToArray()
            $project.status='observed'
        } catch {$errors.Add(@{repository=$repository;message=$_.Exception.Message})}
        $projects.Add($project)
    }
    return [ordered]@{schemaVersion=1;observedAt=[DateTimeOffset]::UtcNow.ToString('O');kind='metadata-inventory-and-advisory';
        coverageComplete=($errors.Count -eq 0);nativeBuilds=0;sourceWrites=0;qualification='not-evaluated';
        projects=$projects.ToArray();errors=$errors.ToArray()}
}

Export-ModuleMember -Function Get-CiDependencyReport
