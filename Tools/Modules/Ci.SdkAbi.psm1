# Portable byte references only. This module grants no SDK admission or product verdict.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')

function Assert-CiSdkAbiPlainPath {
    param([string]$Path)
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){
        if([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint){throw 'Portable SDK ABI references refuse reparse paths.'}
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if($parent -ceq $cursor){break}
        $cursor=$parent
    }
}

function Get-CiPortableSdkFileReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Roots)
    if($Roots.Count -lt 1 -or $Roots.Count -gt 32){throw 'A bounded explicit SDK ABI root inventory is required.'}
    $roles=[string[]]@($Roots.Keys);[Array]::Sort($roles,[StringComparer]::Ordinal)
    $seenRoles=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $rows=[Collections.Generic.List[object]]::new();$totalBytes=0L
    foreach($role in $roles){
        if($role -cnotmatch '^[A-Za-z][A-Za-z0-9.-]{0,63}$' -or -not $seenRoles.Add($role)){throw 'SDK ABI root roles must be unique portable names.'}
        $requested=[string]$Roots[$role]
        if(-not [IO.Path]::IsPathFullyQualified($requested)){throw 'SDK ABI roots must be explicit absolute paths.'}
        $absolute=[IO.Path]::GetFullPath($requested)
        if($absolute.TrimEnd('\','/') -ceq [IO.Path]::GetPathRoot($absolute).TrimEnd('\','/')){throw 'A drive root is not a selected SDK ABI tree.'}
        $root=$absolute.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        if(-not [IO.Directory]::Exists($root)){throw "A required SDK ABI reference root is missing: $role."}
        Assert-CiSdkAbiPlainPath $root
        $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
        $files=[Collections.Generic.SortedDictionary[string,string]]::new([StringComparer]::Ordinal)
        $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        while($pending.Count){
            $directory=$pending.Pop()
            foreach($path in [IO.Directory]::EnumerateFileSystemEntries($directory)){
                $attributes=[IO.File]::GetAttributes($path)
                if($attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Portable SDK ABI references refuse links without traversing their targets.'}
                $relative=[IO.Path]::GetRelativePath($root,$path).Replace('\','/')
                if(-not $names.Add($relative)){throw 'SDK ABI reference contains case-colliding paths.'}
                if($names.Count -gt 200000){throw 'SDK ABI reference exceeds its directory/file bound.'}
                if($attributes -band [IO.FileAttributes]::Directory){$pending.Push($path);continue}
                if($files.Count -ge 200000){throw 'SDK ABI reference exceeds its file bound.'}
                $files.Add($relative,$path)
            }
        }
        if(-not $files.Count){throw 'A required SDK ABI reference tree is empty.'}
        foreach($pair in $files.GetEnumerator()){
            # Hold the exact file against writes/replacement while hashing. Metadata is
            # not a byte identity; equal size and timestamps never bypass this read.
            $stream=[IO.File]::Open($pair.Value,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try{
                $length=$stream.Length;$totalBytes+=$length
                if($totalBytes -gt 64GB -or $rows.Count -ge 200000){throw 'SDK ABI reference exceeds its total byte/file bound.'}
                $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()
                if($stream.Length -ne $length){throw 'SDK ABI reference changed during hashing.'}
                $rows.Add([ordered]@{role=$role;path=$pair.Key;bytes=$length;sha256=$hash})
            }finally{$stream.Dispose()}
        }
    }
    $catalog=$rows.ToArray()
    return [ordered]@{schemaVersion=2;role='PortableSdkFileReference';files=$catalog;
        digest=(Get-CiSha256 ('portable-sdk-files-v2'+"`n"+($catalog|ConvertTo-Json -Depth 5 -Compress)))}
}

function Assert-CiSdkAbiCompilerEnvironment {
    if($env:CI_NATIVE_BUILDS_DISABLED -eq 'true'){throw 'Real SDK ABI toolchain evaluation is forbidden in compiler-free PR checks.'}
    foreach($name in @('CL','_CL_','INCLUDE','LIB','LIBPATH')){
        if([Environment]::GetEnvironmentVariable($name)){throw "Portable SDK ABI reference does not support the $name compiler environment override."}
    }
}

function Get-CiSdkAbiReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ToolingRoot,[Parameter(Mandatory)][string]$MSBuildPath,[Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,[switch]$PassThruBinding)
    if(-not $IsWindows){throw 'The real SDK ABI reference requires the selected Windows native toolchain.'}
    Assert-CiSdkAbiCompilerEnvironment
    if([IO.Path]::GetFileName($MSBuildPath) -ine 'MSBuild.exe'){throw 'The SDK ABI reference requires the actual selected MSBuild executable.'}
    foreach($path in @($MSBuildPath,$ProjectPath)){
        if(-not [IO.Path]::IsPathFullyQualified($path) -or -not [IO.File]::Exists($path)){throw 'SDK ABI evaluation requires explicit existing reviewed project and MSBuild paths.'}
        Assert-CiSdkAbiPlainPath $path
    }
    $required=@('PlatformToolset','VCToolsInstallDir','VCToolsVersion','WindowsSdkDir','WindowsTargetPlatformVersion',
        'PreferredToolArchitecture','VCTargetsPath','VCToolArchitecture','WindowsSDKToolArchitecture')
    $names=$required+@('CLToolExe','CLToolPath','CLToolArchitecture','LinkToolExe','LinkToolPath','LinkToolArchitecture',
        'LibToolExe','LibToolPath','LibToolArchitecture','FxCompileToolArchitecture','FXCToolPath','MultiProcFXC','FxCompileToolExe')
    $evaluation=Invoke-CiProcess -FilePath $MSBuildPath -Arguments @($ProjectPath,'/nologo','/p:Configuration=Release',"/p:Platform=$Platform",('-getProperty:'+($names -join ','))) `
        -WorkingDirectory ([IO.Path]::GetDirectoryName($ProjectPath)) -TimeoutSeconds 120
    $properties=($evaluation.stdout|ConvertFrom-Json -AsHashtable).Properties
    foreach($name in $required){if(-not $properties.Contains($name) -or [string]::IsNullOrWhiteSpace([string]$properties[$name])){throw "SDK ABI evaluation is missing $name."}}
    $hostTool=[string]$properties.PreferredToolArchitecture
    if($hostTool -cnotin @('x86','x64','arm64') -or $properties.VCToolsVersion -cnotmatch '^\d+\.\d+\.\d+$' -or
        $properties.WindowsTargetPlatformVersion -cnotmatch '^\d+\.\d+\.\d+\.\d+$'){throw 'Unsupported SDK ABI compiler/SDK selection.'}
    $sdkVersion=[string]$properties.WindowsTargetPlatformVersion
    # Reuse the reviewed producer's complete tool-selection guard instead of
    # reimplementing MSBuild's Native32Bit/Native64Bit/NativeARM64 mapping.
    # Callers authenticate this tooling snapshot before importing any of its code.
    $policyPath=Join-Path $ToolingRoot 'Tools/PerformancePolicy.psm1'
    Assert-CiSdkAbiPlainPath $policyPath
    $policy=Import-Module $policyPath -PassThru
    $selected=& $policy {param($p,$a) Get-PerformanceResolvedToolPaths -Properties $p -Platform $a} $properties $Platform
    $roots=[ordered]@{
        MSBuild=[IO.Path]::GetDirectoryName($MSBuildPath)
        VCTargets=[string]$properties.VCTargetsPath
        MSVCHeaders=(Join-Path $properties.VCToolsInstallDir 'include')
        MSVCLibraries=(Join-Path $properties.VCToolsInstallDir ('lib/'+$Platform))
        MSVCTools=[IO.Path]::GetDirectoryName($selected.CL)
        WindowsHeaders=(Join-Path $properties.WindowsSdkDir ('Include/'+$sdkVersion))
        WindowsLibraries=(Join-Path $properties.WindowsSdkDir ("Lib/$sdkVersion/um/"+$Platform))
        CRuntimeLibraries=(Join-Path $properties.WindowsSdkDir ("Lib/$sdkVersion/ucrt/"+$Platform))
        WindowsTools=[IO.Path]::GetDirectoryName($selected.FXC)
    }
    $compiler=[ordered]@{platform=$Platform;configuration='Release';toolset=[string]$properties.PlatformToolset;
        vcToolsVersion=[string]$properties.VCToolsVersion;windowsSdkVersion=$sdkVersion;preferredToolArchitecture=$hostTool;
        vcToolArchitecture=[string]$properties.VCToolArchitecture;windowsSdkToolArchitecture=[string]$properties.WindowsSDKToolArchitecture}
    $files=Get-CiPortableSdkFileReference -Roots $roots
    $reference=New-CiSdkAbiReference -Compiler $compiler -FileReference $files
    if($PassThruBinding){return [pscustomobject]@{Reference=$reference;Properties=$properties;SelectedTools=$selected;Roots=$roots}}
    return $reference
}

function New-CiSdkAbiReference {
    param([Collections.IDictionary]$Compiler,[Collections.IDictionary]$FileReference)
    $reference=[ordered]@{schemaVersion=2;role='PortableSdkToolchainReference';compiler=$Compiler;fileReference=$FileReference;
        digest=(Get-CiSha256 ('portable-sdk-toolchain-v2'+"`n"+($Compiler|ConvertTo-Json -Compress)+"`n"+$FileReference.digest))}
    Assert-CiSdkAbiReference $reference
    return $reference
}

function Assert-CiSdkAbiReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Reference)
    $json=$Reference|ConvertTo-Json -Depth 8 -Compress
    if($json.Length -gt 64MB -or -not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/portable-sdk-toolchain-reference.schema.json'))){throw 'Invalid portable SDK toolchain reference schema.'}
    $compiler=[ordered]@{}
    foreach($name in @('platform','configuration','toolset','vcToolsVersion','windowsSdkVersion','preferredToolArchitecture','vcToolArchitecture','windowsSdkToolArchitecture')){$compiler[$name]=$Reference.compiler[$name]}
    $architectures=@{Native32Bit='x86';Native64Bit='x64';NativeARM64='arm64'}
    if($architectures[$compiler.vcToolArchitecture] -cne $compiler.preferredToolArchitecture){throw 'Inconsistent portable SDK compiler host selection.'}
    # Producer and consumer can legitimately load different pinned storage modules
    # with the same name. Retain the exact implementation, never a name-only list.
    $paths=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkCache.psm1') -PassThru
    $rows=[Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $roles=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$totalBytes=0L
    foreach($file in $Reference.fileReference.files){
        & $paths {param($p) Test-CiSdkRelativePath $p} $file.path
        $key=$file.role+[char]0+$file.path
        if(-not $names.Add($key)){throw 'Duplicate portable SDK reference path.'}
        [void]$roles.Add($file.role);$totalBytes+=$file.bytes
        if($totalBytes -gt 64GB){throw 'Portable SDK reference exceeds its total byte bound.'}
        $rows.Add($key,[ordered]@{role=$file.role;path=$file.path;bytes=$file.bytes;sha256=$file.sha256})
    }
    if($roles.Count -ne 9){throw 'Portable SDK reference omits a required tool/header/library role.'}
    $filesDigest=Get-CiSha256 ('portable-sdk-files-v2'+"`n"+(@($rows.Values)|ConvertTo-Json -Depth 5 -Compress))
    $digest=Get-CiSha256 ('portable-sdk-toolchain-v2'+"`n"+($compiler|ConvertTo-Json -Compress)+"`n"+$filesDigest)
    if($filesDigest -cne $Reference.fileReference.digest -or $digest -cne $Reference.digest){throw 'Portable SDK reference content differs from its digest.'}
}

Export-ModuleMember -Function Get-CiPortableSdkFileReference,Get-CiSdkAbiReference,Assert-CiSdkAbiReference
