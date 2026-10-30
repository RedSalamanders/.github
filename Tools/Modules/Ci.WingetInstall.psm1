Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -Scope Local
Import-Module (Join-Path $PSScriptRoot 'Ci.Project.psm1') -Scope Local

function Read-CiInstalledPortablePackage {
    param([string]$Identifier)
    foreach($hive in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall')){
        foreach($key in @(Get-ChildItem -LiteralPath $hive -ErrorAction SilentlyContinue)){
            $entry=Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if($entry.PSObject.Properties['WinGetPackageIdentifier'] -and $entry.WinGetPackageIdentifier -ieq $Identifier){
                if(-not $entry.PSObject.Properties['InstallLocation'] -or -not $entry.PSObject.Properties['DisplayVersion']){throw 'Installed portable package has incomplete registration.'}
                @{identifier=$entry.WinGetPackageIdentifier;version=$entry.DisplayVersion;location=$entry.InstallLocation}
            }
        }
    }
}

function Read-CiInstalledAlias {
    param([string]$Command,[string]$Platform)
    $path=Join-Path $env:LOCALAPPDATA ("Microsoft/WinGet/Links/$Command.exe")
    $file=Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if(-not $file){return $null}
    $target=$file.ResolveLinkTarget($true)
    if(-not $target -or -not [IO.File]::Exists($target.FullName)){throw "Portable alias is not a valid file link: $Command"}
    $null=Assert-CiPeArchitecture -Path $target.FullName -Platform $Platform
    $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($target.FullName)
    return @{path=$path;target=$target.FullName;version=("$($version.FileMajorPart).$($version.FileMinorPart).$($version.FileBuildPart)")}
}

function Invoke-CiOwnedWingetInstall {
    <#
    .SYNOPSIS
        Prove an owned unpublished portable install, every alias, declared smoke and cleanup.
    .DESCRIPTION
        Registration is read directly because winget list may not correlate an unpublished
        manifest with an upstream source. Never removes a pre-existing/foreign installation.
        Provider parameters exist for deterministic tests; the hosted CLI uses native providers.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Plan,
        [Parameter(Mandatory)][string]$Manifest,[Parameter(Mandatory)][string]$Scratch,
        [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,
        [Parameter(Mandatory)][string]$Winget,
        [scriptblock]$ReadInstalled={param($Id) Read-CiInstalledPortablePackage $Id},
        [scriptblock]$ReadAlias={param($Command,$Architecture) Read-CiInstalledAlias $Command $Architecture},
        [scriptblock]$Execute)
    if(-not $Execute){
        $Execute={param($File,$Arguments,$Seconds) Invoke-CiProcess -FilePath $File -Arguments $Arguments -WorkingDirectory $Scratch -TimeoutSeconds $Seconds -AllowFailure}
    }
    $package=$Plan.project.winget.identifier
    $commands=@(@{executable=$Plan.project.winget.executable;alias=$Plan.project.winget.alias})
    if($Plan.project.winget.Contains('additionalCommands')){$commands+=@($Plan.project.winget.additionalCommands)}
    if(@($commands.alias|Sort-Object -Unique).Count -ne $commands.Count){throw 'Portable aliases must be unique.'}
    foreach($command in $commands){
        if($command.alias -cnotmatch '^[A-Za-z0-9-]+$' -or $command.executable -cnotmatch '^[A-Za-z0-9]+[.]exe$'){throw 'Unsafe portable command declaration.'}
    }
    $smokes=@()
    if($Plan.project.winget.Contains('smokeTests')){
        foreach($smoke in $Plan.project.winget.smokeTests){
            if(@($commands|Where-Object alias -ceq $smoke.command).Count -ne 1 -or
                $smoke.timeoutSeconds -lt 1 -or $smoke.timeoutSeconds -gt 600 -or @($smoke.arguments).Count -gt 32){
                throw 'Smoke must name a declared portable alias and a bounded argument vector.'
            }
            $smokes+=@($smoke)
        }
    }
    if(@(& $ReadInstalled $package).Count){throw 'The exact package must be absent before this owned operation.'}
    foreach($command in $commands){if(& $ReadAlias $command.alias $Platform){throw "Portable alias already exists: $($command.alias)"}}
    function Run-Owned([string]$File,[string[]]$Arguments,[int]$Seconds,[string]$LogName){
        try {$result=& $Execute $File $Arguments $Seconds}
        catch {[IO.File]::WriteAllText((Join-Path $Scratch $LogName),(Protect-CiDiagnostic $_.Exception.Message));throw}
        [IO.File]::WriteAllText((Join-Path $Scratch $LogName),(Protect-CiDiagnostic ($result.stdout+$result.stderr)))
        if($result.exitCode -ne 0){throw "Owned install/probe command failed with exit $($result.exitCode); see $LogName"}
        return $result
    }
    $installRoot=[IO.Path]::GetFullPath((Join-Path $Scratch 'installed')).TrimEnd('\','/')
    function Assert-OwnedRegistration($Entry){
        $location=[IO.Path]::GetFullPath([string]$Entry.location).TrimEnd('\','/')
        if($Entry.identifier -ine $package -or $Entry.version -cne $Plan.batch.version -or
            ($location -ine $installRoot -and -not $location.StartsWith($installRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){
            throw 'Portable registration is foreign, stale or outside this operation; refuse uninstall.'
        }
    }
    $owned=$false;$passed=$false;$probes=0
    try{
        $null=Run-Owned $Winget @('settings','--enable','LocalManifestFiles') 180 'settings.log'
        $null=Run-Owned $Winget @('validate','--manifest',[IO.Path]::GetFullPath($Manifest)) 180 'validate.log'
        $owned=$true
        $null=Run-Owned $Winget @('install','--manifest',[IO.Path]::GetFullPath($Manifest),'--location',$installRoot,'--scope','user',
            '--accept-package-agreements','--accept-source-agreements','--disable-interactivity') 600 'install.log'
        $entries=@(& $ReadInstalled $package)
        if($entries.Count -ne 1){throw 'Expected one exact portable Apps & features registration.'}
        Assert-OwnedRegistration $entries[0]
        foreach($command in $commands){
            $alias=& $ReadAlias $command.alias $Platform
            if(-not $alias){throw "Portable command alias is missing: $($command.alias)"}
            $target=[IO.Path]::GetFullPath($alias.target)
            if(-not $target.StartsWith($installRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
                [IO.Path]::GetFileName($target) -cne $command.executable -or $alias.version -cne $Plan.batch.version){
                throw 'Portable alias does not resolve to its exact owned executable/version.'
            }
            $null=Run-Owned $alias.path @('--help') 120 ("alias-$($command.alias)-help.log");$probes++
            foreach($smoke in @($smokes|Where-Object command -ceq $command.alias)){
                $null=Run-Owned $alias.path @($smoke.arguments) ([int]$smoke.timeoutSeconds) ("alias-$($command.alias)-smoke-$probes.log");$probes++
            }
        }
        $passed=$true
    }finally{
        if($owned){
            $entries=@(& $ReadInstalled $package)
            if($entries.Count -gt 1){throw 'Ambiguous install ownership; preserve evidence without uninstalling.'}
            if($entries.Count -eq 1){
                Assert-OwnedRegistration $entries[0]
                $null=Run-Owned $Winget @('uninstall','--manifest',[IO.Path]::GetFullPath($Manifest),'--version',$Plan.batch.version,
                    '--scope','user','--silent','--purge','--accept-source-agreements','--disable-interactivity') 300 'uninstall.log'
            }
            if(@(& $ReadInstalled $package).Count){throw 'Owned portable registration remained after uninstall.'}
            foreach($command in $commands){if(& $ReadAlias $command.alias $Platform){throw 'Owned portable alias remained after uninstall.'}}
        }
    }
    if(-not $passed){throw 'Native portable installation did not qualify.'}
    return @{passed=$true;cleanedUp=$true;aliases=$commands.Count;probes=$probes}
}

function Test-CiWingetInstallReceipt {
    [CmdletBinding()]
    param([System.Collections.IDictionary]$Receipt,[System.Collections.IDictionary]$Plan,
        [ValidateSet('x64','ARM64')][string]$Platform,[string]$RunId,[string]$ManifestDigest)
    foreach($key in @('schemaVersion','passed','cleanedUp','platform','commit','nativeDigest','runId','version','manifestDigest','aliases','probes')){
        if(-not $Receipt.Contains($key)){throw 'winget install evidence lacks alias/probe or identity proof.'}
    }
    $aliases=1
    if($Plan.project.winget.Contains('additionalCommands')){$aliases+=@($Plan.project.winget.additionalCommands).Count}
    $probes=$aliases
    if($Plan.project.winget.Contains('smokeTests')){$probes+=@($Plan.project.winget.smokeTests).Count}
    if($Receipt.schemaVersion -ne 1 -or $Receipt.passed -isnot [bool] -or -not $Receipt.passed -or
        $Receipt.cleanedUp -isnot [bool] -or -not $Receipt.cleanedUp -or $Receipt.platform -cne $Platform -or
        $Receipt.commit -cne $Plan.batch.commit -or $Receipt.nativeDigest -cne $Plan.batch.nativeDigest -or
        $Receipt.runId -cne $RunId -or $Receipt.version -cne $Plan.batch.version -or $Receipt.manifestDigest -cne $ManifestDigest -or
        ($Receipt.aliases -isnot [int] -and $Receipt.aliases -isnot [long]) -or $Receipt.aliases -ne $aliases -or
        ($Receipt.probes -isnot [int] -and $Receipt.probes -isnot [long]) -or $Receipt.probes -ne $probes){
        throw 'winget install evidence is stale, filtered or incomplete.'
    }
    return $true
}

Export-ModuleMember -Function Invoke-CiOwnedWingetInstall, Test-CiWingetInstallReceipt
