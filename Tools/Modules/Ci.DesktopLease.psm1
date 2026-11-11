# Admission only: the existing native harness still owns consent, warning, input and verified restoration.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Invoke-CiDesktopLeaseCore {
    param([string]$MutexName,[scriptblock]$Operation,[int]$TimeoutMilliseconds=10800000)
    $mutex=[Threading.Mutex]::new($false,$MutexName)
    $acquired=$false
    try{
        try{$acquired=$mutex.WaitOne($TimeoutMilliseconds)}
        catch [Threading.AbandonedMutexException]{
            $acquired=$true
            Write-Warning 'Acquired an abandoned shared test-desktop admission lease.'
        }
        if(-not $acquired){throw 'Timed out waiting for shared test-desktop admission; no interactive child was launched.'}
        & $Operation
    }finally{
        try{if($acquired){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}
    }
}

function Invoke-CiInteractiveDesktopOperation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$RequiresInteractiveDesktop,[Parameter(Mandatory)][scriptblock]$Operation)
    if(-not $RequiresInteractiveDesktop){return & $Operation}
    if(-not [OperatingSystem]::IsWindows()){throw 'Interactive desktop admission requires Windows.'}
    # Compatibility order is deliberate: Root's existing outer lock first, then
    # the unchanged DxUi native lease inside Operation. Never acquire in reverse.
    Write-Host '[test-desktop] Waiting for shared session admission.' -ForegroundColor DarkGray
    $clock=[Diagnostics.Stopwatch]::StartNew()
    Invoke-CiDesktopLeaseCore -MutexName 'Local\RedSalamander.InteractiveTestRun.v1' -Operation {
        $clock.Stop()
        Write-Host "[test-desktop] Shared session admission wait: $($clock.ElapsedMilliseconds) ms." -ForegroundColor DarkGray
        & $Operation
    }.GetNewClosure()
}

Export-ModuleMember -Function Invoke-CiInteractiveDesktopOperation
