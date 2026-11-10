# Repository-read transport only. Callers independently authenticate the server
# envelope and own the destination; this helper grants no artifact/result trust.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Receive-CiHostedArtifactArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^RedSalamanders/(DxUi|RedSalamander|RedXe|RedTilde|RedPrism|RedMonitor)$')][string]$Repository,
        [Parameter(Mandatory)][Collections.IDictionary]$Artifact,[Parameter(Mandatory)][string]$Destination)
    if(-not $env:GH_TOKEN -or $Artifact.artifactId -cnotmatch '^[1-9][0-9]{0,19}$' -or
        $Artifact.archiveSha256 -cnotmatch '^[a-f0-9]{64}$' -or $Artifact.archiveBytes -lt 1 -or $Artifact.archiveBytes -gt 4GB){
        throw 'Repository-read credentials and a bounded independently authenticated artifact envelope are required.'
    }
    $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false
    $api=[Net.Http.HttpClient]::new($handler);$download=[Net.Http.HttpClient]::new()
    $response=$null;$stream=$null;$target=$null;$deadline=[Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(10))
    try{
        $api.DefaultRequestHeaders.UserAgent.ParseAdd('RedSalamanders-ArtifactTransport/1')
        $api.DefaultRequestHeaders.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$env:GH_TOKEN)
        $api.DefaultRequestHeaders.Add('X-GitHub-Api-Version','2026-03-10')
        $response=$api.GetAsync("https://api.github.com/repos/$Repository/actions/artifacts/$($Artifact.artifactId)/zip",[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$deadline.Token).GetAwaiter().GetResult()
        if([int]$response.StatusCode -ne 302){throw 'GitHub refused the original artifact download.'}
        $location=$response.Headers.Location
        if($null -eq $location -or -not $location.IsAbsoluteUri -or $location.Scheme -cne 'https' -or $location.UserInfo){throw 'GitHub returned an invalid artifact redirect.'}
        $response.Dispose();$response=$null
        # No API credential is attached to the separately constructed signed-URL client.
        $response=$download.GetAsync($location,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$deadline.Token).GetAwaiter().GetResult()
        if(-not $response.IsSuccessStatusCode){throw 'Original artifact storage refused the download.'}
        $stream=$response.Content.ReadAsStreamAsync($deadline.Token).GetAwaiter().GetResult()
        $target=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=[byte[]]::new(1MB);$written=0L
        while(($count=$stream.ReadAsync($buffer,0,$buffer.Length,$deadline.Token).GetAwaiter().GetResult()) -gt 0){
            $written+=$count
            if($written -gt $Artifact.archiveBytes){throw 'Original artifact exceeds its server-declared size.'}
            $target.Write($buffer,0,$count)
        }
        $target.Flush($true);$target.Dispose();$target=$null
        if($written -ne $Artifact.archiveBytes -or
            (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Artifact.archiveSha256){
            throw 'Downloaded artifact differs from its original server digest or size.'
        }
    }finally{
        if($null -ne $target){$target.Dispose()};if($null -ne $stream){$stream.Dispose()};if($null -ne $response){$response.Dispose()}
        $api.Dispose();$download.Dispose();$handler.Dispose();$deadline.Dispose()
    }
}

Export-ModuleMember -Function Receive-CiHostedArtifactArchive
