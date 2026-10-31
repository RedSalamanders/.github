<#
.SYNOPSIS
Updates a project's shared-engine pin and regenerates its common thin callers together.
.PARAMETER Root
One RedSalamanders project checkout.
.PARAMETER EngineRef
Exact clean engine commit currently checked out beside this command.
.OUTPUTS
Updated .ci/project.json and canonical CI caller files. Removes an SDK's unchanged legacy publication caller.
No commit, push or native build.
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
$legacyPublication=Assert-CiContainedPath $rootPath (Join-Path $rootPath '.github/workflows/publish.yml')
if($project.kind -ceq 'sdk' -and (Test-Path -LiteralPath $legacyPublication)){
    # Only the old generated caller is an owned migration input. Preserve custom work for review.
    $lf=[string][char]10;$crlf=[string][char]13+$lf
    $expected=[IO.File]::ReadAllText((Join-Path $engine 'Templates/publish.yml')).Replace('@ENGINE@',$old).Replace('@OPERATIONS@','Prepare, Release').Replace($crlf,$lf).TrimEnd()
    if([IO.File]::ReadAllText($legacyPublication).Replace($crlf,$lf).TrimEnd() -cne $expected){
        throw 'SDK publication caller has custom changes; review it before removing the workflow.'
    }
}
foreach($template in Get-CiProjectWorkflowTemplates -Project $project){
    $content=[IO.File]::ReadAllText($template.FullName).Replace('@ENGINE@',$EngineRef).Replace('@OPERATIONS@','Prepare, Release, Winget')
    $path=Assert-CiContainedPath $rootPath (Join-Path $rootPath ('.github/workflows/'+$template.Name))
    [IO.File]::WriteAllText($path,$content,[Text.UTF8Encoding]::new($false))
}
if($project.kind -ceq 'sdk' -and (Test-Path -LiteralPath $legacyPublication)){
    Remove-Item -LiteralPath $legacyPublication
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

