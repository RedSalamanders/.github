<#
.SYNOPSIS Executes real pinned-SDK MSBuild ABI admission controls without product compilation.
.PARAMETER ProjectRoot Application owning the already verified SDK reader and its .build witness.
.PARAMETER SdkRoot Exact payload supplied by the active verified pinned SDK reader.
.PARAMETER LeasePath Still-held reader witness; no control can bypass its ownership check.
.PARAMETER Platform Native SDK target x64 or ARM64.
.PARAMETER MSBuildPath Existing Visual Studio MSBuild selected by the application.
.OUTPUTS Create-only logs and a controls.json receipt beneath application .build/sdk-consumer-controls.
.NOTES Requires Windows, PowerShell 7.4, a compatible SDK and active reader. Refuses compiler-free PR execution.
Never compiles or launches a product, changes a pin or grants native product qualification.
.EXAMPLE ./Tools/Test-SdkConsumerPolicy.ps1 -ProjectRoot ../RedMonitor -SdkRoot ../RedMonitor/.build/sdk/payload -LeasePath ../RedMonitor/.build/sdk-leases/active.json -Platform x64 -MSBuildPath C:/Tools/MSBuild.exe
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$SdkRoot,
    [Parameter(Mandatory)][string]$LeasePath,[Parameter(Mandatory)][ValidateSet('x64','ARM64')][string]$Platform,
    [Parameter(Mandatory)][string]$MSBuildPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows -or $env:CI_NATIVE_BUILDS_DISABLED -eq 'true'){throw 'SDK MSBuild controls require explicit native-tooling execution.'}
$engine=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $engine 'Tools/Modules/Ci.SdkConsumer.psm1')
Import-Module (Join-Path $engine 'Tools/Modules/Ci.Policy.psm1')
$root=[IO.Path]::GetFullPath($ProjectRoot)
Assert-CiSdkConsumerLease -ProjectRoot $root -SdkRoot $SdkRoot -LeasePath $LeasePath -Platform $Platform -Configuration Release
if(-not(Test-Path -LiteralPath $MSBuildPath -PathType Leaf)){throw 'The selected application MSBuild is missing.'}
$run=Assert-CiContainedPath $root (Join-Path $root ('.build/sdk-consumer-controls/'+[guid]::NewGuid().ToString('N')))
[void][IO.Directory]::CreateDirectory($run)
$manifest=Get-Content (Join-Path $SdkRoot 'sdk-manifest.json') -Raw|ConvertFrom-Json
    $xml=@'
<Project>
  <PropertyGroup>
    <CiSdkProjectRoot>@ROOT@</CiSdkProjectRoot><CiSdkRoot>@SDK@</CiSdkRoot>
    <CiSdkLeasePath>@LEASE@</CiSdkLeasePath>
    <Configuration>Release</Configuration><Platform>@PLATFORM@</Platform><VCToolsVersion>@COMPILER@</VCToolsVersion>
    <EnableASAN Condition="'$(SdkFixtureCase)'=='global-asan'">true</EnableASAN>
    <DxUiDisableStlAnnotations Condition="'$(SdkFixtureCase)'=='global-stl'">true</DxUiDisableStlAnnotations>
    <DxUiRoot Condition="'$(SdkFixtureCase)'=='mixed-source'">C:\synthetic-source</DxUiRoot>
  </PropertyGroup>
  <Import Project="@SDK@\DxUi.Sdk.props" /><Import Project="@TARGETS@" />
  <PropertyGroup>
    <CiSdkRoot Condition="'$(SdkFixtureCase)'=='missing-root'"></CiSdkRoot>
    <CiSdkRoot Condition="'$(SdkFixtureCase)'=='wrong-root'">@ROOT@\.build\another-sdk</CiSdkRoot>
  </PropertyGroup>
  <ItemGroup>
    <ClCompile Include="fixture.cpp">
      <RuntimeLibrary Condition="'$(SdkFixtureCase)'=='crt'">MultiThreaded</RuntimeLibrary>
      <LanguageStandard Condition="'$(SdkFixtureCase)'=='language'">stdcpp20</LanguageStandard>
      <EnableASAN Condition="'$(SdkFixtureCase)'=='file-asan'">true</EnableASAN>
      <PreprocessorDefinitions Condition="'$(SdkFixtureCase)'=='debug'">_DEBUG;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <PreprocessorDefinitions Condition="'$(SdkFixtureCase)'=='stl'">_DISABLE_STL_ANNOTATION;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <PreprocessorDefinitions Condition="'$(SdkFixtureCase)'=='vector'">_DISABLE_VECTOR_ANNOTATION;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <PreprocessorDefinitions Condition="'$(SdkFixtureCase)'=='string'">_DISABLE_STRING_ANNOTATION;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <PreprocessorDefinitions Condition="'$(SdkFixtureCase)'=='iterator'">_ITERATOR_DEBUG_LEVEL=1;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <PreprocessorDefinitions Condition="'$(SdkFixtureCase)'=='secure-scl'">_SECURE_SCL=1;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <PreprocessorDefinitions Condition="'$(SdkFixtureCase)'=='iterator-debugging'">_HAS_ITERATOR_DEBUGGING=1;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <StructMemberAlignment Condition="'$(SdkFixtureCase)'=='packing'">1Byte</StructMemberAlignment>
      <TreatWChar_tAsBuiltInType Condition="'$(SdkFixtureCase)'=='wchar'">false</TreatWChar_tAsBuiltInType>
      <CallingConvention Condition="'$(SdkFixtureCase)'=='calling-convention'">StdCall</CallingConvention>
      <PreprocessorDefinitions Condition="'$(SdkFixtureCase)'=='missing-ndebug'">UNICODE;_UNICODE</PreprocessorDefinitions>
      <AdditionalOptions Condition="'$(SdkFixtureCase)'=='opaque-crt'">/MT %(AdditionalOptions)</AdditionalOptions>
      <AdditionalOptions Condition="'$(SdkFixtureCase)'=='opaque-language'">/std:c++20 %(AdditionalOptions)</AdditionalOptions>
      <AdditionalOptions Condition="'$(SdkFixtureCase)'=='opaque-annotation'">/D_DISABLE_STL_ANNOTATION %(AdditionalOptions)</AdditionalOptions>
      <AdditionalOptions Condition="'$(SdkFixtureCase)'=='opaque-iterator'">/D_ITERATOR_DEBUG_LEVEL=1 %(AdditionalOptions)</AdditionalOptions>
      <AdditionalOptions Condition="'$(SdkFixtureCase)'=='opaque-quoted-iterator'">/D &quot;_ITERATOR_DEBUG_LEVEL=1&quot; %(AdditionalOptions)</AdditionalOptions>
      <AdditionalOptions Condition="'$(SdkFixtureCase)'=='opaque-undefine'">/U NDEBUG %(AdditionalOptions)</AdditionalOptions>
      <AdditionalOptions Condition="'$(SdkFixtureCase)'=='opaque-packing'">/Zp1 %(AdditionalOptions)</AdditionalOptions>
      <AdditionalOptions Condition="'$(SdkFixtureCase)'=='opaque-wchar'">/Zc:wchar_t- %(AdditionalOptions)</AdditionalOptions>
    </ClCompile>
    <ClCompile Include="later.cpp" Condition="'$(SdkFixtureCase)'=='second-tu-crt'"><RuntimeLibrary>MultiThreaded</RuntimeLibrary></ClCompile>
  </ItemGroup>
</Project>
'@
    $values=@{ROOT=($root);SDK=$SdkRoot;LEASE=$LeasePath;ENGINE=$engine;PLATFORM=$Platform;
        COMPILER=$manifest.compiler.vcToolsVersion;TARGETS=(Join-Path $engine 'Tools/MSBuild/Ci.SdkConsumer.targets')}
    foreach($key in $values.Keys){$xml=$xml.Replace('@'+$key+'@',[Security.SecurityElement]::Escape($values[$key]))}
    $project=Join-Path $run 'SdkAdmission.proj'
    [IO.File]::WriteAllText($project,$xml,[Text.UTF8Encoding]::new($false))
    $msbuild=$MSBuildPath
    $rows=[Collections.Generic.List[object]]::new()
    foreach($case in @('valid','crt','language','global-asan','global-stl','mixed-source','missing-root','wrong-root','second-tu-crt','file-asan','debug','stl','vector','string','iterator','secure-scl','iterator-debugging','packing','wchar','calling-convention','missing-ndebug','opaque-crt','opaque-language','opaque-annotation','opaque-iterator','opaque-quoted-iterator','opaque-undefine','opaque-packing','opaque-wchar')){
        $log=Join-Path $run ($case+'.log')
        & $msbuild $project /nologo /v:minimal '/t:ValidateDxUiSdkProfile;CiValidateSdkConsumer' ("/p:SdkFixtureCase="+$case) *> $log
        $exit=$LASTEXITCODE;$text=[IO.File]::ReadAllText($log)
        $passed=if($case -ceq 'valid'){$exit -eq 0}else{$exit -ne 0 -and $text -match 'Pinned SDK v1|Opaque compiler options'}
        $rows.Add([ordered]@{case=$case;exitCode=$exit;passed=$passed})
        if(-not $passed){throw "SDK MSBuild profile control failed: $case. Preserve $log"}
    }

    $closed=Assert-CiContainedPath $root (Join-Path $root ('.build/sdk-leases/closed-control-'+[guid]::NewGuid().ToString('N')+'.json'))
    Copy-Item -LiteralPath $LeasePath -Destination $closed
    $log=Join-Path $run 'closed-reader.log'
    & $msbuild $project /nologo /v:minimal '/t:CiValidateSdkConsumer' /p:SdkFixtureCase=valid ("/p:CiSdkLeasePath="+$closed) *> $log
    if($LASTEXITCODE -eq 0 -or [IO.File]::ReadAllText($log) -notmatch 'reader lease is closed'){throw 'Actual target admitted a closed witness copy.'}
    $rows.Add([ordered]@{case='closed-reader';exitCode=$LASTEXITCODE;passed=$true})
    [ordered]@{schemaVersion=1;role='SdkConsumerPolicyControls';passed=$true;runtimeQualified=$false;cases=$rows.ToArray()}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $run 'controls.json')
    Write-Host "PASS $($rows.Count) actual shared SDK ABI controls: $run"
$global:LASTEXITCODE=0
