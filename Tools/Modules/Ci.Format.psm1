Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Ci.GitHub.psm1') -ErrorAction Stop

function Install-CiFormatter {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    if (-not [OperatingSystem]::IsWindows()) { throw 'The common formatter job uses the pinned Windows x64 formatter.' }
    $pin = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Policy/clang-format.json') -Raw | ConvertFrom-Json
    $cache = Assert-CiContainedPath $Root (Join-Path $Root '.build/shared-format')
    [void][IO.Directory]::CreateDirectory($cache)
    $lockPath = Assert-CiContainedPath $Root (Join-Path $cache '.install.lock')
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $wheel = Assert-CiContainedPath $Root (Join-Path $cache 'clang-format.whl')
        if (-not (Test-Path -LiteralPath $wheel) -or (Get-FileHash -LiteralPath $wheel -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pin.sha256) {
            $temporary = Assert-CiContainedPath $Root (Join-Path $cache ([guid]::NewGuid().ToString('N') + '.tmp'))
            Invoke-WebRequest -Uri $pin.url -OutFile $temporary -TimeoutSec 120
            if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pin.sha256) { throw 'Pinned formatter wheel checksum mismatch; preserve the failed download.' }
            [IO.File]::Move($temporary, $wheel, $true)
        }
        $executable = Assert-CiContainedPath $Root (Join-Path $cache 'clang-format.exe')
        $archive = [IO.Compression.ZipFile]::OpenRead($wheel)
        try {
            $entry = $archive.GetEntry($pin.entry)
            if (-not $entry -or $entry.Length -le 0) { throw 'Pinned formatter wheel lacks its expected executable.' }
            $source = $entry.Open()
            try {
                $memory = [IO.MemoryStream]::new()
                try { $source.CopyTo($memory); $bytes = $memory.ToArray() } finally { $memory.Dispose() }
            } finally { $source.Dispose() }
        } finally { $archive.Dispose() }
        $expectedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        if (-not (Test-Path -LiteralPath $executable) -or (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedHash) {
            $stage = Assert-CiContainedPath $Root (Join-Path $cache ([guid]::NewGuid().ToString('N') + '.exe'))
            [IO.File]::WriteAllBytes($stage, $bytes)
            [IO.File]::Move($stage, $executable, $true)
        }
        $version = (Invoke-CiProcess $executable @('--version') $Root).stdout.Trim()
        if ($version -notmatch ('^clang-format version ' + [regex]::Escape($pin.version) + '(\s|$)')) { throw 'Pinned formatter version mismatch.' }
        return $executable
    } finally { $lock.Dispose() }
}

function Invoke-CiFormatting {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Base,
        [AllowNull()][System.Collections.IDictionary]$Project)
    if (-not $Project) { $Project = Read-CiProject $Root -Ref HEAD }
    $changed = Get-CiChangedPaths $Root $Base
    $configChanged = @($changed | Where-Object { [IO.Path]::GetFileName($_) -in @('.clang-format','.clang-format-ignore') }).Count -gt 0
    if ($configChanged) {
        $paths = @((Invoke-CiGit $Root @('ls-files', '-z')).stdout.Split([char]0) | Where-Object { $_ })
    } else { $paths = @($changed) }
    $sources = [Collections.Generic.List[string]]::new()
    foreach ($path in $paths) {
        if ([IO.Path]::GetExtension($path).ToLowerInvariant() -notin @('.c','.cc','.cpp','.cxx','.h','.hh','.hpp','.hxx')) { continue }
        $owned = @($Project.formatRoots | Where-Object { $_ -eq '.' -or $path.StartsWith(($_.TrimEnd('/') + '/'), [StringComparison]::Ordinal) }).Count -gt 0
        if (-not $owned) { continue }
        if ($Project.Contains('formatExclude') -and @($Project.formatExclude | Where-Object { Test-CiGlob $path $_ }).Count -gt 0) { continue }
        $fullPath = Assert-CiContainedPath $Root (Join-Path $Root $path)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
        $sources.Add($path)
    }
    if ($sources.Count) {
        $rootStyle=Assert-CiContainedPath $Root (Join-Path $Root '.clang-format')
        if(-not(Test-Path -LiteralPath $rootStyle -PathType Leaf) -or [IO.File]::ReadAllText($rootStyle) -match 'InheritParentConfig'){
            throw 'Formatting requires an owned root style that cannot inherit configuration outside the checkout.'
        }
        foreach($path in $sources){
            $directory=[IO.Path]::GetDirectoryName((Join-Path $Root $path))
            while($directory){
                foreach($name in @('.clang-format','.clang-format-ignore')){
                    $null=Assert-CiContainedPath $Root (Join-Path $directory $name)
                }
                if([IO.Path]::GetFullPath($directory).TrimEnd('\','/') -ceq [IO.Path]::GetFullPath($Root).TrimEnd('\','/')){break}
                $directory=[IO.Path]::GetDirectoryName($directory)
            }
        }
        $formatter = Install-CiFormatter $Root
        foreach ($path in $sources) {
            $null = Invoke-CiProcess $formatter @('--style=file', '--Werror', '-i', '--', $path) $Root
        }
    }
    $patch = (Invoke-CiGit $Root @('diff', '--binary', '--no-ext-diff')).stdout
    $changedAfter = Get-CiChangedPaths -Root $Root -Base HEAD -WorkingTree
    foreach ($path in $changedAfter) {
        if (-not $sources.Contains($path)) { throw "Formatter changed a path outside its declared source selection: $path" }
    }
    $output = Assert-CiContainedPath $Root (Join-Path $Root '.build/ci/format.patch')
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $output))
    [IO.File]::WriteAllText($output, $patch, [Text.UTF8Encoding]::new($false))
    [ordered]@{ drift = -not [string]::IsNullOrEmpty($patch); checked = $sources.Count; changedPaths = $changedAfter; patch = $output }
}

function Invoke-CiFormatCommit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][int]$PullRequest)
    if ($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REF -cne 'refs/heads/main' -or $env:GITHUB_REPOSITORY -cne $Repository) { throw 'Formatting commits require an explicit trusted default-branch dispatch.' }
    $pr = Invoke-CiApi "repos/$Repository/pulls/$PullRequest"
    if ($pr.state -cne 'open' -or $pr.head.repo.full_name -cne $Repository -or $pr.base.ref -cne 'main') { throw 'Only an open same-repository PR targeting main can receive a formatting commit; forks use the retained patch.' }
    $head = [string]$pr.head.sha; $base = [string]$pr.base.sha; $branch = [string]$pr.head.ref
    if ($head -notmatch '^[a-f0-9]{40}$' -or $base -notmatch '^[a-f0-9]{40}$') { throw 'Invalid PR source identity.' }
    $null = Invoke-CiGit $Root @('check-ref-format', ('refs/heads/' + $branch))
    if ((Invoke-CiGit $Root @('status', '--porcelain')).stdout.Trim()) { throw 'Formatter requires a clean source checkout.' }
    $trustedProject = Read-CiProject $Root -Ref HEAD
    $null = Invoke-CiGit $Root @('fetch', '--no-tags', 'origin', $head, $base)
    $null = Invoke-CiGit $Root @('checkout', '--detach', $head)
    $mergeBase = (Invoke-CiGit $Root @('merge-base', $base, $head)).stdout.Trim()
    $result = Invoke-CiFormatting $Root $mergeBase $trustedProject
    if (-not $result.drift) { Write-Host 'Formatting is already current; no commit or push.'; return }
    $latest = Invoke-CiApi "repos/$Repository/pulls/$PullRequest"
    if ($latest.state -cne 'open' -or $latest.head.sha -cne $head) { throw 'PR head moved while formatting; retain the patch and do not push.' }
    $pathList = Assert-CiContainedPath $Root (Join-Path $Root '.build/ci/format.paths')
    [IO.File]::WriteAllText($pathList, (($result.changedPaths -join [char]0) + [char]0), [Text.UTF8Encoding]::new($false))
    $null = Invoke-CiGit $Root @('--literal-pathspecs', 'add', ('--pathspec-from-file=' + $pathList), '--pathspec-file-nul')
    $null = Invoke-CiGit $Root @('-c', 'user.name=github-actions[bot]', '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com', 'commit', '-m', 'Apply clang-format to PR source files')
    $newHead = (Invoke-CiGit $Root @('rev-parse', 'HEAD')).stdout.Trim()
    # Ordinary fast-forward push refuses a concurrent head change; there is no force update.
    $null = Invoke-CiGit $Root @('push', 'origin', ('HEAD:refs/heads/' + $branch))
    $published = Invoke-CiApi "repos/$Repository/pulls/$PullRequest"
    # Git and PR metadata become visible separately. Wait only for the expected old-to-new
    # transition; a different head or closed/retargeted PR is never accepted.
    for ($attempt = 0; $attempt -lt 5 -and $published.head.sha -ceq $head; ++$attempt) {
        Start-Sleep -Seconds 2
        $published = Invoke-CiApi "repos/$Repository/pulls/$PullRequest"
    }
    if ($published.state -cne 'open' -or $published.base.ref -cne 'main' -or $published.head.ref -cne $branch -or $published.head.sha -cne $newHead) { throw 'Formatting commit identity was not confirmed; request exact-head checks explicitly before merging.' }
    # Execute trusted main YAML, with read-only PR checkout and a separate trusted status writer.
    $null = Invoke-CiApi "repos/$Repository/actions/workflows/ci.yml/dispatches" -Method POST -Body @{
        ref = 'main'; inputs = @{ pr_number = [string]$PullRequest; expected_head = $newHead } }
    Write-Host "Committed formatting at $newHead and explicitly requested fresh PR checks."
}

Export-ModuleMember -Function Install-CiFormatter, Invoke-CiFormatting, Invoke-CiFormatCommit
