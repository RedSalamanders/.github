# Candidate archives contain arbitrary product profiles and diagnostics. Unlike
# dependency SDK imports, this reader never extracts files, loads code or initializes
# a dependency store. Held, bounded streams preserve the server-bound archive bytes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Open-CiCandidateArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][Collections.IDictionary]$Artifact)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $zip=$null
    try{
        if($Artifact.archiveSha256 -cnotmatch '^[a-f0-9]{64}$' -or $Artifact.archiveBytes -lt 1 -or
            $Artifact.archiveBytes -gt 4GB -or $stream.Length -ne $Artifact.archiveBytes -or
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() -cne $Artifact.archiveSha256){
            throw 'Candidate archive differs from its independently authenticated server digest or size.'
        }
        $stream.Position=0
        $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read,$true)
        if($zip.Entries.Count -lt 1 -or $zip.Entries.Count -gt 100000){throw 'Candidate archive has an invalid entry count.'}
        $entries=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $expanded=0L
        foreach($entry in $zip.Entries){
            $name=$entry.FullName.TrimEnd('/')
            if(-not $name -or $name -match '[\\:"<>|?*\x00-\x1f]' -or $name.StartsWith('/') -or
                $name -match '(^|/)\.{1,2}(/|$)|//' -or -not $names.Add($name)){
                throw 'Candidate archive has an unsafe, duplicated or case-colliding path.'
            }
            foreach($segment in $name.Split('/')){
                if($segment -match '[. ]$|^[ ]' -or $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){
                    throw 'Candidate archive has an ambiguous Windows path.'
                }
            }
            $mode=($entry.ExternalAttributes -shr 16) -band 0xF000
            if(($mode -ne 0 -and $mode -ne 0x8000 -and $mode -ne 0x4000) -or
                ($entry.ExternalAttributes -band 0x400) -or $entry.Length -lt 0){throw 'Candidate archive links and special files are refused.'}
            $expanded+=$entry.Length
            if($expanded -gt 8GB){throw 'Candidate archive expands beyond its declared bound.'}
            if(-not $entry.FullName.EndsWith('/')){$entries.Add($name,$entry)}
        }
        $files=[Collections.Generic.HashSet[string]]::new($entries.Keys,[StringComparer]::OrdinalIgnoreCase)
        foreach($name in $entries.Keys){
            $parent=$name
            while($parent.Contains('/')){
                $parent=$parent.Substring(0,$parent.LastIndexOf('/'))
                if($files.Contains($parent)){throw 'Candidate archive file is also a parent directory.'}
            }
        }
        return [pscustomobject]@{Stream=$stream;Zip=$zip;Entries=$entries;Closed=$false}
    }catch{
        if($null -ne $zip){$zip.Dispose()};$stream.Dispose();throw
    }
}

function Read-CiCandidateArchiveJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Archive,[Parameter(Mandatory)][string]$Path)
    if($Archive.Closed -or -not $Archive.Entries.ContainsKey($Path)){throw 'Original exact candidate JSON is missing or its archive is closed.'}
    $entry=$Archive.Entries[$Path]
    if($entry.Length -lt 1 -or $entry.Length -gt 64MB){throw 'Candidate JSON is empty or oversized.'}
    $stream=$entry.Open();$memory=[IO.MemoryStream]::new();$reader=$null
    try{
        $buffer=[byte[]]::new(64KB)
        while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0){
            if($memory.Length+$count -gt $entry.Length -or $memory.Length+$count -gt 64MB){throw 'Candidate JSON expands beyond its declared bound.'}
            $memory.Write($buffer,0,$count)
        }
        if($memory.Length -ne $entry.Length){throw 'Candidate JSON length differs from its archive catalog.'}
        $memory.Position=0;$reader=[IO.StreamReader]::new($memory,[Text.UTF8Encoding]::new($false,$true),$true)
        $json=$reader.ReadToEnd()
        # Reject duplicate JSON properties rather than letting the last value hide
        # another identity. JsonDocument preserves the original property catalog.
        $document=[Text.Json.JsonDocument]::Parse($json)
        try{
            $pending=[Collections.Generic.Stack[Text.Json.JsonElement]]::new();$pending.Push($document.RootElement)
            while($pending.Count){
                $node=$pending.Pop()
                if($node.ValueKind -eq [Text.Json.JsonValueKind]::Object){
                    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                    foreach($property in $node.EnumerateObject()){
                        if(-not $names.Add($property.Name)){throw 'Candidate JSON contains duplicate or case-colliding properties.'}
                        $pending.Push($property.Value)
                    }
                }elseif($node.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($child in $node.EnumerateArray()){$pending.Push($child)}}
            }
        }finally{$document.Dispose()}
        $value=ConvertFrom-Json -InputObject $json -AsHashtable -Depth 50
        if($value -isnot [Collections.IDictionary]){throw 'Candidate JSON must be one original object.'}
        return $value
    }finally{if($null -ne $reader){$reader.Dispose()};$memory.Dispose();$stream.Dispose()}
}

function Test-CiCandidateArchiveFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Archive,[Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$Sha256)
    if($Archive.Closed -or -not $Archive.Entries.ContainsKey($Path)){throw 'Original tested profile or canonical evidence file is missing.'}
    $entry=$Archive.Entries[$Path];$stream=$entry.Open()
    $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try{
        $buffer=[byte[]]::new(1MB);$read=0L
        while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0){
            $read+=$count
            if($read -gt $entry.Length){throw 'Candidate file expands beyond its declared bound.'}
            $hash.AppendData($buffer,0,$count)
        }
        if($read -ne $entry.Length -or [Convert]::ToHexString($hash.GetHashAndReset()).ToLowerInvariant() -cne $Sha256){
            throw 'Original tested profile or canonical evidence bytes changed.'
        }
    }finally{$hash.Dispose();$stream.Dispose()}
    return $true
}

function Close-CiCandidateArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Archive)
    if(-not $Archive.Closed){try{$Archive.Zip.Dispose()}finally{$Archive.Stream.Dispose();$Archive.Closed=$true}}
}

Export-ModuleMember -Function Open-CiCandidateArchive,Read-CiCandidateArchiveJson,Test-CiCandidateArchiveFile,Close-CiCandidateArchive
