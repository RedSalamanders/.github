# Integrity/ownership for immutable dependency bytes only. This module grants no test or publication verdict.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1') -ErrorAction Stop

function ConvertTo-CiSdkIdentity {
    param([Collections.IDictionary]$Identity)
    $json=$Identity|ConvertTo-Json -Depth 10 -Compress
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/sdk-cache-identity.schema.json') -ErrorAction Stop)){throw 'Invalid SDK cache identity.'}
    $ordered=[ordered]@{}
    foreach($name in @('schemaVersion','role','sourceRepository','sourceCommit','sourceBytes','apiRevision','platform','configuration','runtimeFamily',
        'annotationPolicy','languageStandard','optimizationPolicy','toolchainIdentity','compilerProfileIdentity','dependencyIdentity','integrationPolicyIdentity','environmentIdentity')){
        $ordered[$name]=$Identity[$name]
    }
    return $ordered
}

function Get-CiSdkCacheKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Identity)
    $ordered=ConvertTo-CiSdkIdentity $Identity
    return Get-CiSha256 ('sdk-cache-inputs-v1'+"`n"+($ordered|ConvertTo-Json -Depth 10 -Compress))
}

# Separate data-only role for local dirty-source snapshots. Public pinned SDK entrypoints
# never select this branch; their strict v1 identity/key/schema remain unchanged.
function ConvertTo-CiStoredSdkIdentity {
    param([Collections.IDictionary]$Identity,[switch]$LocalSnapshot)
    if(-not $LocalSnapshot){return ConvertTo-CiSdkIdentity $Identity}
    if(-not(Test-Json -Json ($Identity|ConvertTo-Json -Depth 12 -Compress) -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/local-sdk-snapshot-identity.schema.json') -ErrorAction Stop)){throw 'Invalid local SDK snapshot identity.'}
    $root=[string]$Identity.producerRoot
    if(-not [IO.Path]::IsPathFullyQualified($root) -or $root -cne [IO.Path]::GetFullPath($root).TrimEnd('\','/')){throw 'A local snapshot requires its exact absolute producer root.'}
    if([OperatingSystem]::IsWindows()){$root=$root.ToUpperInvariant()}
    $inputs=ConvertTo-CiSdkIdentity $Identity.inputs
    $bindings=[ordered]@{}
    foreach($name in @('headers','libraries','symbols','integration','licenses','buildProvenance')){
        $paths=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
        foreach($path in $Identity.bindings[$name]){Test-CiSdkRelativePath $path;if(-not $paths.Add($path)){throw 'Duplicate local SDK role binding.'}}
        $bindings[$name]=@($paths)
    }
    return [ordered]@{schemaVersion=1;role='LocalUnpinnedSdkSnapshot';producerRoot=$root;inputs=$inputs;bindings=$bindings}
}

function Get-CiStoredSdkKey {
    param([Collections.IDictionary]$Identity,[switch]$LocalSnapshot)
    if(-not $LocalSnapshot){return Get-CiSdkCacheKey $Identity}
    $ordered=ConvertTo-CiStoredSdkIdentity $Identity -LocalSnapshot
    return Get-CiSha256 ('local-unpinned-sdk-snapshot-v1'+"`n"+($ordered|ConvertTo-Json -Depth 12 -Compress))
}

function Initialize-CiSdkStore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$StoreRoot)
    $repository=[IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\','/')
    if($repository -eq [IO.Path]::GetPathRoot($repository).TrimEnd('\','/') -or -not(Test-Path -LiteralPath (Join-Path $repository '.git'))){throw 'SDK store initialization requires a repository, never a drive root.'}
    $store=Assert-CiContainedPath (Join-Path $repository '.build') $StoreRoot
    $marker=Join-Path $store 'store.json'
    if(Test-Path -LiteralPath $marker){[void](Read-CiSdkStore $store)}else{
        if((Test-Path -LiteralPath $store) -and @(Get-ChildItem -LiteralPath $store -Force).Count){throw 'Refusing to initialize a nonempty unowned SDK store.'}
        [void][IO.Directory]::CreateDirectory($store)
        $stream=[IO.File]::Open($marker,'CreateNew','Write','None')
        try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(([ordered]@{schemaVersion=1;kind='RedSalamanders.DependencySdkStore';owner=$repository}|ConvertTo-Json -Compress));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    }
    # Initialization can resume after interruption; validate each existing child before creating it.
    foreach($name in @('entries','locks','staging','quarantine')){[void][IO.Directory]::CreateDirectory((Assert-CiContainedPath $store (Join-Path $store $name)))}
}

function Read-CiSdkStore {
    param([string]$StoreRoot)
    $root=[IO.Path]::GetFullPath($StoreRoot).TrimEnd('\','/')
    if($root -eq [IO.Path]::GetPathRoot($root).TrimEnd('\','/')){throw 'SDK store cannot be a drive root.'}
    $marker=Assert-CiContainedPath $root (Join-Path $root 'store.json')
    if(-not(Test-Path -LiteralPath $marker -PathType Leaf) -or (Get-Item -LiteralPath $marker).Length -gt 4096){throw 'Missing or oversized SDK store ownership marker.'}
    $owner=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json -AsHashtable
    if($owner.Count -ne 3 -or $owner.schemaVersion -ne 1 -or $owner.kind -cne 'RedSalamanders.DependencySdkStore'){throw 'Invalid SDK store ownership marker.'}
    [void](Assert-CiContainedPath (Join-Path $owner.owner '.build') $root)
    return $root
}

function Test-CiSdkRelativePath {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 512 -or $Path -match '[\x00-\x1f<>:"\\|?*]' -or $Path.StartsWith('/')){throw 'Invalid SDK payload path.'}
    foreach($part in $Path.Split('/')){
        if(-not $part -or $part -in @('.','..') -or $part -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'Unsafe SDK payload path component.'}
    }
}

function Get-CiSdkPayloadFiles {
    param([string]$Root)
    $files=[Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [long]$total=0
    foreach($item in Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse SDK payloads are unsupported.'}
        if($item.PSIsContainer){continue}
        $relative=[IO.Path]::GetRelativePath($Root,$item.FullName).Replace('\','/')
        Test-CiSdkRelativePath $relative
        [void](Assert-CiContainedPath $Root $item.FullName)
        if(-not $names.Add($relative)){throw 'SDK payload paths collide under Windows casing.'}
        $total+=$item.Length
        if($total -gt 1GB -or $files.Count -ge 4096){throw 'SDK payload exceeds the v1 bounded-store limit.'}
        $files.Add($relative,[ordered]@{path=$relative;length=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()})
    }
    if(-not $files.Count){throw 'Empty SDK payload.'}
    return @($files.Values)
}

function Enter-CiSdkEntryLock {
    param([string]$Root,[string]$Key,[switch]$Writer)
    $path=Assert-CiContainedPath $Root (Join-Path $Root ('locks/'+$Key.Substring(0,16)+'.lock'))
    if(-not(Test-Path -LiteralPath $path)){
        try{$seed=[IO.File]::Open($path,'CreateNew','ReadWrite','ReadWrite');$seed.Dispose()}
        catch [IO.IOException]{if(-not(Test-Path -LiteralPath $path)){throw}}
    }
    return [IO.File]::Open($path,'Open',$(if($Writer){[IO.FileAccess]::ReadWrite}else{[IO.FileAccess]::Read}),$(if($Writer){[IO.FileShare]::None}else{[IO.FileShare]::Read}))
}

function Get-CiSdkEntryPath {
    param([string]$Root,[string]$Key,[string]$ManifestSha256)
    if($ManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'An independently retained SDK manifest digest is required.'}
    $input=Assert-CiContainedPath $Root (Join-Path $Root ('entries/'+$Key.Substring(0,16)))
    if(Test-Path -LiteralPath $input){
        $marker=Assert-CiContainedPath $Root (Join-Path $input 'input-key.txt')
        if(-not(Test-Path -LiteralPath $marker -PathType Leaf) -or (Get-Item -LiteralPath $marker).Length -ne 64 -or [IO.File]::ReadAllText($marker) -cne $Key){throw 'SDK shortened input locator has a different complete identity.'}
    }
    return Assert-CiContainedPath $Root (Join-Path $input $ManifestSha256.Substring(0,16))
}

function Read-CiSdkEntryData {
    param([string]$Root,[string]$Key,[Collections.IDictionary]$Identity,[string]$ManifestSha256,[switch]$LocalSnapshot)
    $entry=Get-CiSdkEntryPath $Root $Key $ManifestSha256
    if(-not(Test-Path -LiteralPath $entry -PathType Container)){return $null}
    $path=Assert-CiContainedPath $Root (Join-Path $entry 'entry.json')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -gt 8MB){throw 'Incomplete SDK cache entry.'}
    if((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $ManifestSha256){throw 'SDK manifest differs from its independently retained digest.'}
    $json=Get-Content -LiteralPath $path -Raw
    $schema=if($LocalSnapshot){'local-sdk-snapshot-entry.schema.json'}else{'sdk-cache-entry.schema.json'}
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot "../../Schemas/$schema") -ErrorAction Stop)){throw 'Invalid SDK cache entry.'}
    $manifest=$json|ConvertFrom-Json -AsHashtable
    if($manifest.key -cne $Key -or (Get-CiStoredSdkKey $manifest.identity -LocalSnapshot:$LocalSnapshot) -cne $Key -or (Get-CiStoredSdkKey $Identity -LocalSnapshot:$LocalSnapshot) -cne $Key){throw 'SDK shortened locator has a different complete identity.'}
    $actual=@(Get-CiSdkPayloadFiles (Assert-CiContainedPath $Root (Join-Path $entry 'payload')))
    if(($actual|ConvertTo-Json -Depth 5 -Compress) -cne ($manifest.files|ConvertTo-Json -Depth 5 -Compress)){throw 'SDK payload inventory or bytes changed.'}
    return [pscustomobject]@{Path=$entry;Payload=(Join-Path $entry 'payload');Manifest=$manifest;ManifestSha256=$ManifestSha256;Key=$Key}
}

function Publish-CiSdkCacheEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][Collections.IDictionary]$Identity,[Parameter(Mandatory)][string]$PayloadRoot)
    $root=Read-CiSdkStore $StoreRoot
    $key=Get-CiSdkCacheKey $Identity
    $files=@(Get-CiSdkPayloadFiles $PayloadRoot)
    $manifest=[ordered]@{schemaVersion=1;role='DependencySdkInputs';key=$key;identity=(ConvertTo-CiSdkIdentity $Identity);files=$files}
    $manifestJson=$manifest|ConvertTo-Json -Depth 10
    return Publish-CiSdkEntryData -StoreRoot $root -Identity $Identity -PayloadRoot $PayloadRoot -Files $files -ManifestJson $manifestJson
}

function Import-CiSdkCacheEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][Collections.IDictionary]$Identity,
        [Parameter(Mandatory)][string]$EntryRoot,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256)
    # Authenticate the envelope independently before calling. This primitive grants only byte integrity.
    $path=Assert-CiContainedPath $EntryRoot (Join-Path $EntryRoot 'entry.json')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item $path).Length -gt 8MB){throw 'Missing or oversized imported SDK manifest.'}
    $bytes=[IO.File]::ReadAllBytes($path)
    if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant() -cne $ManifestSha256){throw 'Imported SDK manifest differs from the independent envelope.'}
    $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/sdk-cache-entry.schema.json'))){throw 'Invalid imported SDK manifest.'}
    $manifest=$json|ConvertFrom-Json -AsHashtable
    $key=Get-CiSdkCacheKey $Identity
    if($manifest.key -cne $key -or (Get-CiSdkCacheKey $manifest.identity) -cne $key){throw 'Imported SDK inputs differ from the independently evaluated recipe.'}
    $payload=Assert-CiContainedPath $EntryRoot (Join-Path $EntryRoot 'payload')
    $files=@(Get-CiSdkPayloadFiles $payload)
    if(($files|ConvertTo-Json -Depth 5 -Compress) -cne ($manifest.files|ConvertTo-Json -Depth 5 -Compress)){throw 'Imported SDK payload inventory or bytes changed.'}
    return Publish-CiSdkEntryData -StoreRoot $StoreRoot -Identity $Identity -PayloadRoot $payload -Files $files -ManifestJson $json
}

function Publish-CiSdkEntryData {
    param([string]$StoreRoot,[Collections.IDictionary]$Identity,[string]$PayloadRoot,[object[]]$Files,[string]$ManifestJson,[switch]$LocalSnapshot)
    $root=Read-CiSdkStore $StoreRoot
    $key=Get-CiStoredSdkKey $Identity -LocalSnapshot:$LocalSnapshot
    $manifestSha=Get-CiSha256 $manifestJson
    $lease=Enter-CiSdkEntryLock $root $key -Writer
    try{
        $existing=Read-CiSdkEntryData $root $key $Identity $manifestSha -LocalSnapshot:$LocalSnapshot
        if($existing){return $existing}
        $staging=Assert-CiContainedPath $root (Join-Path $root ('staging/'+$key.Substring(0,16)+'-'+[guid]::NewGuid().ToString('N')))
        $payload=Join-Path $staging 'payload'
        [void][IO.Directory]::CreateDirectory($payload)
        foreach($file in $files){
            $source=Assert-CiContainedPath $PayloadRoot (Join-Path $PayloadRoot $file.path)
            $target=Assert-CiContainedPath $root (Join-Path $payload $file.path)
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
            [IO.File]::Copy($source,$target,$false)
        }
        $copied=@(Get-CiSdkPayloadFiles $payload)
        $after=@(Get-CiSdkPayloadFiles $PayloadRoot)
        $catalog=$files|ConvertTo-Json -Depth 5 -Compress
        if(($copied|ConvertTo-Json -Depth 5 -Compress) -cne $catalog -or ($after|ConvertTo-Json -Depth 5 -Compress) -cne $catalog){throw 'SDK source changed while publishing; incomplete staging is preserved.'}
        [IO.File]::WriteAllText((Join-Path $staging 'entry.json'),$manifestJson,[Text.UTF8Encoding]::new($false))
        $input=Assert-CiContainedPath $root (Join-Path $root ('entries/'+$key.Substring(0,16)))
        if(-not(Test-Path -LiteralPath $input)){
            [void][IO.Directory]::CreateDirectory($input)
            [IO.File]::WriteAllText((Join-Path $input 'input-key.txt'),$key,[Text.UTF8Encoding]::new($false))
        }
        $destination=Get-CiSdkEntryPath $root $key $manifestSha
        [void](Assert-CiContainedPath $root $staging)
        [IO.Directory]::Move($staging,$destination)
        return Read-CiSdkEntryData $root $key $Identity $manifestSha -LocalSnapshot:$LocalSnapshot
    }finally{$lease.Dispose()}
}

function Open-CiSdkCacheEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][Collections.IDictionary]$Identity,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256)
    $root=Read-CiSdkStore $StoreRoot;$key=Get-CiSdkCacheKey $Identity
    $lease=Enter-CiSdkEntryLock $root $key
    try{
        $entry=Read-CiSdkEntryData $root $key $Identity $ManifestSha256
        if(-not $entry){$lease.Dispose();return $null}
        return [pscustomobject]@{Store=$root;Key=$key;Identity=$Identity;Payload=$entry.Payload;Manifest=$entry.Manifest;ManifestSha256=$ManifestSha256;Lease=$lease}
    }catch{$lease.Dispose();throw}
}

function Close-CiSdkCacheEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Entry)
    try{if(-not(Read-CiSdkEntryData $Entry.Store $Entry.Key $Entry.Identity $Entry.ManifestSha256)){throw 'SDK entry disappeared during reader use.'}}finally{$Entry.Lease.Dispose()}
}

function Move-CiSdkCacheEntryToQuarantine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][Collections.IDictionary]$Identity,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256)
    $root=Read-CiSdkStore $StoreRoot;$key=Get-CiSdkCacheKey $Identity
    $lease=Enter-CiSdkEntryLock $root $key -Writer
    try{
        $source=Get-CiSdkEntryPath $root $key $ManifestSha256
        if(-not(Test-Path -LiteralPath $source -PathType Container)){return}
        # A corrupt entry is retained atomically, never recursively deleted or followed.
        $target=Assert-CiContainedPath $root (Join-Path $root ('quarantine/'+$key.Substring(0,16)+'-'+[guid]::NewGuid().ToString('N')))
        [IO.Directory]::Move($source,$target)
        return $target
    }finally{$lease.Dispose()}
}

Export-ModuleMember -Function Get-CiSdkCacheKey,Initialize-CiSdkStore,Publish-CiSdkCacheEntry,Import-CiSdkCacheEntry,Open-CiSdkCacheEntry,Close-CiSdkCacheEntry,Move-CiSdkCacheEntryToQuarantine
