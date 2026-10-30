Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.Artifacts.psm1')

function Get-CiPublicationPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$EngineRef,
        [Parameter(Mandatory)][string]$Directory)
    if($RunId -cnotmatch '^[1-9][0-9]*$' -or $EngineRef -cnotmatch '^[a-f0-9]{40}$'){throw 'Invalid qualification run or engine identity.'}
    $project=Read-CiProject $Root
    if($project.engine.ref -cne $EngineRef){throw 'Publication engine and trusted main pin differ.'}
    $run=Invoke-CiApi "repos/$($project.repository)/actions/runs/$RunId"
    if($run.status -cne 'completed' -or $run.conclusion -cne 'success' -or $run.path -cne '.github/workflows/qualify.yml' -or
        $run.event -cne 'workflow_dispatch' -or $run.head_branch -cne 'main' -or [int]$run.run_attempt -ne 1){throw 'Select an original successful main Release qualification run, not an old CI or rerun.'}
    $Directory=Assert-CiContainedPath $Root $Directory
    if(Test-Path -LiteralPath $Directory){throw 'Publication requires a fresh artifact directory; never combine different downloads.'}
    [void][IO.Directory]::CreateDirectory($Directory)
    $null=Invoke-CiProcess gh @('run','download',$RunId,'--repo',$project.repository,'--dir',$Directory,
        '--pattern','admission','--pattern','regression-*','--pattern','production-*') $Root -TimeoutSeconds 600
    $descriptors=@(Get-ChildItem -LiteralPath $Directory -Recurse -Filter 'batch.json' -File)
    if($descriptors.Count -ne 1){throw 'Qualification admission artifact is missing, expired or ambiguous.'}
    $batch=Get-Content -LiteralPath $descriptors[0].FullName -Raw|ConvertFrom-Json -AsHashtable
    if($batch.repository -cne $project.repository -or $batch.runId -cne $RunId -or $batch.commit -cne $run.head_sha -or $batch.engine.ref -cne $EngineRef){throw 'Qualification run, source or engine provenance differs.'}
    $null=Test-CiQualification -Directory $Directory -Descriptor $batch -Phase Complete
    $state=(Read-CiState $project.repository).state
    $current=New-CiInputDescriptor $Root
    if(-not $state -or $state.outcome -cne 'succeeded' -or $state.runId -cne $RunId -or
        $state.nativeDigest -cne $batch.nativeDigest -or $current.nativeDigest -cne $batch.nativeDigest){throw 'Later inputs or a failed attempt supersede this qualification. Publication never rebuilds.'}
    $assets=[Collections.Generic.List[object]]::new()
    foreach($platform in @('x64','ARM64')){
        $file=@(Get-ChildItem -LiteralPath $Directory -Recurse -Filter "production-$platform.json" -File)[0]
        $receipt=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json -AsHashtable
        foreach($archive in $receipt.archives){$assets.Add([ordered]@{platform=$platform;file=$archive.file;
            path=(Join-Path $file.DirectoryName $archive.file);relativePath=[IO.Path]::GetRelativePath($Directory,(Join-Path $file.DirectoryName $archive.file)).Replace('\','/');
            sha256=$archive.sha256;size=$archive.size})}
    }
    $names=@($assets|ForEach-Object file)
    if(@($names|Sort-Object -Unique).Count -ne $names.Count){throw 'Release asset names collide between architectures.'}
    $plan=[ordered]@{schemaVersion=1;project=$project;batch=$batch;assets=$assets.ToArray();tag=('v'+$batch.version);directory=$Directory}
    Assert-CiPublicationCurrent -Root $Root -Plan $plan
    return $plan
}

function Assert-CiReleaseAsset {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Asset,[Parameter(Mandatory)]$Expected,[Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Tag,[Parameter(Mandatory)][string]$Directory,[switch]$Anonymous)
    if($Asset.name -cne $Expected.file -or [long]$Asset.size -ne [long]$Expected.size){throw 'Published ZIP metadata differs from qualified bytes.'}
    $checkRoot=Join-Path $Directory ('asset-check-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($checkRoot)
    $target=Join-Path $checkRoot $Expected.file
    if($Anonymous){
        $url="https://github.com/$Repository/releases/download/$Tag/$($Expected.file)"
        if($Asset.browser_download_url -cne $url){throw 'Unexpected public ZIP URL.'}
        Invoke-WebRequest -Uri $url -OutFile $target -TimeoutSec 300
    }else{
        $null=Invoke-CiProcess gh @('release','download',$Tag,'--repo',$Repository,'--pattern',$Expected.file,'--dir',$checkRoot) $Directory -TimeoutSeconds 300
    }
    if((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -cne $Expected.sha256){throw 'Published ZIP bytes differ from qualification.'}
}

function Publish-CiGitHubRelease {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Plan,[switch]$RequireExisting,[switch]$Anonymous,[string]$EligibilityRoot='')
    if($EligibilityRoot){Assert-CiPublicationCurrent -Root $EligibilityRoot -Plan $Plan}
    $repo=$Plan.project.repository;$tag=$Plan.tag
    $release=Invoke-CiApi "repos/$repo/releases/tags/$tag" -AllowNotFound
    $marker="Source: $($Plan.batch.commit)`nEngine: $($Plan.batch.engine.ref)`nNative inputs: $($Plan.batch.nativeDigest)"
    if(-not $release){
        if($RequireExisting){throw 'Publish the qualified GitHub ZIP release before requesting winget.'}
        $ref=Invoke-CiApi "repos/$repo/git/ref/tags/$tag" -AllowNotFound
        if($ref -and ($ref.object.type -cne 'commit' -or $ref.object.sha -cne $Plan.batch.commit)){throw 'Existing version tag targets different source.'}
        $body=$marker+"`n`nQualified run: https://github.com/$repo/actions/runs/$($Plan.batch.runId)`n`n"+
            (($Plan.assets|ForEach-Object{"$($_.file): SHA256 $($_.sha256)"}) -join "`n")
        $release=Invoke-CiApi "repos/$repo/releases" -Method POST -Body @{tag_name=$tag;target_commitish=$Plan.batch.commit;name=$tag;body=$body;draft=$true;prerelease=$false}
    }elseif(-not ([string]$release.body).Contains($marker)){throw 'Existing release has different or absent source/engine provenance; no overwrite is allowed.'}
    $expectedNames=@($Plan.assets.file)
    if(@($release.assets|Where-Object {$_.name -cnotin $expectedNames}).Count){throw 'Existing release contains unqualified assets.'}
    foreach($expected in $Plan.assets){
        $existing=@($release.assets|Where-Object name -ceq $expected.file)
        if($existing.Count -gt 1){throw 'Duplicate published ZIP asset.'}
        if($existing.Count -eq 1){
            if($release.draft){
                if($existing[0].digest -cne ('sha256:'+$expected.sha256)){throw 'Existing draft ZIP has absent/different server digest; retain it for review.'}
            }else{Assert-CiReleaseAsset $existing[0] $expected $repo $tag $Plan.directory -Anonymous:$Anonymous}
            continue
        }
        if(-not $release.draft -or $RequireExisting){throw 'Existing public release is incomplete; no replacement or hidden rebuild is allowed.'}
        $upload="https://uploads.github.com/repos/$repo/releases/$($release.id)/assets?name=$([uri]::EscapeDataString($expected.file))"
        $asset=Invoke-RestMethod -Uri $upload -Method POST -Headers @{Authorization=('Bearer '+$env:GH_TOKEN);Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2026-03-10'} -InFile $expected.path -ContentType 'application/zip' -TimeoutSec 600
        if($asset.name -cne $expected.file -or $asset.digest -cne ('sha256:'+$expected.sha256)){throw 'Uploaded ZIP digest differs; retained draft must be reviewed.'}
    }
    if($release.draft){
        if($RequireExisting){throw 'winget requires a public, published ZIP release.'}
        if($EligibilityRoot){Assert-CiPublicationCurrent -Root $EligibilityRoot -Plan $Plan}
        $release=Invoke-CiApi "repos/$repo/releases/$($release.id)" -Method PATCH -Body @{draft=$false}
    }
    $ref=Invoke-CiApi "repos/$repo/git/ref/tags/$tag"
    if($ref.object.type -cne 'commit' -or $ref.object.sha -cne $Plan.batch.commit){throw 'Version tag does not target qualified source.'}
    foreach($expected in $Plan.assets){
        $asset=@($release.assets|Where-Object name -ceq $expected.file)
        if($asset.Count -ne 1){throw 'Release did not retain exactly one of each qualified ZIP.'}
        Assert-CiReleaseAsset $asset[0] $expected $repo $tag $Plan.directory -Anonymous:$Anonymous
    }
    return $release
}

function New-CiWingetManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Plan,[Parameter(Mandatory)][string]$Directory)
    $project=$Plan.project
    if($project.kind -cne 'application' -or -not $project.winget){throw 'DxUi SDK publication does not support winget.'}
    if(-not $project.winget.Contains('license') -or -not $project.winget.license){throw 'The product license must be configured before winget publication.'}
    [void][IO.Directory]::CreateDirectory($Directory)
    $id=$project.winget.identifier;$version=$Plan.batch.version;$name=$project.repository.Split('/')[1]
    $common="PackageIdentifier: $id`nPackageVersion: $version`n"
    $installer=$common+"InstallerType: zip`nNestedInstallerType: portable`nUpgradeBehavior: uninstallPrevious`nInstallers:`n"
    $commands=@(@{executable=$project.winget.executable;alias=$project.winget.alias})
    if($project.winget.Contains('additionalCommands')){$commands+=@($project.winget.additionalCommands)}
    $aliases=@($commands|ForEach-Object alias)
    if(@($aliases|Sort-Object -Unique).Count -ne $aliases.Count){throw 'Portable command aliases must be unique.'}
    foreach($command in $commands){
        if($command.executable -cnotmatch '^[A-Za-z0-9._-]+[.]exe$' -or $command.alias -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'){
            throw 'Unsafe portable command configuration.'
        }
    }
    foreach($platform in @('x64','ARM64')){
        $assets=@($Plan.assets|Where-Object { $_.platform -ceq $platform -and $_.file -notmatch '(?i)symbols' })
        if($assets.Count -ne 1){throw 'winget requires one portable application ZIP per architecture.'}
        $archive=[IO.Compression.ZipFile]::OpenRead($assets[0].path)
        try{
            $nestedCommands=foreach($command in $commands){
                $entries=@($archive.Entries|Where-Object {$_.Name -ceq $command.executable})
                if($entries.Count -ne 1){throw 'The ZIP has no unique configured portable executable.'}
                $nested=$entries[0].FullName.Replace('\','/')
                if($nested -match '(^/|(^|/)\.\.(/|$)|:|[\x00-\x1f])'){throw 'Unsafe nested executable path.'}
                @{path=("'"+$nested.Replace("'","''")+"'");alias=("'"+$command.alias+"'")}
            }
        }finally{$archive.Dispose()}
        $arch=$platform.ToLowerInvariant()
        $url="https://github.com/$($project.repository)/releases/download/$($Plan.tag)/$($assets[0].file)"
        $installer+="- Architecture: $arch`n  InstallerUrl: $url`n  InstallerSha256: $($assets[0].sha256.ToUpperInvariant())`n  NestedInstallerFiles:`n"
        foreach($command in $nestedCommands){
            $installer+="  - RelativeFilePath: $($command.path)`n    PortableCommandAlias: $($command.alias)`n"
        }
    }
    $installer+="ManifestType: installer`nManifestVersion: 1.12.0`n"
    $locale=$common+"PackageLocale: en-US`nPublisher: RedSalamanders`nPackageName: $name`nLicense: $($project.winget.license)`nShortDescription: $name Windows application`nPackageUrl: https://github.com/$($project.repository)`nManifestType: defaultLocale`nManifestVersion: 1.12.0`n"
    $versionFile=$common+"DefaultLocale: en-US`nManifestType: version`nManifestVersion: 1.12.0`n"
    foreach($pair in @(@("$id.yaml",$versionFile),@("$id.installer.yaml",$installer),@("$id.locale.en-US.yaml",$locale))){
        [IO.File]::WriteAllText((Join-Path $Directory $pair[0]),$pair[1],[Text.UTF8Encoding]::new($false))
    }
    return $Directory
}

function Read-CiPublicationPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)
    $plan=Get-Content -LiteralPath (Join-Path $Directory 'publication.json') -Raw|ConvertFrom-Json -AsHashtable
    $plan.directory=[IO.Path]::GetFullPath($Directory)
    $null=Test-CiQualification -Directory $Directory -Descriptor $plan.batch -Phase Complete
    foreach($asset in $plan.assets){
        $asset.path=Assert-CiContainedPath $Directory (Join-Path $Directory $asset.relativePath)
        if((Get-FileHash -LiteralPath $asset.path).Hash.ToLowerInvariant() -cne $asset.sha256){throw 'Downloaded publication plan has altered ZIP bytes.'}
    }
    return $plan
}

function Assert-CiPublicationCurrent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][System.Collections.IDictionary]$Plan)
    $head=Get-CiMainHead $Plan.project.repository
    $known=Invoke-CiGit $Root @('cat-file','-e',($head+'^{commit}')) -AllowFailure
    if($known.exitCode -ne 0){
        $null=Invoke-CiGit $Root @('-c','credential.helper=','-c','credential.helper=!gh auth git-credential','fetch','--no-tags','origin',$head)
    }
    $current=New-CiInputDescriptor $Root -Ref $head
    $state=(Read-CiState $Plan.project.repository).state
    if($current.nativeDigest -cne $Plan.batch.nativeDigest -or -not $state -or $state.runId -cne $Plan.batch.runId -or
        $state.nativeDigest -cne $Plan.batch.nativeDigest -or $state.outcome -cne 'succeeded'){throw 'Publication qualification was superseded or no longer passed.'}
}

function Test-CiProjectPublicationPreflight {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][System.Collections.IDictionary]$Plan)
    if($Plan.project.repository -cne 'RedSalamanders/RedSalamander'){return}
    # The existing observer is compiler-free. Keep it in the read-only preparation job,
    # bound to the exact qualified source and lock rather than a later prose-only head.
    $null=Invoke-CiGit $Root @('checkout','--detach',$Plan.batch.commit)
    $output=Join-Path $Root '.build/TerminalEngineStatus/publication/status.json'
    $hostPath=(Get-Process -Id $PID).Path
    $env:CI_NATIVE_BUILDS_DISABLED='true'
    $null=Invoke-CiProcess $hostPath @('-NoProfile','-NonInteractive','-File',
        (Join-Path $Root 'Tools/Get-GhosttyTerminalRuntimeStatus.ps1'),'-Mode','Online',
        '-OutputPath',$output,'-ExpectedSourceCommit',$Plan.batch.commit) $Root -TimeoutSeconds 300
    $report=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json -AsHashtable
    $lockHash=(Get-FileHash -LiteralPath (Join-Path $Root 'External/TerminalEngine/GhosttyRuntimeLock.v1.json')).Hash.ToLowerInvariant()
    if($report.sourceBinding.repositoryCommit -cne $Plan.batch.commit -or $report.canonicalLock.sha256 -cne $lockHash -or
        $report.result -cin @('security-review','required-manual','unreachable')){throw 'Source-and-lock-bound Ghostty publication preflight failed closed.'}
    $retained=Join-Path $Plan.directory 'preflight'
    [void][IO.Directory]::CreateDirectory($retained)
    Copy-Item -LiteralPath $output -Destination (Join-Path $retained 'ghostty-status.json')
    Write-Host "Source-bound Ghostty publication preflight: $($report.result)."
}

Export-ModuleMember -Function Get-CiPublicationPlan, Assert-CiReleaseAsset, Publish-CiGitHubRelease, New-CiWingetManifest, Read-CiPublicationPlan, Assert-CiPublicationCurrent, Test-CiProjectPublicationPreflight

