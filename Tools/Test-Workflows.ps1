<#
.SYNOPSIS
Lints GitHub workflow syntax with the checksum-pinned native actionlint executable.
.PARAMETER Root
Project or engine checkout. Stores the verified tool below .build/ci/tools only.
.OUTPUTS
Workflow syntax diagnostics; nonzero on an invalid workflow.
.NOTES
Requires Windows x64/PowerShell 7.4 and HTTPS for an uncached download. No compiler or native build.
Rejects unsafe/reparse output paths and verifies both archive and executable digests.
.EXAMPLE
./Tools/Test-Workflows.ps1 -Root ../RedMonitor
#>
[CmdletBinding()]
param([string]$Root='.')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Policy.psm1')
$Root=[IO.Path]::GetFullPath($Root)
$policy=Get-Content (Join-Path $PSScriptRoot '../Policy/workflow-lint.json') -Raw|ConvertFrom-Json -AsHashtable
if(-not $IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -cne 'X64'){throw 'The pinned workflow linter entry point requires Windows x64; it never compiles a fallback tool.'}
$cache=Assert-CiContainedPath $Root (Join-Path $Root ('.build/ci/tools/actionlint-'+$policy.version))
[void][IO.Directory]::CreateDirectory($cache)
$executable=Assert-CiContainedPath $Root (Join-Path $cache 'actionlint.exe')
if(-not(Test-Path -LiteralPath $executable) -or (Get-FileHash -LiteralPath $executable).Hash.ToLowerInvariant() -cne $policy.executableSha256){
    $archive=Assert-CiContainedPath $Root (Join-Path $cache ('download-'+[guid]::NewGuid().ToString('N')+'.zip'))
    Invoke-WebRequest -Uri $policy.url -OutFile $archive -TimeoutSec 120
    if((Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant() -cne $policy.archiveSha256){throw 'Workflow linter archive checksum mismatch.'}
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try{
        $entry=$zip.GetEntry('actionlint.exe')
        if(-not $entry){throw 'The verified workflow linter archive lacks its executable.'}
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$executable,$true)
    }finally{$zip.Dispose()}
    if((Get-FileHash -LiteralPath $executable).Hash.ToLowerInvariant() -cne $policy.executableSha256){throw 'Workflow linter executable checksum mismatch.'}
}
$files=@(Get-ChildItem -LiteralPath (Join-Path $Root '.github/workflows') -Filter '*.yml' -File|ForEach-Object FullName)
if(-not $files.Count){throw 'No workflow files found.'}
foreach($file in $files){$null=Test-CiWorkflowQueues ([IO.File]::ReadAllText($file))}
# The preview label is a real hosted native ARM64 label not yet in actionlint's static catalog.
$config=Join-Path $PSScriptRoot '../.github/actionlint.yaml'
# v1.7.12 predates GitHub's queue:max syntax. Validate that field ourselves against
# the official concurrency contract; suppress only the obsolete unknown-key diagnostic.
$null=Invoke-CiProcess -FilePath $executable -Arguments (@('-config-file',[IO.Path]::GetFullPath($config),
    '-ignore','unexpected key "queue" for "concurrency" section')+$files) -WorkingDirectory $Root -TimeoutSeconds 60
Write-Host "Validated syntax of $($files.Count) workflow definitions."

