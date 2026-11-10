<#
.SYNOPSIS Tests immutable SDK byte storage and leases without compilation or SDK acceptance.
.PARAMETER TestRoot Existing marked RedSalamander.Perf root, or a hosted RUNNER_TEMP descendant.
.OUTPUTS Retained synthetic fixtures and results.json below a unique owned root.
.NOTES No product, account, publication, desktop or dependency pin changes. Fake library bytes test storage only.
.EXAMPLE ./Tests/Test-SdkCache.ps1 -TestRoot Z:/RedSalamander.Perf
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$TestRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$engine=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $engine 'Tools/Modules/Ci.SdkCache.psm1') -Force
$selected=[IO.Path]::GetFullPath($TestRoot).TrimEnd('\','/')
$hosted=$env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted' -and $env:RUNNER_TEMP
if($hosted){
    $prefix=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $selected.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Hosted SDK fixtures must remain under RUNNER_TEMP.'}
}elseif($selected -notmatch '^[A-Za-z]:[\\/]RedSalamander\.Perf$' -or
    -not(Test-Path -LiteralPath (Join-Path $selected '.red-salamander-test-root')) -or
    [IO.File]::ReadAllText((Join-Path $selected '.red-salamander-test-root')).Trim() -cne 'red-salamander.test-sandbox-root.v1'){
    throw 'SDK fixtures require the existing marked test root.'
}
if((Get-Item -LiteralPath $selected).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse test roots are unsupported.'}
$root=Join-Path $selected ('unified-ci/sdk-store-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
& git -C $root init -q
if($LASTEXITCODE){throw 'Cannot initialize owned store fixture.'}
$store=Join-Path $root '.build/sdk-cache'
$payload=Join-Path $root 'fixture-payload'
[void][IO.Directory]::CreateDirectory((Join-Path $payload 'include/DxUi'))
[void][IO.Directory]::CreateDirectory((Join-Path $payload 'lib'))
[IO.File]::WriteAllText((Join-Path $payload 'include/DxUi/Fixture.h'),'synthetic header v1')
[IO.File]::WriteAllText((Join-Path $payload 'lib/DxUi.lib'),'synthetic bytes, not a native SDK')
$identity=[ordered]@{schemaVersion=1;role='DependencySdkInputs';sourceRepository='RedSalamanders/DxUi';sourceCommit=('a'*40);sourceBytes=('b'*64);apiRevision=4;
    platform='x64';configuration='Release';runtimeFamily='MD';annotationPolicy='enabled';languageStandard='stdcpplatest';optimizationPolicy='GL-LTCG-full';
    toolchainIdentity=('c'*64);compilerProfileIdentity=('d'*64);dependencyIdentity=('e'*64);integrationPolicyIdentity=('f'*64);environmentIdentity=('0'*64)}
$results=[Collections.Generic.List[object]]::new()
function Check([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Refuses([scriptblock]$Body){$failed=$false;try{& $Body|Out-Null}catch{$failed=$true};Check $failed 'Expected refusal.'}
function Case([string]$Name,[scriptblock]$Body){try{& $Body;$results.Add(@{name=$Name;passed=$true});Write-Host "PASS $Name"}catch{$results.Add(@{name=$Name;passed=$false;error=$_.Exception.Message});Write-Host "FAIL $Name`: $($_.Exception.Message)"}}
Initialize-CiSdkStore $root $store
$published=$null
Case 'key ordering is stable and every input family invalidates' {
    $key=Get-CiSdkCacheKey $identity
    $reverse=[ordered]@{};foreach($name in @($identity.Keys)[($identity.Count-1)..0]){$reverse[$name]=$identity[$name]}
    Check ((Get-CiSdkCacheKey $reverse) -ceq $key) 'Property order changed the key.'
    foreach($name in @('sourceCommit','sourceBytes','apiRevision','platform','toolchainIdentity','compilerProfileIdentity','dependencyIdentity','integrationPolicyIdentity','environmentIdentity')){
        $changed=$identity|ConvertTo-Json|ConvertFrom-Json -AsHashtable
        $changed[$name]=switch($name){apiRevision{5};platform{'ARM64'};sourceCommit{'1'*40};default{'1'*64}}
        Check ((Get-CiSdkCacheKey $changed) -cne $key) "Identity omitted $name."
    }
    foreach($pair in @(@('configuration','Debug'),@('runtimeFamily','MT'),@('annotationPolicy','disabled'),@('role','ProductionRelease'))){
        $changed=$identity|ConvertTo-Json|ConvertFrom-Json -AsHashtable;$changed[$pair[0]]=$pair[1]
        Refuses {Get-CiSdkCacheKey $changed}
    }
}
Case 'owned initialization refuses foreign roots and nonempty data' {
    $foreign=Join-Path $root '.build/unowned';[void][IO.Directory]::CreateDirectory($foreign)
    [IO.File]::WriteAllText((Join-Path $foreign 'keep.txt'),'preserve')
    Refuses {Initialize-CiSdkStore $root $foreign}
    Refuses {Initialize-CiSdkStore $root (Join-Path $root 'outside-build')}
    Check ([IO.File]::ReadAllText((Join-Path $foreign 'keep.txt')) -ceq 'preserve') 'Initialization changed foreign bytes.'
    # Simulate interruption after the ownership marker, before an empty child was created.
    [IO.Directory]::Delete((Join-Path $store 'quarantine'))
    Initialize-CiSdkStore $root $store
    Check (Test-Path -LiteralPath (Join-Path $store 'quarantine') -PathType Container) 'Owned initialization could not resume.'
}
Case 'publish, explicit digest admission and multiple readers preserve bytes' {
    $script:published=Publish-CiSdkCacheEntry $store $identity $payload
    $again=Publish-CiSdkCacheEntry $store $identity $payload
    Check ($again.ManifestSha256 -ceq $published.ManifestSha256) 'Identical publication replaced the entry.'
    $first=Open-CiSdkCacheEntry $store $identity $published.ManifestSha256
    $second=$null
    try{
        $second=Open-CiSdkCacheEntry $store $identity $published.ManifestSha256
        Check ($null -ne $second) 'A second reader was blocked.'
        Refuses {Move-CiSdkCacheEntryToQuarantine $store $identity $published.ManifestSha256}
        Check ([IO.File]::ReadAllText((Join-Path $first.Payload 'lib/DxUi.lib')) -ceq 'synthetic bytes, not a native SDK') 'Payload bytes changed.'
    }finally{if($second){Close-CiSdkCacheEntry $second};Close-CiSdkCacheEntry $first}
    $wrong=$published.ManifestSha256.Substring(0,16)+('1'*48)
    Refuses {Open-CiSdkCacheEntry $store $identity $wrong}
    Check ($null -eq (Open-CiSdkCacheEntry $store $identity ('2'*64))) 'Missing output version was not a cache miss.'
}
Case 'different outputs for equal inputs remain separate immutable versions' {
    [IO.File]::WriteAllText((Join-Path $payload 'lib/DxUi.lib'),'a different valid storage fixture')
    $other=Publish-CiSdkCacheEntry $store $identity $payload
    Check ($other.ManifestSha256 -cne $published.ManifestSha256) 'Different output bytes shared a descriptor.'
    $old=Open-CiSdkCacheEntry $store $identity $published.ManifestSha256
    try{Check ([IO.File]::ReadAllText((Join-Path $old.Payload 'lib/DxUi.lib')) -ceq 'synthetic bytes, not a native SDK') 'Later publication overwrote the old entry.'}finally{Close-CiSdkCacheEntry $old}
}
Case 'short input locators verify the full identity before accepting a hit' {
    $marker=Join-Path (Split-Path -Parent $published.Path) 'input-key.txt'
    $original=[IO.File]::ReadAllBytes($marker)
    try{
        [IO.File]::WriteAllText($marker,($published.Key.Substring(0,16)+('f'*48)),[Text.UTF8Encoding]::new($false))
        Refuses {Open-CiSdkCacheEntry $store $identity $published.ManifestSha256}
    }finally{[IO.File]::WriteAllBytes($marker,$original)}
}
Case 'separate processes share readers but cannot evict an active reader' {
    $scriptPath=Join-Path $root '.build/lease-child.ps1'
    $identityPath=Join-Path $root '.build/identity.json'
    [IO.File]::WriteAllText($identityPath,($identity|ConvertTo-Json))
    [IO.File]::WriteAllText($scriptPath,@'
param($Module,$Store,$IdentityPath,$Digest,$Mode)
$ErrorActionPreference='Stop'
Import-Module $Module
$identity=Get-Content $IdentityPath -Raw|ConvertFrom-Json -AsHashtable
if($Mode -eq 'read'){$entry=Open-CiSdkCacheEntry $Store $identity $Digest;if(-not $entry){exit 2};Close-CiSdkCacheEntry $entry;exit 0}
try{Move-CiSdkCacheEntryToQuarantine $Store $identity $Digest|Out-Null}catch [IO.IOException]{exit 17}
exit 3
'@)
    $entry=Open-CiSdkCacheEntry $store $identity $published.ManifestSha256
    try{
        foreach($mode in @('read','evict')){
            $start=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
            $start.UseShellExecute=$false;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
            foreach($arg in @('-NoProfile','-File',$scriptPath,'-Module',(Join-Path $engine 'Tools/Modules/Ci.SdkCache.psm1'),'-Store',$store,'-IdentityPath',$identityPath,'-Digest',$published.ManifestSha256,'-Mode',$mode)){$start.ArgumentList.Add($arg)}
            $child=[Diagnostics.Process]::Start($start)
            try{
                $stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
                if(-not $child.WaitForExit(30000)){$child.Kill($true);throw 'Owned SDK lease fixture timed out.'}
                $output=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
                Check ($child.ExitCode -eq $(if($mode -eq 'read'){0}else{17})) "Unexpected $mode child result: $output"
            }finally{$child.Dispose()}
        }
    }finally{Close-CiSdkCacheEntry $entry}
}
Case 'source mutation during publish preserves staging and exposes no complete entry' {
    $module=Get-Module Ci.SdkCache
    $original=& $module {(Get-Command Get-CiSdkPayloadFiles).ScriptBlock}
    $changed=$identity|ConvertTo-Json|ConvertFrom-Json -AsHashtable;$changed.environmentIdentity='1'*64
    $source=Join-Path $payload 'lib/DxUi.lib';$saved=[IO.File]::ReadAllBytes($source)
    try{
        & $module {
            param($Original,$Root,$File)
            $script:SdkOriginalCatalog=$Original;$script:SdkMutationRoot=$Root;$script:SdkMutationFile=$File;$script:SdkMutationPending=$true
            Set-Item Function:script:Get-CiSdkPayloadFiles {
                param($Root)
                $catalog=@(& $script:SdkOriginalCatalog $Root)
                if($script:SdkMutationPending -and $Root -ceq $script:SdkMutationRoot){$script:SdkMutationPending=$false;[IO.File]::AppendAllText($script:SdkMutationFile,'mutated after source acquisition')}
                return $catalog
            }
        } $original $payload $source
        Refuses {Publish-CiSdkCacheEntry $store $changed $payload}
    }finally{
        & $module {param($Original) Set-Item Function:script:Get-CiSdkPayloadFiles $Original;Remove-Variable SdkOriginalCatalog,SdkMutationRoot,SdkMutationFile,SdkMutationPending -Scope Script} $original
        [IO.File]::WriteAllBytes($source,$saved)
    }
    Check ($null -eq (Open-CiSdkCacheEntry $store $changed ('2'*64))) 'Interrupted publication exposed a cache hit.'
    Check (@(Get-ChildItem (Join-Path $store 'staging') -Directory).Count -gt 0) 'Failed publication evidence was discarded.'
}
Case 'changed, extra and missing files fail integrity without timestamp shortcuts' {
    $file=Join-Path $published.Payload 'lib/DxUi.lib';$bytes=[IO.File]::ReadAllBytes($file);$stamp=[IO.File]::GetLastWriteTimeUtc($file)
    $corrupt=[byte[]]$bytes.Clone();$corrupt[0]=$corrupt[0] -bxor 1
    [IO.File]::WriteAllBytes($file,$corrupt);[IO.File]::SetLastWriteTimeUtc($file,$stamp)
    Refuses {Open-CiSdkCacheEntry $store $identity $published.ManifestSha256}
    [IO.File]::WriteAllBytes($file,$bytes)
    $extra=Join-Path $published.Payload 'extra.dll';[IO.File]::WriteAllText($extra,'unexpected')
    Refuses {Open-CiSdkCacheEntry $store $identity $published.ManifestSha256};[IO.File]::Delete($extra)
    [IO.File]::Move($file,$file+'.held')
    try{Refuses {Open-CiSdkCacheEntry $store $identity $published.ManifestSha256}}finally{[IO.File]::Move($file+'.held',$file)}
}
Case 'coherently rewritten manifest cannot replace an independently retained digest' {
    $file=Join-Path $published.Path 'entry.json';$bytes=[IO.File]::ReadAllBytes($file)
    $changed=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -AsHashtable;$changed.files[0].sha256='1'*64
    [IO.File]::WriteAllText($file,($changed|ConvertTo-Json -Depth 10))
    try{Refuses {Open-CiSdkCacheEntry $store $identity $published.ManifestSha256}}finally{[IO.File]::WriteAllBytes($file,$bytes)}
}
Case 'mutation during a reader lease is detected on close and releases the lease' {
    $entry=Open-CiSdkCacheEntry $store $identity $published.ManifestSha256
    $file=Join-Path $entry.Payload 'lib/DxUi.lib';$bytes=[IO.File]::ReadAllBytes($file)
    [IO.File]::WriteAllText($file,'changed during reader use')
    try{Refuses {Close-CiSdkCacheEntry $entry}}finally{[IO.File]::WriteAllBytes($file,$bytes)}
    $restored=Open-CiSdkCacheEntry $store $identity $published.ManifestSha256;Close-CiSdkCacheEntry $restored
}
Case 'import preserves the exact original manifest and independent identity across stores' {
    $importStore=Join-Path $root '.build/imported-sdk-cache'
    Initialize-CiSdkStore $root $importStore
    $original=[IO.File]::ReadAllBytes((Join-Path $published.Path 'entry.json'))
    $imported=Import-CiSdkCacheEntry -StoreRoot $importStore -Identity $identity -EntryRoot $published.Path -ManifestSha256 $published.ManifestSha256
    Check ($imported.ManifestSha256 -ceq $published.ManifestSha256) 'Import rewrote the original output identity.'
    Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $imported.Path 'entry.json'))) -ceq [Convert]::ToBase64String($original)) 'Manifest bytes changed during import.'
    $leased=Open-CiSdkCacheEntry $importStore $identity $published.ManifestSha256
    Close-CiSdkCacheEntry $leased
    Refuses {Import-CiSdkCacheEntry $importStore $identity $published.Path ('0'*64)}
    $changed=$identity|ConvertTo-Json|ConvertFrom-Json -AsHashtable;$changed.apiRevision=5
    Refuses {Import-CiSdkCacheEntry $importStore $changed $published.Path $published.ManifestSha256}
    $file=Join-Path $published.Payload 'lib/DxUi.lib';$bytes=[IO.File]::ReadAllBytes($file)
    try{
        [IO.File]::WriteAllText($file,'corrupt imported input')
        Refuses {Import-CiSdkCacheEntry $importStore $identity $published.Path $published.ManifestSha256}
    }finally{[IO.File]::WriteAllBytes($file,$bytes)}
}
Case 'quarantine retains original bytes and a missing entry is a cache miss' {
    $retained=Move-CiSdkCacheEntryToQuarantine $store $identity $published.ManifestSha256
    Check (Test-Path -LiteralPath (Join-Path $retained 'payload/lib/DxUi.lib')) 'Quarantine lost the original payload.'
    Check ($null -eq (Open-CiSdkCacheEntry $store $identity $published.ManifestSha256)) 'Quarantined entry was still accepted.'
}
Case 'portable path grammar refuses traversal, streams and device names' {
    $module=Get-Module Ci.SdkCache
    foreach($path in @('../escape.h','a/../escape.h','a\\escape.h','/root.h','a:stream','a/CON.h','a/trailing.')){
        Refuses {& $module {param($p) Test-CiSdkRelativePath $p} $path}
    }
}
$failed=@($results|Where-Object{-not $_.passed})
[IO.File]::WriteAllText((Join-Path $root 'results.json'),([ordered]@{kind='synthetic SDK store controls; no native SDK acceptance';cases=$results.ToArray();passed=$results.Count-$failed.Count;failed=$failed.Count}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host "SDK store results: $root"
if($failed.Count){throw "$($failed.Count) SDK store cases failed."}
$global:LASTEXITCODE=0
