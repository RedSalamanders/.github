<#
.SYNOPSIS Runs actual owned MSVC PDB-service lifetime controls without building a product.
.PARAMETER HarnessRoot Reviewed RedSalamander checkout supplying its canonical sandbox and contained-process helpers.
.PARAMETER EngineRoot Exact reviewed engine checkout supplying Set-CiNativeProcessEnvironment.
.PARAMETER TestRoot Existing marked RedSalamander.Perf sandbox; never initializes a drive-root folder.
.PARAMETER CompilerPath Exact discovered native x64 MSVC cl.exe, matching the toolchain being investigated.
.OUTPUTS Native compilation logs, owned-service observations and an explicitly scoped result under TestRoot/evidence/compiler-metadata.
.NOTES Manual Windows native control only; refuses compiler-free execution before imports or outputs. Uses the reviewed Root containment helper's own job-membership predicate for diagnostic compatibility; no foreign process is adopted or stopped. The shared negative control gives only two fixture jobs the same fresh test-owned endpoint. Positive controls use separate endpoints, retire A and actually compile again in B. Tests /Zi and /ZI on x64; this is not product, ARM64, ASan-runtime or original-C1090 reproduction qualification. Helper source hashes and all failed evidence are retained. Changing harness internals can make this diagnostic visibly unsupported.
.EXAMPLE ./Tests/Test-NativePdbIsolation.ps1 -HarnessRoot ../RedSalamander -EngineRoot . -TestRoot Z:/RedSalamander.Perf -CompilerPath '<discovered native x64 cl.exe>'
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$HarnessRoot,[Parameter(Mandatory)][string]$EngineRoot,
    [Parameter(Mandatory)][string]$TestRoot,[Parameter(Mandatory)][string]$CompilerPath)
$ErrorActionPreference='Stop'
if($env:CI_NATIVE_BUILDS_DISABLED -ceq 'true'){throw 'Native PDB lifetime controls are forbidden in compiler-free execution.'}
if(-not $IsWindows){throw 'Native PDB lifetime controls require Windows and the actual reviewed MSVC toolchain.'}
foreach($name in @('CL','_CL_')){
    if([Environment]::GetEnvironmentVariable($name,'Process')){throw ('Opaque compiler overrides cannot change native metadata controls: '+$name)}
}
$root=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $HarnessRoot).Path)
$EngineRoot=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $EngineRoot).Path)
$helperFiles=@((Join-Path $root 'Tools/Modules/Build/SanitizedEnvironment.psm1'),(Join-Path $root 'Tools/Modules/Testing/TestSandbox.psm1'),(Join-Path $EngineRoot 'Tools/Modules/Ci.Policy.psm1'))
$helperHashes=@{};foreach($file in $helperFiles){$helperHashes[$file]=(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant()}
Import-Module (Join-Path $root 'Tools/Modules/Testing/TestSandbox.psm1')
Import-Module (Join-Path $root 'Tools/Modules/Build/SanitizedEnvironment.psm1')
Import-Module (Join-Path $EngineRoot 'Tools/Modules/Ci.Policy.psm1')
$context=New-RSTestRunContext -RepoRoot $root -TestRootOverride $TestRoot
$env:REDSALAMANDER_TEST_ROOT=$context.TestRoot;$env:REDSALAMANDER_TEST_RUN_ID=$context.RunId
$scratch=New-RSTestSandboxScratchDirectory -RepoRoot $root -Harness I61NativePdb -Case Lifetime
$env:TEMP=$scratch;$env:TMP=$scratch
$evidence=Join-Path $context.TestRoot ('evidence/compiler-metadata/'+$context.RunId)
[void][IO.Directory]::CreateDirectory($evidence)
$compiler=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CompilerPath).Path)
if(-not(Test-Path -LiteralPath $compiler)){throw 'Use the actual discovered compiler; no alternate toolchain fallback.'}
$hostPath=(Get-Process -Id $PID).Path
$workerPath=Join-Path $scratch 'worker.ps1'
$worker=@'
param([string]$Compiler,[string]$CaseRoot,[string]$DebugFlag)
$ErrorActionPreference='Stop'
function Compile([string]$Stem){
    $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$Compiler;$psi.WorkingDirectory=$CaseRoot
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    foreach($arg in @('/nologo',$DebugFlag,'/FS','/Od','/Wall','/WX-','/c',(Join-Path $CaseRoot 'input.cpp'),('/Fo'+(Join-Path $CaseRoot ($Stem+'.obj'))),('/Fd'+(Join-Path $CaseRoot 'unit.pdb')))){[void]$psi.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::Start($psi)
    try{
        $started=$process.StartTime.ToUniversalTime();$clId=$process.Id
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(60000)){$process.Kill($true);throw 'Owned fixture compiler timed out.'}
        $ended=[DateTime]::UtcNow;$exit=$process.ExitCode
        [IO.File]::WriteAllText((Join-Path $CaseRoot ($Stem+'.stdout.log')),$stdout.GetAwaiter().GetResult())
        [IO.File]::WriteAllText((Join-Path $CaseRoot ($Stem+'.stderr.log')),$stderr.GetAwaiter().GetResult())
        if($exit){throw ('Owned native metadata fixture failed: '+$exit)}
        if(($stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()) -match '(?im)\bwarning\s+[A-Z]+[0-9]+'){throw 'Native metadata fixture must compile with zero warnings.'}
        $object=[IO.File]::ReadAllBytes((Join-Path $CaseRoot ($Stem+'.obj')))
        if($object.Length -lt 2 -or [BitConverter]::ToUInt16($object,0) -ne 0x8664){throw 'Actual native metadata fixture did not emit an x64 COFF object.'}
        if(-not(Test-Path (Join-Path $CaseRoot 'unit.pdb')) -or (Get-Item (Join-Path $CaseRoot 'unit.pdb')).Length -le 0){throw 'Native compile produced no PDB.'}
        return @{processId=$clId;startUtc=$started.ToString('o');endUtc=$ended.ToString('o');exitCode=$exit}
    }finally{$process.Dispose()}
}
$first=Compile first
[IO.File]::WriteAllText((Join-Path $CaseRoot 'ready.json'),($first|ConvertTo-Json))
$deadline=[DateTime]::UtcNow.AddSeconds(90)
while([DateTime]::UtcNow -lt $deadline){
    if(Test-Path (Join-Path $CaseRoot 'compile-again')){
        $second=Compile second
        [IO.File]::WriteAllText((Join-Path $CaseRoot 'second.json'),($second|ConvertTo-Json))
        while([DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
    }
    Start-Sleep -Milliseconds 100
}
throw 'Owned lifetime fixture expired before controller cleanup.'
'@
[IO.File]::WriteAllText($workerPath,$worker)
function Wait-Ready($Process,[string]$Path){
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path -LiteralPath $Path)){
        if($Process.HasExited){throw ('Owned worker exited before readiness: '+$Process.StandardError.ReadToEnd())}
        if($timer.Elapsed.TotalSeconds -gt 65){throw 'Owned metadata readiness timed out.'}
        Start-Sleep -Milliseconds 100
    }
    return Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
}
function Get-Server($Record,$OwnedProcess){
    $start=[datetime]$Record.startUtc;$end=[datetime]$Record.endUtc
    # Diagnostic-only access to this controller's own containment object. Use its
    # native job membership predicate; service spawn brokers may outlive cl.exe.
    $flags=[Reflection.BindingFlags]'Instance,NonPublic'
    $job=$OwnedProcess.GetType().GetField('job',$flags).GetValue($OwnedProcess)
    $contains=$job.GetType().GetMethod('ContainsProcess',$flags)
    $matches=[Collections.Generic.List[object]]::new()
    $observed=@(Get-CimInstance Win32_Process -Filter "Name='mspdbsrv.exe'")
    $observed|Select-Object ProcessId,ParentProcessId,ExecutablePath,CreationDate|ConvertTo-Json|Set-Content (Join-Path $evidence ('server-observation-'+[guid]::NewGuid().ToString('N')+'.json'))
    foreach($row in $observed){
        $process=$null;$borrowed=$null
        try{
            $process=[Diagnostics.Process]::GetProcessById([int]$row.ProcessId)
            $borrowed=[Microsoft.Win32.SafeHandles.SafeFileHandle]::new($process.Handle,$false)
            $member=[bool]$contains.Invoke($job,@($borrowed))
            if($member){$matches.Add($process);$process=$null}
        }finally{if($borrowed){$borrowed.Dispose()};if($process){$process.Dispose()}}
    }
    if($matches.Count -gt 1){foreach($process in $matches){$process.Dispose()};throw 'Ambiguous service membership in the exact owned job.'}
    if($matches.Count){return $matches[0]}
    return $null
}
$rows=[Collections.Generic.List[object]]::new()
foreach($debugFlag in @('/Zi','/ZI')){
    foreach($mode in @('shared-negative-control','isolated-positive')){
        $a=$null;$b=$null;$serverA=$null;$serverB=$null
        $caseRoot=Join-Path $scratch (($(if($debugFlag -ceq '/Zi'){'program-database'}else{'edit-and-continue'}))+'-'+$mode)
        $roots=@(Join-Path $caseRoot 'a';Join-Path $caseRoot 'b')
        foreach($path in $roots){[void][IO.Directory]::CreateDirectory($path);[IO.File]::WriteAllText((Join-Path $path 'input.cpp'),'struct Example { int field; }; int PdbProbe(Example value) { return value.field + 1; }')}
        try{
            $startA=[Diagnostics.ProcessStartInfo]::new();$startA.FileName=$hostPath;$startA.WorkingDirectory=$roots[0];$startA.UseShellExecute=$false
            $startA.CreateNoWindow=$true;$startA.RedirectStandardOutput=$true;$startA.RedirectStandardError=$true
            foreach($value in @('-NoProfile','-File',$workerPath,'-Compiler',$compiler,'-CaseRoot',$roots[0],'-DebugFlag',$debugFlag)){[void]$startA.ArgumentList.Add($value)}
            $endpointA=Set-CiNativeProcessEnvironment -ProcessStartInfo $startA
            $a=Start-RSContainedProcess -ProcessStartInfo $startA
            if(-not $a.IsInContainmentJob){throw 'First owned worker is not contained.'}
            $recordA=Wait-Ready $a (Join-Path $roots[0] 'ready.json');$serverA=Get-Server $recordA $a
            if($null -eq $serverA){throw 'First fixture created no independently attributable metadata service.'}
            $startB=[Diagnostics.ProcessStartInfo]::new();$startB.FileName=$hostPath;$startB.WorkingDirectory=$roots[1];$startB.UseShellExecute=$false
            $startB.CreateNoWindow=$true;$startB.RedirectStandardOutput=$true;$startB.RedirectStandardError=$true
            foreach($value in @('-NoProfile','-File',$workerPath,'-Compiler',$compiler,'-CaseRoot',$roots[1],'-DebugFlag',$debugFlag)){[void]$startB.ArgumentList.Add($value)}
            $endpointB=Set-CiNativeProcessEnvironment -ProcessStartInfo $startB
            if($mode -ceq 'shared-negative-control'){$startB.Environment['_MSPDBSRV_ENDPOINT_']=$endpointA}
            $b=Start-RSContainedProcess -ProcessStartInfo $startB
            if(-not $b.IsInContainmentJob){throw 'Second owned worker is not contained.'}
            $recordB=Wait-Ready $b (Join-Path $roots[1] 'ready.json');$serverB=Get-Server $recordB $b
            if($mode -ceq 'shared-negative-control'){
                if($null -ne $serverB){throw 'Negative control did not share the original owned service.'}
            }elseif($null -eq $serverB -or $serverA.Id -eq $serverB.Id -or $endpointA -ceq $endpointB){throw 'Positive fixture did not create independent native services.'}
            Close-RSContainedProcess -Process $a;$a=$null
            if(-not $serverA.WaitForExit(5000)){throw 'Original owned service survived its job; native cleanup control is inconclusive.'}
            if($mode -ceq 'isolated-positive'){
                if($serverB.HasExited){throw 'Closing A retired B metadata service.'}
                [IO.File]::WriteAllText((Join-Path $roots[1] 'compile-again'),'owned controller request')
                $second=Wait-Ready $b (Join-Path $roots[1] 'second.json')
                if($second.exitCode -ne 0 -or $serverB.HasExited){throw 'B failed actual compilation after A cleanup.'}
            }
            $rows.Add(@{debugFlag=$debugFlag;mode=$mode;passed=$true;originalOwnedServiceRetired=$true;secondServiceSurvived=($mode -ceq 'isolated-positive');secondCompileAfterCleanup=($mode -ceq 'isolated-positive')})
            [IO.File]::WriteAllText((Join-Path $evidence 'progress.json'),($rows.ToArray()|ConvertTo-Json -Depth 6))
        }finally{
            if($a){Close-RSContainedProcess -Process $a};if($b){Close-RSContainedProcess -Process $b}
            if($serverA){$serverA.Dispose()};if($serverB){$serverB.Dispose()}
        }
    }
}
foreach($file in $helperFiles){if((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $helperHashes[$file]){throw 'Reviewed native helper source changed during lifetime controls.'}}
$provenance=@($helperFiles|ForEach-Object {@{name=[IO.Path]::GetFileName($_);sha256=$helperHashes[$_]}})
[IO.File]::WriteAllText((Join-Path $evidence 'helper-provenance.json'),($provenance|ConvertTo-Json -Depth 5))
[IO.File]::WriteAllText((Join-Path $evidence 'scope.json'),(@{role='ActualX64MsvcPdbServiceLifetimeControls';cases=$rows.ToArray();compilerSha256=(Get-FileHash $compiler).Hash.ToLowerInvariant();helperSha256=(Get-FileHash (Join-Path $EngineRoot 'Tools/Modules/Ci.Policy.psm1')).Hash.ToLowerInvariant();productQualified=$false;arm64Qualified=$false;originalC1090Reproduced=$false}|ConvertTo-Json -Depth 7))
Write-Host ('PASS actual private/shared owned MSVC PDB service lifetime controls: '+$evidence)
