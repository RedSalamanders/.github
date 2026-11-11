# Independently frozen local descriptor/data leases only. No producer code is imported or executed.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.SourceInputs.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.LocalSdkSnapshot.psm1')

function Assert-CiLocalDescriptorPlainPath {
    param([string]$Path)
    if(-not [IO.Path]::IsPathFullyQualified($Path)){throw 'A local SDK descriptor requires an absolute path.'}
    $full=[IO.Path]::GetFullPath($Path)
    if($full.TrimEnd('\','/') -ceq [IO.Path]::GetPathRoot($full).TrimEnd('\','/')){throw 'Local SDK data cannot name a drive root.'}
    # Reuse the canonical no-follow guard across the complete ancestor chain, for reading only.
    return Assert-CiContainedPath -Root ([IO.Path]::GetPathRoot($full)) -Path $full
}

function Read-CiLocalDescriptorBytes {
    param([string]$Path)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if($stream.Length -lt 1 -or $stream.Length -gt 8MB){throw 'Empty or oversized local SDK descriptor.'}
        $bytes=[byte[]]::new([int]$stream.Length)
        $offset=0
        while($offset -lt $bytes.Length){
            $read=$stream.Read($bytes,$offset,$bytes.Length-$offset)
            if($read -eq 0){throw 'Local SDK descriptor was truncated while reading.'}
            $offset+=$read
        }
        if($stream.ReadByte() -ne -1){throw 'Local SDK descriptor grew while reading.'}
        return ,$bytes
    }finally{$stream.Dispose()}
}

function Read-CiLocalSdkSnapshotDescriptor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Descriptor,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedDescriptorSha256)
    $path=Assert-CiLocalDescriptorPlainPath $Descriptor
    $bytes=Read-CiLocalDescriptorBytes $path
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    if($hash -cne $ExpectedDescriptorSha256){throw 'Local SDK descriptor changed after its independent freeze.'}
    $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    if(-not(Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '../../Schemas/local-sdk-snapshot-descriptor.schema.json') -ErrorAction Stop)){throw 'Invalid local SDK descriptor.'}
    $record=$json|ConvertFrom-Json -AsHashtable
    $toolingRoot=Assert-CiLocalDescriptorPlainPath $record.toolingBootstrap.root
    [void](Assert-CiContainedPath (Join-Path $toolingRoot '.build') $path)
    [void](Assert-CiLocalDescriptorPlainPath $record.storeRoot)
    [void](Assert-CiContainedPath (Join-Path $toolingRoot '.build') $record.storeRoot)
    if((Get-CiLocalSdkSnapshotKey $record.identity) -cne $record.key){throw 'Local SDK descriptor input key changed.'}
    $project=Read-CiProject $toolingRoot
    if($project.repository -cne 'RedSalamanders/DxUi' -or $project.kind -cne 'sdk' -or
        (Resolve-CiCommit $toolingRoot HEAD) -cne $record.producerTooling.commit -or
        (Get-CiCheckoutContentIdentity $toolingRoot) -cne $record.toolingBootstrap.sourceBytes -or
        (Get-CiPinnedEngineInputsIdentity -Root $toolingRoot -EngineRoot (Join-Path $toolingRoot '.ci-engine')) -cne $record.toolingBootstrap.engineInputsIdentity){
        throw 'Local SDK producer tooling or its actual pinned engine changed before import.'
    }
    return [pscustomobject]@{Path=$path;Sha256=$hash;Record=$record;Role='LocalUnpinnedSdkSnapshotDescriptor'}
}

function Open-CiLocalSdkSnapshotDescriptor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Descriptor,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedDescriptorSha256)
    $parsed=Read-CiLocalSdkSnapshotDescriptor $Descriptor $ExpectedDescriptorSha256
    $record=$parsed.Record
    $snapshot=Open-CiLocalSdkSnapshot $record.storeRoot $record.identity $record.manifestSha256
    if($null -eq $snapshot){return $null}
    try{
        $null=Read-CiLocalSdkSnapshotDescriptor $Descriptor $ExpectedDescriptorSha256
        return [pscustomobject]@{Path=$parsed.Path;Sha256=$parsed.Sha256;Record=$record;Snapshot=$snapshot;Closed=$false;Role='LocalUnpinnedSdkSnapshotDescriptorLease'}
    }catch{
        $failure=$_
        try{Close-CiLocalSdkSnapshot $snapshot}catch{Write-Warning ('Local snapshot close also failed: '+$_.Exception.Message)}
        throw $failure
    }
}

function Close-CiLocalSdkSnapshotDescriptor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Handle)
    if($Handle.Closed){throw 'Local SDK descriptor reader is already closed.'}
    $failure=$null
    try{$null=Read-CiLocalSdkSnapshotDescriptor $Handle.Path $Handle.Sha256}catch{$failure=$_}
    try{Close-CiLocalSdkSnapshot $Handle.Snapshot}
    catch{if($null -eq $failure){$failure=$_}else{Write-Warning ('Local snapshot close also failed: '+$_.Exception.Message)}}
    finally{$Handle.Closed=$true}
    if($null -ne $failure){throw $failure}
}

Export-ModuleMember -Function Read-CiLocalSdkSnapshotDescriptor,Open-CiLocalSdkSnapshotDescriptor,Close-CiLocalSdkSnapshotDescriptor
