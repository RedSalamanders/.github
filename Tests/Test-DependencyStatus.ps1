[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../Tools/Modules/Ci.Dependencies.psm1')
$names=@('RedSalamander','DxUi','RedXe','RedPrism','RedTilde','RedMonitor')
$current='c'*40
$old='b'*40
$script:passed=0
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Case([string]$Name,[scriptblock]$Action){& $Action; ++$script:passed; Write-Host "PASS $Name"}
function New-Fixture {
    $routes=@{}
    $trees=@{}
    $routes['repos/RedSalamanders/.github/git/matching-refs/tags/v']=@(@{ref='refs/tags/v1.0.4';object=@{type='commit';sha=$current}})
    foreach($name in $names){
        $repo='RedSalamanders/'+$name
        $head=([Convert]::ToHexString([Security.Cryptography.SHA1]::HashData([Text.Encoding]::UTF8.GetBytes($repo)))).ToLowerInvariant()
        $routes["repos/$repo/git/ref/heads/main"]=@{object=@{sha=$head}}
        $trees[$name]=@{truncated=$false;tree=[Collections.Generic.List[object]]::new()}
        $routes["repos/$repo/git/trees/$($head)?recursive=1"]=$trees[$name]
        $data=[ordered]@{
            '.ci/project.json'=@{repository=$repo;engine=@{repository='RedSalamanders/.github';ref=$current}};
            'vcpkg.json'=@{'builtin-baseline'=$old;dependencies=@(@{name='wil';'version>='='1.0.0'});overrides=@(@{name='wil';version='1.0.0'})};
            'vcpkg-tool.json'=@{repository='https://github.com/microsoft/vcpkg';commit=$old};
            'Dependencies/DxUi.lock.json'=@{repository='https://github.com/RedSalamanders/DxUi';commit=$old};
            'Dependencies/Lucide.lock.json'=@{repository='https://github.com/lucide-icons/lucide';commit=$old}
        }
        foreach($path in $data.Keys){
            $bytes=[Text.Encoding]::UTF8.GetBytes(($data[$path]|ConvertTo-Json -Depth 15 -Compress))
            $blob=([Convert]::ToHexString([Security.Cryptography.SHA1]::HashData($bytes))).ToLowerInvariant()
            $entry=@{path=$path;type='blob';sha=$blob;size=$bytes.Length}
            $trees[$name].tree.Add($entry)
            $routes["repos/$repo/git/blobs/$blob"]=@{sha=$blob;encoding='base64';content=[Convert]::ToBase64String($bytes)}
        }
    }
    return @{routes=$routes;trees=$trees;calls=[Collections.Generic.List[string]]::new()}
}
function Read-Report($Fixture) {
    $reader={
        param($Route)
        $Fixture.calls.Add($Route)
        if(-not $Fixture.routes.ContainsKey($Route)){throw "Unavailable reviewed metadata: $Route"}
        return $Fixture.routes[$Route]
    }.GetNewClosure()
    return Get-CiDependencyReport -ReadApi $reader
}

Case 'Six immutable inventories retain native port floors, overrides and both own/external source lock scope' {
    $f=New-Fixture
    $r=Read-Report $f
    Require $r.coverageComplete 'All six fixture repositories must be observed.'
    Require ($r.projects.Count -eq 6 -and @($r.projects|Where-Object status -ceq 'observed').Count -eq 6) 'Missing inventory.'
    Require ($r.projects[0].vcpkg.dependencies[0]['version>='] -eq '1.0.0') 'Port floor was dropped.'
    Require ($r.projects[0].vcpkg.overrides[0].version -eq '1.0.0') 'Exact override was dropped.'
    Require ($r.projects[0].sourceLocks.Count -eq 2) 'Source lock was dropped.'
    Require (-not $r.projects[0].engine.updateAvailable) 'An unchanged tag needs no update.'
    Require (@($f.calls|Where-Object{$_ -match '/actions/|/contents/|/git/refs/'}).Count -eq 0) 'No qualification/mutable-content/write API belongs here.'
}
Case 'A source-main difference remains unqualified and external repositories receive no credential-bearing API call' {
    $f=New-Fixture
    $r=Read-Report $f
    $pin=@($r.projects[0].sourceLocks|Where-Object path -eq 'Dependencies/DxUi.lock.json')[0]
    Require ($pin.mainDiffers -and $pin.qualification -ceq 'not-evaluated') 'Main movement is not qualification.'
    Require (@($f.calls|Where-Object{$_ -notmatch '^repos/RedSalamanders/'}).Count -eq 0) 'Credentials left the reviewed organization.'
    Require (@($r.projects[0].limitations -match 'External source lock').Count -gt 0) 'External advisory scope must be explicit.'
}
Case 'Private or unavailable repositories retain public results and fail complete-coverage status' {
    $f=New-Fixture
    $f.routes.Remove('repos/RedSalamanders/RedPrism/git/ref/heads/main')
    $f.routes.Remove('repos/RedSalamanders/RedTilde/git/ref/heads/main')
    $r=Read-Report $f
    Require (-not $r.coverageComplete -and $r.errors.Count -eq 2) 'Missing private repositories must not turn green.'
    Require (@($r.projects|Where-Object status -ceq 'observed').Count -eq 4) 'Readable projects must remain inventoried.'
}
Case 'Truncated source trees and wrong blob identities cannot claim a complete snapshot' {
    $f=New-Fixture
    $f.trees.RedXe.truncated=$true
    $entry=@($f.trees.RedSalamander.tree|Where-Object path -eq '.ci/project.json')[0]
    $f.routes['repos/RedSalamanders/RedSalamander/git/blobs/'+$entry.sha].sha='d'*40
    $r=Read-Report $f
    Require (-not $r.coverageComplete -and $r.errors.Count -eq 2) 'Partial/unbound metadata must fail coverage.'
}
Case 'Oversized metadata and malformed source URLs are refused without following data as commands or API routes' {
    $f=New-Fixture
    $entry=@($f.trees.RedXe.tree|Where-Object path -eq 'vcpkg.json')[0]
    $entry.size=262145
    $entry=@($f.trees.RedSalamander.tree|Where-Object path -eq 'Dependencies/DxUi.lock.json')[0]
    $bad=@{repository='https://user:secret@github.com/RedSalamanders/DxUi';commit=$old}|ConvertTo-Json -Compress
    $f.routes['repos/RedSalamanders/RedSalamander/git/blobs/'+$entry.sha].content=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bad))
    $r=Read-Report $f
    Require (-not $r.coverageComplete -and $r.errors.Count -eq 2) 'Unsafe lock or oversized metadata must fail.'
    Require (@($f.calls|Where-Object{$_ -match 'secret|user:'}).Count -eq 0) 'Lock data became a credential-bearing route.'
}
Case 'Annotated stable engine tags resolve to a full commit and only advise coordinated caller updates' {
    $f=New-Fixture
    $tag='e'*40
    $f.routes['repos/RedSalamanders/.github/git/matching-refs/tags/v']+=@{ref='refs/tags/v1.1.0';object=@{type='tag';sha=$tag}}
    $f.routes["repos/RedSalamanders/.github/git/tags/$tag"]=@{object=@{type='commit';sha='d'*40}}
    $r=Read-Report $f
    Require ($r.coverageComplete -and $r.projects[0].engine.latestTag -ceq 'v1.1.0' -and $r.projects[0].engine.updateAvailable) 'Latest annotated tag was not observed.'
    Require ($r.projects[0].engine.updateProcedure -match 'all callers together') 'A workflow-only pin edit must not be suggested.'
}
Case 'Missing default-branch CI deployment and missing engine tags stay visible as incomplete coverage' {
    $f=New-Fixture
    $f.trees.RedPrism.tree.RemoveAt(0)
    $f.routes['repos/RedSalamanders/.github/git/matching-refs/tags/v']=@()
    $r=Read-Report $f
    Require (-not $r.coverageComplete -and $r.errors.Count -eq 2) 'An undeployed adapter or unavailable engine tags must not look ready.'
}
Write-Host "$script:passed dependency metadata behavior controls passed; no compiler or network was invoked."
