Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.WingetPublication.psm1')

function Invoke-CiWingetApi {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Route,[ValidateSet('GET','POST','PATCH')][string]$Method='GET',
        [object]$Body,[switch]$AllowNotFound)
    if(-not $env:WINGET_TOKEN){throw 'Explicit winget submission requires WINGET_TOKEN.'}
    if($Route -cne 'user' -and $Route -cnotmatch '^repos/[A-Za-z0-9-]+/winget-pkgs(?:/[A-Za-z0-9_./?=&%+-]+)?$'){throw 'winget API route is outside its reviewed boundary.'}
    if($Route -cne 'user'){
        $owner=$Route.Split('/')[1]
        if($owner -cne 'microsoft' -and $owner -cne $script:WingetOwner){throw 'winget API route names a foreign fork.'}
    }
    $requestArguments=@{Uri=('https://api.github.com/'+$Route);Method=$Method;TimeoutSec=60;
        Headers=@{Authorization=('Bearer '+$env:WINGET_TOKEN);Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2026-03-10'}}
    if($PSBoundParameters.ContainsKey('Body')){$requestArguments.ContentType='application/json';$requestArguments.Body=$Body|ConvertTo-Json -Depth 30 -Compress}
    try{return Invoke-RestMethod @requestArguments}catch [Microsoft.PowerShell.Commands.HttpResponseException]{
        $status=[int]$_.Exception.Response.StatusCode
        if($AllowNotFound -and $status -eq 404){return $null}
        throw "winget GitHub operation refused with HTTP $status; retained manifests and remote state were not overwritten."
    }
}

function Submit-CiWinget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Plan,[Parameter(Mandatory)][string]$ManifestDirectory)
    $user=Invoke-CiWingetApi 'user'
    $script:WingetOwner=[string]$user.login
    if($script:WingetOwner -cnotmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$'){throw 'Invalid publication credential owner.'}
    $owner=$script:WingetOwner;$fork="$owner/winget-pkgs"
    $package=$Plan.project.winget.identifier;$version=$Plan.batch.version
    $identity=New-RSWingetPublicationIdentity -PackageIdentifier $package -Version $version -ManifestRoot $ManifestDirectory -PullRequestTitle "Update: $package version $version"
    $api=(Get-Command Invoke-CiWingetApi).ScriptBlock
    $contentHash=(Get-Command Get-RSWingetManifestContentHash).ScriptBlock
    $repository=@{
        ListPullRequests={
            param([int]$Page,[int]$PageSize,[string]$State,[string]$Head)
            & $api "repos/microsoft/winget-pkgs/pulls?state=$State&base=master&sort=created&direction=desc&per_page=$PageSize&page=$Page"
        }.GetNewClosure()
        ListPullRequestFiles={
            param([int]$Number,[int]$Page,[int]$PageSize)
            & $api "repos/microsoft/winget-pkgs/pulls/$Number/files?per_page=$PageSize&page=$Page"
        }.GetNewClosure()
        GetManifestContentHash={
            param([string]$RepositoryFullName,[string]$Path,[string]$Ref)
            $encoded=(($Path -split '/')|ForEach-Object{[uri]::EscapeDataString($_)}) -join '/'
            $content=& $api "repos/$RepositoryFullName/contents/$($encoded)?ref=$([uri]::EscapeDataString($Ref))"
            & $contentHash -Bytes ([Convert]::FromBase64String($content.content))
        }.GetNewClosure()
        GetUpstreamManifest={
            $master=& $api 'repos/microsoft/winget-pkgs/git/ref/heads/master'
            $ref=[string]$master.object.sha
            $entries=& $api "repos/microsoft/winget-pkgs/contents/$($identity.ManifestPrefix)?ref=$ref" -AllowNotFound
            [pscustomobject]@{Ref=$ref;Names=@($entries|Where-Object type -ceq 'file'|ForEach-Object name)}
        }.GetNewClosure()
        PatchPullRequest={
            param([int]$Number,[string]$Title,[string]$Body)
            & $api "repos/microsoft/winget-pkgs/pulls/$Number" -Method PATCH -Body @{title=$Title;body=$Body}
        }.GetNewClosure()
    }
    $submit={
        param([string]$InitialTitle)
        $metadata=& $api "repos/$fork" -AllowNotFound
        if(-not $metadata){
            $null=& $api 'repos/microsoft/winget-pkgs/forks' -Method POST -Body @{default_branch_only=$true}
            foreach($attempt in 1..12){$metadata=& $api "repos/$fork" -AllowNotFound;if($metadata){break};Start-Sleep -Seconds 5}
        }
        if(-not $metadata -or -not $metadata.fork -or $metadata.parent.full_name -cne 'microsoft/winget-pkgs'){throw 'The publication fork is not the upstream winget repository.'}
        $master=& $api 'repos/microsoft/winget-pkgs/git/ref/heads/master'
        $commit=& $api "repos/microsoft/winget-pkgs/git/commits/$($master.object.sha)"
        $treeRows=foreach($path in $identity.ManifestHashes.Keys){
            $local=Join-Path $ManifestDirectory ([IO.Path]::GetFileName($path))
            if((& $contentHash -Bytes ([IO.File]::ReadAllBytes($local))) -cne $identity.ManifestHashes[$path]){throw 'Prepared manifests changed before submission.'}
            $blob=& $api "repos/$fork/git/blobs" -Method POST -Body @{content=[IO.File]::ReadAllText($local);encoding='utf-8'}
            @{path=$path;mode='100644';type='blob';sha=$blob.sha}
        }
        $tree=& $api "repos/$fork/git/trees" -Method POST -Body @{base_tree=$commit.tree.sha;tree=@($treeRows)}
        $newCommit=& $api "repos/$fork/git/commits" -Method POST -Body @{message=$InitialTitle;tree=$tree.sha;parents=@($master.object.sha)}
        $branch="$package-$version-$([guid]::NewGuid().ToString('D'))"
        $null=& $api "repos/$fork/git/refs" -Method POST -Body @{ref="refs/heads/$branch";sha=$newCommit.sha}
        $null=& $api 'repos/microsoft/winget-pkgs/pulls' -Method POST -Body @{title=$InitialTitle;head=($owner+':'+$branch);base='master';body=$identity.BodyMarker}
        [pscustomobject]@{ExitCode=0;Output=@('Created exact-version manifest PR using the explicit publication credential.')}
    }.GetNewClosure()
    $body="Publishes $package $version from qualified ZIP bytes. Release: https://github.com/$($Plan.project.repository)/releases/tag/$($Plan.tag). Native ZIP and winget install evidence are retained with this manual publication."
    Invoke-RSWingetPublication -Identity $identity -ExpectedAuthor $owner -ExpectedHeadRepository $fork -PullRequestBody $body -Repository $repository -Submit $submit -MaximumVisibilityAttempts 6
}

Export-ModuleMember -Function Submit-CiWinget

