# Raw working-tree input identity only; no test, SDK or hosted acceptance.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')

function Get-CiCheckoutContentIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    # Bootstrap exception: verify producer code before importing it. Deliberately match the canonical SDK
    # full raw-source map (ordinal paths + SHA-256); this trust-boundary adapter cannot call unverified SDK code.
    $paths=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    $listed=(Invoke-CiGit $Root @('-c','core.fsmonitor=false','ls-files','--cached','--others','--exclude-standard','-z')).stdout
    foreach($path in $listed.Split([char]0,[StringSplitOptions]::RemoveEmptyEntries)){if($path -cnotmatch '^\.build/'){[void]$paths.Add($path)}}
    if(-not $paths.Count){throw 'SDK checkout has no raw source inputs.'}
    $rows=[Collections.Generic.List[string]]::new()
    $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $prefix=$rootPath+[IO.Path]::DirectorySeparatorChar
    $comparison=if([OperatingSystem]::IsWindows()){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    foreach($path in $paths){
        $file=[IO.Path]::GetFullPath((Join-Path $Root $path))
        if(-not $file.StartsWith($prefix,$comparison)){throw 'SDK raw source input escaped its checkout.'}
        # Bootstrap cannot import its subject's implementation. Use direct IO here to preserve every
        # path/reparse/raw-byte check without thousands of PowerShell filesystem-provider round trips.
        $cursor=$file
        while($cursor.Equals($rootPath,$comparison) -or $cursor.StartsWith($prefix,$comparison)){
            $attributes=[IO.File]::GetAttributes($cursor) # Missing/inaccessible inputs fail rather than disappear.
            if($attributes -band [IO.FileAttributes]::ReparsePoint){throw 'SDK raw source reparse path refused.'}
            if($cursor -ceq $file -and ($attributes -band [IO.FileAttributes]::Directory)){throw 'SDK raw source requires a file.'}
            if($cursor.Equals($rootPath,$comparison)){break}
            $cursor=[IO.Path]::GetDirectoryName($cursor)
        }
        $stream=[IO.File]::OpenRead($file)
        try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()}
        $rows.Add($path+[char]0+$hash)
    }
    return Get-CiSha256 ($rows -join "`n")
}

function Get-CiPinnedEngineInputsIdentity {
    <#
    .SYNOPSIS
        Identifies the actual pinned local engine inputs before local evidence reuse.
    .DESCRIPTION
        Requires the project's ordinary .ci-engine Git checkout at its exact clean pin.
        Hashes raw current file bytes, including same-size/backdated edits, through the
        canonical checkout projection. No timestamp cache, compiler, remote API or qualification verdict.
    .PARAMETER Root
        Product checkout containing .ci/project.json and the generated .ci-engine checkout.
    .PARAMETER EngineRoot
        Defaults to this module's engine root. An explicit value must still be the selected
        project's exact .ci-engine location; it is useful for isolated data-only fixtures.
    .OUTPUTS
        SHA-256 over checkout location, exact pin/HEAD and current raw engine content identity.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [string]$EngineRoot=(Join-Path $PSScriptRoot '../..'))
    $projectRoot=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $engine=[IO.Path]::GetFullPath($EngineRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $expected=Assert-CiContainedPath $projectRoot (Join-Path $projectRoot '.ci-engine')
    $comparison=if([OperatingSystem]::IsWindows()){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(-not $engine.Equals($expected,$comparison)){throw 'Local engine inputs require the selected project exact .ci-engine checkout.'}
    $project=Read-CiProject $projectRoot
    $top=(Invoke-CiGit $engine @('rev-parse','--show-toplevel')).stdout.Trim()
    if(-not [IO.Path]::GetFullPath($top).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Equals($engine,$comparison)){
        throw 'Local engine inputs require an independent .ci-engine Git checkout.'
    }
    $head=Resolve-CiCommit $engine HEAD
    if($head -cne $project.engine.ref){throw 'Local engine checkout does not match .ci/project.json exact pin.'}
    $content=Get-CiCheckoutContentIdentity $engine
    if((Invoke-CiGit $engine @('-c','core.fsmonitor=false','status','--porcelain','--untracked-files=all')).stdout.Trim()){
        throw 'Local engine checkout must be clean before reusable evidence is consulted.'
    }
    # Windows checkout aliases differ only in casing; preserve the physical checkout identity.
    $identityRoot=if([OperatingSystem]::IsWindows()){$projectRoot.ToLowerInvariant()}else{$projectRoot}
    $identityEngine=if([OperatingSystem]::IsWindows()){$engine.ToLowerInvariant()}else{$engine}
    return Get-CiSha256 ($identityRoot+[char]0+$identityEngine+[char]0+$head+[char]0+$content)
}

Export-ModuleMember -Function Get-CiCheckoutContentIdentity,Get-CiPinnedEngineInputsIdentity
