<#
.SYNOPSIS Runs one explicitly requested native tool in a private child metadata namespace.
.PARAMETER FilePath Native application path or command name; scripts must use their actual host explicitly.
.PARAMETER WorkingDirectory Existing command working directory.
.PARAMETER ArgumentsJson JSON array of literal string arguments, at most 12000 characters.
.OUTPUTS Original native console output and original native process exit code.
.NOTES Internal child bridge for Invoke-CiNativeCommand. Requires native execution permission; refuses compiler-free execution before launching. Uses a new private Windows MSVC PDB endpoint, changes no calling-process environment and interprets argument data only as strings. No command-string evaluation, credentials, branch writes or process-name cleanup. Synchronous native output remains live in the existing console.
.EXAMPLE ./Tools/Invoke-NativeTool.ps1 -FilePath '<discovered MSBuild.exe>' -WorkingDirectory . -ArgumentsJson '["project.proj","/nologo"]'
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$FilePath,[Parameter(Mandatory)][string]$WorkingDirectory,
    [Parameter(Mandatory)][AllowEmptyString()][string]$ArgumentsJson)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:CI_NATIVE_BUILDS_DISABLED -ceq 'true'){throw 'Native tool invocation is forbidden in compiler-free execution.'}
if($ArgumentsJson.Length -gt 12000){throw 'Native argument payload exceeds the supported direct command-line size.'}
$values=ConvertFrom-Json -InputObject $ArgumentsJson -NoEnumerate
if($values -isnot [array]){throw 'Native arguments must be a JSON array.'}
foreach($value in $values){
    if($value -isnot [string] -or $value.Contains([char]0)){throw 'Native arguments must be literal strings without NUL.'}
}
$nativeArguments=[string[]]@($values)
$directory=(Resolve-Path -LiteralPath $WorkingDirectory -ErrorAction Stop).Path
if(-not(Test-Path -LiteralPath $directory -PathType Container)){throw 'Native working directory must already exist.'}
if(Test-Path -LiteralPath $FilePath -PathType Leaf){
    if([IO.Path]::GetExtension($FilePath) -in @('.ps1','.psm1','.psd1')){throw 'Scripts require their actual native host explicitly.'}
    $nativePath=(Get-Item -LiteralPath $FilePath).FullName
}else{
    if([Management.Automation.WildcardPattern]::ContainsWildcardCharacters($FilePath)){throw 'Native application names must be literal.'}
    $nativePath=(Get-Command -Name $FilePath -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
}
Import-Module (Join-Path $PSScriptRoot 'Modules/Ci.Policy.psm1')
$context=[Diagnostics.ProcessStartInfo]::new();$context.FileName=$nativePath;$context.UseShellExecute=$false
$endpoint=Set-CiNativeProcessEnvironment -ProcessStartInfo $context
if($endpoint){$env:_MSPDBSRV_ENDPOINT_=$endpoint}
Set-Location -LiteralPath $directory
# Preserve native failures as their exact exit rather than converting them to a
# PowerShell exception before the ordinary caller checks its result.
$PSNativeCommandUseErrorActionPreference=$false
& $nativePath @nativeArguments
exit $LASTEXITCODE
