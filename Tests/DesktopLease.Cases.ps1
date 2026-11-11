# Dot-sourced by Test-Engine. All kernel leases below use unique test names; no input or production lock is taken.
Invoke-Case 'Shared desktop admission preserves ordinary noninteractive output and rejects unsupported foreground intent' {
    $desktop=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.DesktopLease.psm1') -Force -PassThru
    $value=Invoke-CiInteractiveDesktopOperation -RequiresInteractiveDesktop $false -Operation {[pscustomobject]@{literal='unchanged 日';exit=19}}
    Assert-Equal 'unchanged 日' $value.literal;Assert-Equal 19 $value.exit
    if(-not $IsWindows){Assert-Refused {Invoke-CiInteractiveDesktopOperation -RequiresInteractiveDesktop $true -Operation {throw 'must not enter'}}}
    else{
        # Execute the public branch at a recording boundary; verify its real compatibility name without taking it.
        & $desktop {
            $script:recorded=@{}
            $script:originalCore=${function:Invoke-CiDesktopLeaseCore}
            function script:Invoke-CiDesktopLeaseCore {param($MutexName,$Operation,$TimeoutMilliseconds)
                $script:recorded.name=$MutexName;& $Operation
            }
        }
        try{
            $value=Invoke-CiInteractiveDesktopOperation -RequiresInteractiveDesktop $true -Operation {'literal result'}
            Assert-Equal 'literal result' $value
            Assert-Equal 'Local\RedSalamander.InteractiveTestRun.v1' (& $desktop {$script:recorded.name})
        }finally{& $desktop {Set-Item Function:script:Invoke-CiDesktopLeaseCore $script:originalCore}}
    }
}

Invoke-Case 'Shared desktop core releases failures, permits same-thread nesting and keeps disjoint test leases independent' {
    if(-not $IsWindows){return}
    $desktop=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.DesktopLease.psm1') -PassThru
    $name='Local\I61.DesktopFixture.'+[guid]::NewGuid().ToString('N')
    $value=& $desktop {param($n)
        Invoke-CiDesktopLeaseCore $n {
            Invoke-CiDesktopLeaseCore $n {'nested result'}
            Invoke-CiDesktopLeaseCore ($n+'.other') {'disjoint result'}
        }
    } $name
    Assert-Equal 'nested result|disjoint result' ($value -join '|')
    Assert-Refused {& $desktop {param($n)Invoke-CiDesktopLeaseCore $n {throw 'controlled operation failure'}} $name}
    $mutex=[Threading.Mutex]::new($false,$name)
    try{$available=$mutex.WaitOne(0);Assert-True $available;if($available){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}
}

Invoke-Case 'Shared desktop contenders time out without entering and abandoned owned fixtures recover without input' {
    if(-not $IsWindows){return}
    $desktop=Import-Module (Join-Path $engineRoot 'Tools/Modules/Ci.DesktopLease.psm1') -PassThru
    $name='Local\I61.DesktopFixture.'+[guid]::NewGuid().ToString('N')
    $mutex=[Threading.Mutex]::new($false,$name)
    $directory=New-Fixture 'desktop-admission-processes'
    $scriptPath=Join-Path $directory 'contender.ps1'
    $text=@'
param($ModulePath,$Name,$Kind)
$ErrorActionPreference='Stop'
$m=Import-Module $ModulePath -PassThru
if($Kind -ceq 'abandon'){$owned=[Threading.Mutex]::new($false,$Name);[void]$owned.WaitOne(0);[Environment]::Exit(0)}
$state=@{entered=$false;refused=$false;error=''}
try{& $m {param($n,$s)Invoke-CiDesktopLeaseCore -MutexName $n -TimeoutMilliseconds 50 -Operation {$s.entered=$true}} $Name $state}catch{$state.refused=$true;$state.error=$_.Exception.Message}
$state|ConvertTo-Json -Compress
'@
    [IO.File]::WriteAllText($scriptPath,$text)
    try{
        Assert-True ($mutex.WaitOne(0))
        try{
            $result=Invoke-CiProcess -FilePath (Get-Process -Id $PID).Path -Arguments @('-NoProfile','-File',$scriptPath,(Join-Path $engineRoot 'Tools/Modules/Ci.DesktopLease.psm1'),$name,'contend') -WorkingDirectory $directory -TimeoutSeconds 20
            $state=$result.stdout|ConvertFrom-Json
            Assert-True ($state.refused -and -not $state.entered -and $state.error.StartsWith('Timed out waiting for shared test-desktop admission'))
        }finally{$mutex.ReleaseMutex()}
        $null=Invoke-CiProcess -FilePath (Get-Process -Id $PID).Path -Arguments @('-NoProfile','-File',$scriptPath,(Join-Path $engineRoot 'Tools/Modules/Ci.DesktopLease.psm1'),$name,'abandon') -WorkingDirectory $directory -TimeoutSeconds 20
        $value=& $desktop {param($n)Invoke-CiDesktopLeaseCore $n {'recovered'}} $name
        Assert-Equal 'recovered' $value
    }finally{$mutex.Dispose()}
}
