# Data-only snapshot seam. Producer build provenance and consumer/linker admission remain owned by adapters.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SourceInputs.psm1')
$script:storage=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkCache.psm1') -PassThru

function Assert-CiLocalSnapshotSource {
    param([Collections.IDictionary]$Identity)
    $source=$Identity.producerRoot
    if((Resolve-CiCommit $source HEAD) -cne $Identity.inputs.sourceCommit -or
        (Get-CiCheckoutContentIdentity $source) -cne $Identity.inputs.sourceBytes){throw 'Local SDK snapshot producer changed; capture/build a new candidate.'}
}

function Assert-CiLocalSnapshotBindings {
    param([Collections.IDictionary]$Identity,[object[]]$Files)
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($file in $Files){[void]$names.Add($file.path)}
    foreach($role in $Identity.bindings.Keys){
        foreach($path in $Identity.bindings[$role]){if(-not $names.Contains($path)){throw "Local SDK snapshot omits its declared $role input: $path"}}
    }
}

function Get-CiLocalSdkSnapshotKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Identity)
    return & $script:storage {param($i) Get-CiStoredSdkKey $i -LocalSnapshot} $Identity
}

function Publish-CiLocalSdkSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][Collections.IDictionary]$Identity,
        [Parameter(Mandatory)][string]$PayloadRoot)
    $identityState=& $script:storage {param($i) ConvertTo-CiStoredSdkIdentity $i -LocalSnapshot} $Identity
    Assert-CiLocalSnapshotSource $identityState
    $files=@(& $script:storage {param($p) Get-CiSdkPayloadFiles $p} $PayloadRoot)
    Assert-CiLocalSnapshotBindings $identityState $files
    $key=Get-CiLocalSdkSnapshotKey $identityState
    $manifest=[ordered]@{schemaVersion=1;role='LocalUnpinnedSdkSnapshot';key=$key;identity=$identityState;files=$files}
    $entry=& $script:storage {param($s,$i,$p,$f,$m)
        Publish-CiSdkEntryData $s $i $p $f $m -LocalSnapshot
    } $StoreRoot $identityState $PayloadRoot $files ($manifest|ConvertTo-Json -Depth 14)
    # Even an existing immutable entry cannot authorize a source mutation during this acquisition.
    Assert-CiLocalSnapshotSource $identityState
    return $entry
}

function Open-CiLocalSdkSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][Collections.IDictionary]$Identity,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256)
    $identityState=& $script:storage {param($i) ConvertTo-CiStoredSdkIdentity $i -LocalSnapshot} $Identity
    Assert-CiLocalSnapshotSource $identityState
    $key=Get-CiLocalSdkSnapshotKey $identityState
    $entry=& $script:storage {param($s,$i,$k,$h)
        $root=Read-CiSdkStore $s
        $lease=Enter-CiSdkEntryLock $root $k
        try{
            $data=Read-CiSdkEntryData $root $k $i $h -LocalSnapshot
            if(-not $data){$lease.Dispose();return $null}
            return [pscustomobject]@{Store=$root;Key=$k;Identity=$i;Payload=$data.Payload;Manifest=$data.Manifest;ManifestSha256=$h;Lease=$lease;Closed=$false}
        }catch{$lease.Dispose();throw}
    } $StoreRoot $identityState $key $ManifestSha256
    if($null -eq $entry){return $null}
    try{
        Assert-CiLocalSnapshotBindings $identityState @($entry.Manifest.files)
        Assert-CiLocalSnapshotSource $identityState
        return $entry
    }catch{$entry.Lease.Dispose();throw}
}

function Close-CiLocalSdkSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Snapshot)
    if($Snapshot.Closed){throw 'Local SDK snapshot reader is already closed.'}
    try{
        Assert-CiLocalSnapshotSource $Snapshot.Identity
        $null=& $script:storage {param($e)
            if(-not(Read-CiSdkEntryData $e.Store $e.Key $e.Identity $e.ManifestSha256 -LocalSnapshot)){throw 'Local SDK snapshot disappeared during use.'}
        } $Snapshot
    }finally{$Snapshot.Lease.Dispose();$Snapshot.Closed=$true}
}

Export-ModuleMember -Function Get-CiLocalSdkSnapshotKey,Publish-CiLocalSdkSnapshot,Open-CiLocalSdkSnapshot,Close-CiLocalSdkSnapshot
