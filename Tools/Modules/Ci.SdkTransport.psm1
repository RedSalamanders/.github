# Authenticated immutable dependency transport; never a product test or publication verdict.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkProducer.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SdkCache.psm1')

function Test-CiHostedSdkEnvelope {
    param([object]$Run,[object]$Jobs,[object]$Artifacts,[object]$Workflow,
        [string]$SourceCommit,[string]$Platform,[string]$RunId,[int]$Attempt)
    $policyJson=Get-Content (Join-Path $PSScriptRoot '../../Policy/sdk-transport.json') -Raw
    if(-not(Test-Json -Json $policyJson -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/sdk-transport-policy.schema.json'))){throw 'Invalid reviewed SDK transport policy.'}
    $policy=$policyJson|ConvertFrom-Json
    $producer=Read-CiSdkProducerPolicy
    if(@($producer.sources|Where-Object commit -CEQ $SourceCommit).Count -ne 1){throw 'Unreviewed SDK source pin.'}
    if([string]$Run.id -cne $RunId -or $Run.run_attempt -ne $Attempt -or $Run.status -cne 'completed' -or
        $Run.conclusion -cne 'success' -or $Run.event -cne 'workflow_dispatch' -or $Run.head_branch -cne 'main' -or
        $Run.path -cne $policy.workflowPath -or $Run.repository.full_name -cne $policy.repository -or
        [string]$Run.head_sha -cnotmatch '^[a-f0-9]{40}$'){throw 'SDK artifact requires the exact successful main producer attempt.'}
    if($Workflow.path -cne $policy.workflowPath -or $Workflow.sha -cne $policy.workflowBlob){throw 'SDK producer caller differs from its reviewed immutable workflow.'}
    $refs=@($Run.referenced_workflows)
    if($refs.Count -ne 1 -or $refs[0].sha -cne $policy.engineRef -or
        $refs[0].path -cne ('RedSalamanders/.github/.github/workflows/sdk-inputs.yml@'+$policy.engineRef)){
        throw 'SDK producer executed another reusable workflow or engine.'
    }
    if($Jobs.total_count -ne @($Jobs.jobs).Count -or $Artifacts.total_count -ne @($Artifacts.artifacts).Count){throw 'Truncated SDK producer metadata is not admissible.'}
    $runner=if($Platform -ceq 'x64'){'windows-2025-vs2026'}elseif($Platform -ceq 'ARM64'){'windows-11-vs2026-arm'}else{throw 'Invalid native SDK platform.'}
    $selected=@($Jobs.jobs|Where-Object name -CEQ "inputs / sdk ($Platform, $runner)")
    if($selected.Count -ne 1 -or $selected[0].status -cne 'completed' -or $selected[0].conclusion -cne 'success' -or
        $selected[0].run_id -ne $Run.id -or $selected[0].run_attempt -ne $Attempt -or
        $selected[0].runner_group_name -cne 'GitHub Actions' -or $runner -cnotin @($selected[0].labels)){
        throw 'SDK artifact lacks successful matching native architecture execution.'
    }
    $name="dependency-sdk-$SourceCommit-$Platform-$Attempt"
    $items=@($Artifacts.artifacts|Where-Object name -CEQ $name)
    if($items.Count -ne 1){throw 'Exactly one attempt/source/platform SDK artifact is required.'}
    $item=$items[0]
    if($item.expired -isnot [bool] -or $item.expired -or [string]$item.id -cnotmatch '^[1-9][0-9]{0,19}$' -or
        $item.digest -cnotmatch '^sha256:[a-f0-9]{64}$' -or $item.size_in_bytes -lt 1 -or $item.size_in_bytes -gt 1GB -or
        $item.workflow_run.id -ne $Run.id -or $item.workflow_run.head_sha -cne $Run.head_sha -or
        $item.workflow_run.head_branch -cne 'main' -or $item.workflow_run.repository_id -ne $Run.repository.id -or
        $item.workflow_run.head_repository_id -ne $Run.repository.id){throw 'SDK artifact envelope identity, size or digest is invalid.'}
    return [ordered]@{schemaVersion=1;role='HostedDependencySdkEnvelope';repository=$policy.repository;sourceCommit=$SourceCommit;
        platform=$Platform;runId=$RunId;attempt=$Attempt;producerCommit=$Run.head_sha;engineRef=$policy.engineRef;
        artifactId=[string]$item.id;artifactName=$name;archiveSha256=$item.digest.Substring(7);archiveBytes=[long]$item.size_in_bytes}
}

function Resolve-CiHostedSdkArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
        [Parameter(Mandatory)][ValidateRange(1,100000)][int]$Attempt,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$SourceCommit,
        [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform)
    $repo='RedSalamanders/DxUi'
    $run=Invoke-CiApi "repos/$repo/actions/runs/$RunId/attempts/$Attempt" -Method GET
    $jobs=Invoke-CiApi "repos/$repo/actions/runs/$RunId/attempts/$Attempt/jobs?per_page=100" -Method GET
    $artifacts=Invoke-CiApi "repos/$repo/actions/runs/$RunId/artifacts?per_page=100" -Method GET
    if([string]$run.head_sha -cnotmatch '^[a-f0-9]{40}$'){throw 'Invalid producer commit.'}
    $workflow=Invoke-CiApi "repos/$repo/contents/.github/workflows/sdk-inputs.yml?ref=$($run.head_sha)" -Method GET
    Test-CiHostedSdkEnvelope $run $jobs $artifacts $workflow $SourceCommit $Platform $RunId $Attempt
}

function Assert-CiSdkArchiveBytes {
    param([Collections.IDictionary]$Envelope,[string]$Archive)
    if((Get-Item -LiteralPath $Archive).Length -ne $Envelope.archiveBytes -or
        (Get-FileHash -LiteralPath $Archive).Hash.ToLowerInvariant() -cne $Envelope.archiveSha256){throw 'SDK archive differs from the authenticated server size/digest.'}
}

function Receive-CiSdkArchive {
    param([Collections.IDictionary]$Envelope,[string]$Destination)
    if(-not $env:GH_TOKEN){throw 'Repository-read authentication is required for SDK transport.'}
    $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false
    $api=[Net.Http.HttpClient]::new($handler);$download=[Net.Http.HttpClient]::new()
    $response=$null;$stream=$null;$target=$null;$deadline=[Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(10))
    try{
        $api.DefaultRequestHeaders.UserAgent.ParseAdd('RedSalamanders-SdkTransport/1')
        $api.DefaultRequestHeaders.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$env:GH_TOKEN)
        $api.DefaultRequestHeaders.Add('X-GitHub-Api-Version','2026-03-10')
        $url="https://api.github.com/repos/RedSalamanders/DxUi/actions/artifacts/$($Envelope.artifactId)/zip"
        $response=$api.GetAsync($url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if([int]$response.StatusCode -ne 302){throw 'GitHub refused the SDK artifact download.'}
        $location=$response.Headers.Location
        if($null -eq $location -or -not $location.IsAbsoluteUri -or $location.Scheme -cne 'https' -or $location.UserInfo){throw 'GitHub returned an invalid SDK artifact redirect.'}
        $response.Dispose();$response=$null
        # The separate client has no API authentication headers; the signed redirect never receives GH_TOKEN.
        $download.Timeout=[TimeSpan]::FromMinutes(10)
        $response=$download.GetAsync($location,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if(-not $response.IsSuccessStatusCode){throw 'SDK artifact storage refused the download.'}
        $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $target=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=[byte[]]::new(1MB);$total=0L
        while(($count=$stream.ReadAsync($buffer,0,$buffer.Length,$deadline.Token).GetAwaiter().GetResult()) -gt 0){
            $total+=$count
            if($total -gt $Envelope.archiveBytes){throw 'SDK artifact exceeds the authenticated byte count.'}
            $target.Write($buffer,0,$count)
        }
        if($total -ne $Envelope.archiveBytes){throw 'SDK artifact download is incomplete.'}
        $target.Dispose();$target=$null
        Assert-CiSdkArchiveBytes $Envelope $Destination
    }finally{
        if($null -ne $target){$target.Dispose()};if($null -ne $stream){$stream.Dispose()};if($null -ne $response){$response.Dispose()}
        $api.Dispose();$download.Dispose();$deadline.Dispose()
    }
}

function Expand-CiSdkArchive {
    param([string]$Archive,[string]$Destination,[Collections.IDictionary]$Envelope)
    $cache=Get-Module Ci.SdkCache
    $archiveStream=[IO.File]::Open($Archive,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $zip=$null;$manifests=[Collections.Generic.List[object]]::new()
    try{
        if($null -ne $Envelope){
            $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($archiveStream)).ToLowerInvariant()
            if($archiveStream.Length -ne $Envelope.archiveBytes -or $hash -cne $Envelope.archiveSha256){throw 'SDK archive changed before extraction.'}
            $archiveStream.Position=0
        }
        $zip=[IO.Compression.ZipArchive]::new($archiveStream,[IO.Compression.ZipArchiveMode]::Read,$true)
        if($zip.Entries.Count -lt 1 -or $zip.Entries.Count -gt 50000){throw 'SDK archive has an invalid entry count.'}
        $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $total=0L
        # Validate the complete catalog before extracting the first file.
        foreach($entry in $zip.Entries){
            $name=$entry.FullName.TrimEnd('/')
            & $cache {param($p) Test-CiSdkRelativePath $p} $name
            if(-not $names.Add($name)){throw 'Duplicate or case-colliding SDK archive path.'}
            $mode=($entry.ExternalAttributes -shr 16) -band 0xF000
            if($mode -eq 0xA000 -or ($entry.ExternalAttributes -band 0x400)){throw 'SDK archive links and reparse entries are refused.'}
            $total+=$entry.Length
            if($total -gt 2GB){throw 'SDK archive expands beyond its bound.'}
        }
        foreach($entry in $zip.Entries){
            $path=Assert-CiContainedPath $Destination (Join-Path $Destination $entry.FullName)
            if($entry.FullName.EndsWith('/')){[void][IO.Directory]::CreateDirectory($path);continue}
            if(($entry.FullName -split '/')[-1] -ceq 'entry.json'){
                # Hold the server-digest-verified archive open. The independent manifest digest comes
                # from these authenticated bytes, never a mutable extracted filesystem manifest.
                $content=$entry.Open()
                try{$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($content)).ToLowerInvariant()}finally{$content.Dispose()}
                $manifests.Add([ordered]@{path=$entry.FullName;sha256=$sha})
            }
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$path,$false)
        }
        return $manifests.ToArray()
    }finally{if($null -ne $zip){$zip.Dispose()};$archiveStream.Dispose()}
}

function Test-CiSdkTransportRecipe {
    param([Collections.IDictionary]$Expected,[Collections.IDictionary]$Actual)
    $expectedKey=Get-CiSdkCacheKey $Expected;$actualKey=Get-CiSdkCacheKey $Actual
    foreach($name in @('sourceRepository','sourceCommit','sourceBytes','apiRevision','platform','configuration','runtimeFamily','annotationPolicy','languageStandard','optimizationPolicy','integrationPolicyIdentity')){
        if([string]$Expected[$name] -cne [string]$Actual[$name]){throw "Hosted SDK has an unexpected source/profile/policy field: $name."}
    }
    return $expectedKey -ceq $actualKey
}

function Import-CiHostedSdkArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$DownloadRoot,[Parameter(Mandatory)][Collections.IDictionary]$Identity,
        [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$RunId,
        [Parameter(Mandatory)][ValidateRange(1,100000)][int]$Attempt)
    # Identity comes from the independently bootstrapped/evaluated producer recipe, never the downloaded entry.
    $key=Get-CiSdkCacheKey $Identity
    $envelope=Resolve-CiHostedSdkArtifact -RunId $RunId -Attempt $Attempt -SourceCommit $Identity.sourceCommit -Platform $Identity.platform
    $owned=Assert-CiContainedPath (Join-Path $RepositoryRoot '.build') $DownloadRoot
    $directory=Assert-CiContainedPath $owned (Join-Path $owned ([guid]::NewGuid().ToString('N')))
    [void][IO.Directory]::CreateDirectory($directory)
    $envelopePath=Join-Path $directory 'authenticated-envelope.json'
    [IO.File]::WriteAllText($envelopePath,($envelope|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $archive=Join-Path $directory 'artifact.zip';Receive-CiSdkArchive $envelope $archive
    $expanded=Join-Path $directory 'expanded';[void][IO.Directory]::CreateDirectory($expanded)
    $catalog=@(Expand-CiSdkArchive $archive $expanded $envelope)
    $entries=@(Get-ChildItem -LiteralPath $expanded -Filter entry.json -Recurse -File)
    if($entries.Count -ne 1){throw 'SDK artifact must contain exactly one immutable input version.'}
    $entry=$entries[0]
    $relative=[IO.Path]::GetRelativePath($expanded,$entry.FullName).Replace('\','/')
    if($catalog.Count -ne 1 -or $catalog[0].path -cne $relative){throw 'Extracted SDK manifest differs from the authenticated archive catalog.'}
    $manifestSha=$catalog[0].sha256
    if((Get-FileHash -LiteralPath $entry.FullName).Hash.ToLowerInvariant() -cne $manifestSha){throw 'Extracted SDK manifest changed after authenticated acquisition.'}
    $json=Get-Content -LiteralPath $entry.FullName -Raw
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/sdk-cache-entry.schema.json'))){throw 'Invalid hosted SDK entry manifest.'}
    $remote=$json|ConvertFrom-Json -AsHashtable
    $remoteKey=Get-CiSdkCacheKey $remote.identity
    if($remote.key -cne $remoteKey){throw 'Hosted SDK manifest has an inconsistent input identity.'}
    $marker=Join-Path (Split-Path -Parent $entry.DirectoryName) 'input-key.txt'
    if(-not(Test-Path -LiteralPath $marker -PathType Leaf) -or [IO.File]::ReadAllText($marker) -cne $remoteKey){throw 'Downloaded SDK input key marker is invalid.'}
    if((Split-Path -Leaf $entry.DirectoryName) -cne $manifestSha.Substring(0,16) -or
        (Split-Path -Leaf (Split-Path -Parent $entry.DirectoryName)) -cne $remoteKey.Substring(0,16)){throw 'Downloaded SDK locator does not bind its complete key/manifest.'}
    # Re-read producer metadata after transfer; expiry, deletion or a changed attempt cannot gain acceptance.
    $after=Resolve-CiHostedSdkArtifact -RunId $RunId -Attempt $Attempt -SourceCommit $Identity.sourceCommit -Platform $Identity.platform
    if(($after|ConvertTo-Json -Compress) -cne ($envelope|ConvertTo-Json -Compress)){throw 'SDK artifact provenance changed during transport.'}
    if(-not(Test-CiSdkTransportRecipe -Expected $Identity -Actual $remote.identity)){
        Write-Host "Verified SDK uses another compiler/dependency/environment recipe ($remoteKey); exact requested key $key is unavailable."
        return $null
    }
    Initialize-CiSdkStore -RepositoryRoot $RepositoryRoot -StoreRoot $StoreRoot
    $result=Import-CiSdkCacheEntry -StoreRoot $StoreRoot -Identity $Identity -EntryRoot $entry.DirectoryName -ManifestSha256 $manifestSha
    [IO.File]::WriteAllText((Join-Path $directory 'import.json'),([ordered]@{role='DependencyBytesImported';key=$result.Key;manifestSha256=$result.ManifestSha256;envelope=$envelope}|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    return $result
}

Export-ModuleMember -Function Resolve-CiHostedSdkArtifact,Import-CiHostedSdkArtifact
