# Live admission only. Product adapters own scenario execution and runtime results.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ci.Policy.psm1')
Import-Module (Join-Path $PSScriptRoot 'Ci.LocalSdkConsumer.psm1')
$script:abi=Import-Module (Join-Path $PSScriptRoot 'Ci.SdkAbi.psm1') -PassThru

function Assert-CiLocalSdkRuntimeRecord {
    param([string]$ProjectRoot,[string]$Receipt,[Collections.IDictionary]$Record)
    foreach($name in @('schemaVersion','role','recipe','projectRoot','sourceBytes','engineInputs','dependency','platform','configuration',
            'outputRoot','executable','executableSha256','inputDescriptor','runtimeRoot','runtimeBytes','testsExecuted','repositoryQualified','productionQualified')){
        if(-not $Record.Contains($name)){throw 'Local SDK runtime requires a complete byte-catalog build record; rebuild older candidates.'}
    }
    if($Record.schemaVersion -ne 1 -or $Record.role -cne 'LocalUnpinnedApplicationBuild' -or $Record.recipe -cne 'LocalUnpinnedReleaseSdk' -or $Record.configuration -cne 'Release'){
        throw 'Local SDK runtime cannot impersonate a pinned or production build.'
    }
    foreach($flag in @('testsExecuted','repositoryQualified','productionQualified')){
        if($Record[$flag] -isnot [bool] -or $Record[$flag]){throw 'A local SDK build record cannot grant test or qualification results.'}
    }
    foreach($name in @('sourceBytes','engineInputs','executableSha256')){
        if($Record[$name] -isnot [string] -or $Record[$name] -cnotmatch '^[a-f0-9]{64}$'){throw 'Local SDK runtime build identity is malformed.'}
    }
    $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(-not [IO.Path]::GetFullPath($Record.projectRoot).Equals($ProjectRoot,$comparison)){throw 'Local SDK runtime build belongs to another project.'}
    $operation=Split-Path -Parent $Receipt
    if([IO.Path]::GetFileName($Receipt) -cne 'local-unpinned-build.json' -or
        [IO.Path]::GetFileName($operation) -cnotmatch '^[a-f0-9]{32}$' -or
        -not [IO.Path]::GetFullPath((Split-Path -Parent $operation)).Equals((Join-Path $ProjectRoot '.build/local-unpinned'),$comparison) -or
        -not [IO.Path]::GetFullPath($Record.outputRoot).Equals($operation,$comparison)){
        throw 'Local SDK runtime requires the original owned build operation.'
    }
    [void](Assert-CiContainedPath $operation $Record.runtimeRoot)
    [void](Assert-CiContainedPath $Record.runtimeRoot $Record.executable)
    if($Record.platform -cnotin @('x64','ARM64') -or [IO.Path]::GetExtension($Record.executable) -ine '.exe'){
        throw 'Local SDK runtime build has an unsupported executable or architecture.'
    }
    if($Record.inputDescriptor -isnot [Collections.IDictionary] -or $Record.inputDescriptor.Count -ne 2 -or
        -not $Record.inputDescriptor.Contains('path') -or -not $Record.inputDescriptor.Contains('sha256') -or
        $Record.inputDescriptor.sha256 -cnotmatch '^[a-f0-9]{64}$' -or -not [IO.Path]::IsPathFullyQualified($Record.inputDescriptor.path)){
        throw 'Local SDK runtime requires the original independently hashed SDK descriptor.'
    }
}

function Assert-CiLocalSdkRuntimeBytes {
    param([Collections.IDictionary]$Record)
    $actual=& $script:abi {param($r)Get-CiPortableSdkFileReference @{ApplicationOutput=$r}} $Record.runtimeRoot
    if(($actual|ConvertTo-Json -Depth 8 -Compress) -cne ($Record.runtimeBytes|ConvertTo-Json -Depth 8 -Compress) -or
        (Get-FileHash -LiteralPath $Record.executable).Hash.ToLowerInvariant() -cne $Record.executableSha256){
        throw 'Local SDK runtime payload inventory or bytes changed.'
    }
}

function Open-CiLocalSdkApplicationRuntimeInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$BuildReceipt,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedBuildSha256,
        [Parameter(Mandatory)][string]$MSBuildPath)
    if(-not $IsWindows -or $env:GITHUB_ACTIONS -ceq 'true' -or $env:CI_NATIVE_BUILDS_DISABLED -ceq 'true'){
        throw 'Local SDK runtime admission requires local Windows native execution.'
    }
    Open-CiLocalSdkRuntimeInput @PSBoundParameters
}

function Open-CiLocalSdkRuntimeInput {
    param([string]$ProjectRoot,[string]$BuildReceipt,[string]$ExpectedBuildSha256,[string]$MSBuildPath)
    $root=[IO.Path]::GetFullPath($ProjectRoot)
    $receipt=Assert-CiContainedPath (Join-Path $root '.build/local-unpinned') $BuildReceipt
    $operation=$null;$stream=$null;$sdk=$null;$files=[Collections.Generic.List[IO.FileStream]]::new()
    try{
        $operation=[IO.File]::Open((Join-Path (Split-Path $receipt) 'operation.lock'),'Open','ReadWrite','None')
        $stream=[IO.File]::Open($receipt,'Open','Read','Read')
        if($stream.Length -gt 32MB -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() -cne $ExpectedBuildSha256){
            throw 'Local SDK runtime build receipt differs from its independently retained digest.'
        }
        $stream.Position=0
        $reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$false,4096,$true)
        try{$record=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable}finally{$reader.Dispose()}
        Assert-CiLocalSdkRuntimeRecord $root $receipt $record
        $architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        if(($record.platform -ceq 'ARM64' -and $architecture -ine 'Arm64') -or ($record.platform -ceq 'x64' -and $architecture -ine 'X64')){
            throw 'Local SDK runtime requires execution on its selected native architecture.'
        }
        $sdk=Open-CiLocalSdkConsumerInput -ProjectRoot $root -Descriptor $record.inputDescriptor.path -ExpectedDescriptorSha256 $record.inputDescriptor.sha256 -Platform $record.platform -Configuration Release -MSBuildPath $MSBuildPath
        if($sdk.SourceBytes -cne $record.sourceBytes -or $sdk.EngineInputs -cne $record.engineInputs -or
            ($sdk.Evidence|ConvertTo-Json -Depth 8 -Compress) -cne ($record.dependency|ConvertTo-Json -Depth 8 -Compress)){
            throw 'Local SDK runtime source, actual engine or dependency differs from its built candidate.'
        }
        Assert-CiLocalSdkRuntimeBytes $record
        foreach($file in $record.runtimeBytes.files){
            if($file.role -cne 'ApplicationOutput'){throw 'Local SDK runtime payload has a foreign byte-catalog role.'}
            $path=Assert-CiContainedPath $record.runtimeRoot (Join-Path $record.runtimeRoot $file.path)
            $files.Add([IO.File]::Open($path,'Open','Read','Read'))
        }
        Assert-CiLocalSdkRuntimeBytes $record
        return [pscustomobject]@{Role='LocalUnpinnedApplicationRuntimeInput';ProjectRoot=$root;Build=$record;ReceiptPath=$receipt;
            ReceiptSha256=$ExpectedBuildSha256;SdkInput=$sdk;Operation=$operation;ReceiptStream=$stream;PayloadStreams=$files;Closed=$false}
    }catch{
        $primary=$_
        foreach($file in $files){$file.Dispose()}
        if($sdk -and -not $sdk.Closed){try{Close-CiLocalSdkConsumerInput $sdk}catch{Write-Warning ('Runtime SDK close also failed: '+$_.Exception.Message)}}
        if($stream){$stream.Dispose()};if($operation){$operation.Dispose()}
        throw $primary
    }
}

function Close-CiLocalSdkApplicationRuntimeInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RuntimeInput)
    if($RuntimeInput.Role -cne 'LocalUnpinnedApplicationRuntimeInput' -or $RuntimeInput.Closed){throw 'An active local SDK application runtime input is required.'}
    $failure=$null
    try{
        Assert-CiLocalSdkRuntimeBytes $RuntimeInput.Build
        Close-CiLocalSdkConsumerInput $RuntimeInput.SdkInput
    }catch{$failure=$_}
    finally{
        foreach($file in $RuntimeInput.PayloadStreams){$file.Dispose()}
        if(-not $RuntimeInput.SdkInput.Closed){try{Close-CiLocalSdkConsumerInput $RuntimeInput.SdkInput}catch{if(-not $failure){$failure=$_}else{Write-Warning $_.Exception.Message}}}
        $RuntimeInput.ReceiptStream.Dispose();$RuntimeInput.Operation.Dispose();$RuntimeInput.Closed=$true
    }
    if($failure){throw $failure}
}

Export-ModuleMember -Function Open-CiLocalSdkApplicationRuntimeInput,Close-CiLocalSdkApplicationRuntimeInput
