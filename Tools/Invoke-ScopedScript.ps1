<#
.SYNOPSIS
Runs one product script with JSON-encoded parameters in this PowerShell process.
.DESCRIPTION
Internal child bridge for Tools/Test-Changes.ps1, which starts it in its own pwsh process for the product's build.ps1
and test.ps1, so that an array parameter such as -Suites reaches the script as an array and the product script never
shares the runner's modules. Parameter values are data: a string, an array of strings, an integer, or true for a
switch. No command-string evaluation.
.PARAMETER Script
Full path of the product's .ps1 script.
.PARAMETER WorkingDirectory
Existing folder the script runs in (the product root).
.PARAMETER ParametersJson
JSON object mapping parameter names to values, at most 12000 characters.
.OUTPUTS
The script's own console output. The process exits with the script's exit code, or 1 when the script fails.
.NOTES
Requires PowerShell 7. Side effects are the script's own.
.EXAMPLE
./Tools/Invoke-ScopedScript.ps1 -Script D:/Product/test.ps1 -WorkingDirectory D:/Product -ParametersJson '{"Suites":["Core"],"SkipBuild":true}'
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Script, [Parameter(Mandatory)][string]$WorkingDirectory, [Parameter(Mandatory)][string]$ParametersJson)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($ParametersJson.Length -gt 12000) { throw 'The product script parameters exceed the supported command-line size.' }
if (-not [IO.File]::Exists($Script) -or [IO.Path]::GetExtension($Script) -cne '.ps1') { throw "Not a product script: $Script" }
if (-not [IO.Directory]::Exists($WorkingDirectory)) { throw "The working directory does not exist: $WorkingDirectory" }
$values = ConvertFrom-Json -InputObject $ParametersJson -AsHashtable
if ($values -isnot [Collections.IDictionary]) { throw 'Product script parameters must be a JSON object.' }
$parameters = @{}
foreach ($name in @($values.Keys)) {
    if ($name -cnotmatch '^[A-Za-z][A-Za-z0-9]*$') { throw "Invalid parameter name: $name" }
    $value = $values[$name]
    if ($value -is [bool]) {
        if (-not $value) { throw "A switch is passed as true or not at all: $name" }
        $parameters[$name] = [switch]::Present
    } elseif ($value -is [string]) {
        $parameters[$name] = $value
    } elseif ($value -is [long] -or $value -is [int]) {
        $parameters[$name] = [int]$value
    } elseif ($value -is [Collections.IList]) {
        foreach ($item in $value) { if ($item -isnot [string]) { throw "Array parameter $name holds a value that is not a string." } }
        $parameters[$name] = [string[]]@($value)
    } else { throw "Unsupported value for parameter ${name}." }
}
Set-Location -LiteralPath $WorkingDirectory
$global:LASTEXITCODE = 0
& $Script @parameters
$succeeded = $?
$code = $LASTEXITCODE
if ($code) { exit $code }
if (-not $succeeded) { exit 1 }
exit 0
