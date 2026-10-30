<#
.SYNOPSIS
Updates a project's shared-engine pin and regenerates its common thin callers together.
.PARAMETER Root
One RedSalamanders project checkout.
.PARAMETER EngineRef
Exact clean engine commit currently checked out beside this command.
.OUTPUTS
Updated .ci/project.json and canonical CI caller files. No commit, push or native build.
.NOTES
Requires PowerShell 7.4 and Git. Explicit maintenance command; review the diff and run compiler-free
adapter checks before submitting the pin update. Dependabot ignores this multi-file engine dependency.
.EXAMPLE
./Tools/Update-ProjectPin.ps1 -Root ../RedMonitor -EngineRef 0123456789012345678901234567890123456789
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$EngineRef)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$engine=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Policy.psm1')
$project=Read-CiProject $Root
if((Resolve-CiCommit $engine HEAD) -cne $EngineRef -or (Invoke-CiGit $engine @('status','--porcelain','--untracked-files=no')).stdout.Trim()){
    throw 'Use the exact clean reviewed engine commit; a mutable development checkout cannot publish a pin.'
}
$old=$project.engine.ref
$project.engine.ref=$EngineRef
$rootPath=[IO.Path]::GetFullPath($Root)
foreach($template in Get-ChildItem (Join-Path $engine 'Templates') -Filter '*.yml'){
    $operations=if($project.kind -ceq 'sdk'){'Prepare, Release'}else{'Prepare, Release, Winget'}
    $content=[IO.File]::ReadAllText($template.FullName).Replace('@ENGINE@',$EngineRef).Replace('@OPERATIONS@',$operations)
    $path=Assert-CiContainedPath $rootPath (Join-Path $rootPath ('.github/workflows/'+$template.Name))
    [IO.File]::WriteAllText($path,$content,[Text.UTF8Encoding]::new($false))
}
# Historical sealed and metadata-only definitions retain their reviewed bytes.
foreach($name in @('asan.yml','nightly-ci.yml')){
    $path=Join-Path $rootPath ('.github/workflows/'+$name)
    if(Test-Path -LiteralPath $path){
        $content=[IO.File]::ReadAllText($path)
        if($content.Contains('RedSalamanders/.github/.github/workflows/qualification.yml@')){
            [IO.File]::WriteAllText($path,$content.Replace($old,$EngineRef),[Text.UTF8Encoding]::new($false))
        }
    }
}
$manifest=Assert-CiContainedPath $rootPath (Join-Path $rootPath '.ci/project.json')
[IO.File]::WriteAllText($manifest,($project|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
Write-Host "Updated $($project.repository) from $old to $EngineRef. Review, validate and submit this change."

