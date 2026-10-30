Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function Test-CiProductionReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Receipt,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Descriptor,
        [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform, [string]$Directory = '')
    foreach ($field in @('schemaVersion','repository','commit','nativeDigest','engine','platform','version','buildNumber',
            'role','testModeDisabled','smokePassed','kind','archives','runId')) {
        if (-not $Receipt.Contains($field)) { throw "Missing production receipt field: $field" }
    }
    if ($Receipt.schemaVersion -ne 1 -or $Receipt.repository -cne $Descriptor.repository -or
        $Receipt.commit -cne $Descriptor.commit -or $Receipt.nativeDigest -cne $Descriptor.nativeDigest -or
        $Receipt.engine.repository -cne $Descriptor.engine.repository -or $Receipt.engine.ref -cne $Descriptor.engine.ref -or
        $Receipt.platform -cne $Platform -or $Receipt.version -cne $Descriptor.version -or
        $Receipt.buildNumber -ne $Descriptor.buildNumber -or $Receipt.runId -cne $Descriptor.runId -or
        $Receipt.role -cne 'ProductionRelease') { throw 'Production receipt identity mismatch.' }
    foreach ($flag in @('testModeDisabled','smokePassed')) {
        if ($Receipt[$flag] -isnot [bool] -or -not $Receipt[$flag]) { throw "Production prerequisite did not pass: $flag" }
    }
    $kind = if ($Descriptor.repository -ceq 'RedSalamanders/DxUi') { 'sdk' } else { 'application' }
    if ($Receipt.kind -cne $kind -or -not @($Receipt.archives).Count) { throw 'Wrong or empty product archive kind.' }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($archive in $Receipt.archives) {
        if ($archive.file -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.zip$' -or $archive.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
            ($archive.size -isnot [int] -and $archive.size -isnot [long]) -or $archive.size -le 0 -or -not $names.Add($archive.file)) {
            throw 'Invalid or duplicate ZIP archive descriptor.'
        }
        if ($Directory) {
            $file = Assert-CiContainedPath $Directory (Join-Path $Directory $archive.file)
            if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -ne $archive.size -or
                (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $archive.sha256) { throw 'Qualified ZIP is missing or its bytes changed.' }
        }
    }
    if ($Directory) {
        $actual = @(Get-ChildItem -LiteralPath $Directory -Filter '*.zip' -File)
        if ($actual.Count -ne $names.Count -or @($actual | Where-Object { -not $names.Contains($_.Name) }).Count) { throw 'Unqualified extra ZIP in the production artifact.' }
    }
    return $true
}

function Test-CiQualification {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][System.Collections.IDictionary]$Descriptor,
        [ValidateSet('Regression','Complete')][string]$Phase = 'Complete')
    foreach ($platform in @('x64','ARM64')) {
        $regressions = @(Get-ChildItem -LiteralPath $Directory -Recurse -Filter "regression-$platform.json" -File)
        if ($regressions.Count -ne 1) { throw "Exactly one $platform regression receipt is required." }
        $receipt = Get-Content -LiteralPath $regressions[0].FullName -Raw | ConvertFrom-Json -AsHashtable
        $null = Test-CiRegressionReceipt $receipt $Descriptor $platform
        if ($Phase -eq 'Complete') {
            $productions = @(Get-ChildItem -LiteralPath $Directory -Recurse -Filter "production-$platform.json" -File)
            if ($productions.Count -ne 1) { throw "Exactly one $platform production receipt is required." }
            $production = Get-Content -LiteralPath $productions[0].FullName -Raw | ConvertFrom-Json -AsHashtable
            $null = Test-CiProductionReceipt $production $Descriptor $platform $productions[0].DirectoryName
        }
    }
    Write-Host "Both native architectures have complete, matching $Phase evidence."
    return $true
}

Export-ModuleMember -Function Test-CiProductionReceipt, Test-CiQualification

