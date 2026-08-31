#requires -Version 7.0
<#
.SYNOPSIS
  Dry-runs one of the reusable build workflows on your machine — no GitHub, no
  runner, no publish. It executes the real composite-action scripts, in the same
  order the workflow calls them, against a throwaway copy of a repo, threading
  each step's outputs / env into the next step exactly like Actions would.

.DESCRIPTION
  Steps are classed as:
    offline    - run for real (get-sln-info, get-project-info, version prefix,
                 plugin metadata, update-assembly-info, create-nuspec)
    needs-build - run only if a compile actually happened this run
                 (copy-build-output, check-package-name, add-files-to-nupkg)
    build      - dry-run unless -RunBuild  (dotnet-build, pack-nuget,
                 generate-config-schema)
    docker     - dry-run unless -RunDocker (docker-build-3series)
    dry-always - never executed; the resolved inputs and, for nuget.org, the
                 fail-closed owner+visibility gate are printed
                 (upload-release, publish-nuget-github, publish-nuget-org,
                  embed-devtools-spa, cleanup-failed-release)

  Nothing here calls gh, git push, nuget push, docker push, or the network.

.EXAMPLE
  # smoke-test every lane against a generated fixture
  pwsh tests/run-workflow-local.ps1 -All

.EXAMPLE
  # dry-run the net8 plugin lane against a real local checkout
  pwsh tests/run-workflow-local.ps1 -Workflow plugin-4series-net8 `
       -RepoPath ../epi-lg-display -Repo epi-lg-display -Version 2.3.1

.EXAMPLE
  # actually compile (needs the .NET SDK; still publishes nothing)
  pwsh tests/run-workflow-local.ps1 -Workflow essentials-4series-net8 `
       -RepoPath ../Essentials -Repo Essentials -RunBuild
#>
[CmdletBinding(DefaultParameterSetName = 'one')]
param(
  [Parameter(ParameterSetName = 'one', Mandatory)]
  [ValidateSet(
    'plugin-3series-net35',
    'plugin-4series-net472',
    'plugin-4series-net8',
    'essentials-3series-net35',
    'essentials-4series-net472',
    'essentials-4series-net8')]
  [string]$Workflow,

  [Parameter(ParameterSetName = 'all', Mandatory)]
  [switch]$All,

  [string]$RepoPath,                       # local checkout to test; omitted => fixture
  [string]$Owner = 'PepperDash',
  [string]$Repo,                           # repo name; defaults from RepoPath or fixture
  [ValidateSet('public', 'private')]
  [string]$Visibility = 'public',
  [string]$Version = '2.3.1',
  [string]$Tag,
  [string]$Channel = '',                   # '' => Release, else Debug/prerelease
  [string]$NewVersion = 'true',
  [switch]$ApplyVersionPrefix = $true,
  [string]$EssentialsMajor = '',           # '' => auto-detect (4-Series) ; 3-Series forces '1'
  [string]$PackageStyle = 'concatenated',  # 3-Series plugin id spelling
  [string]$PackagePrefix,                  # default depends on lane
  [string]$Bypass = '',                    # '' => lane default for check-package-name

  [switch]$RunBuild,                        # actually run dotnet-build / pack / schema-gen
  [switch]$RunDocker,                       # actually run docker-build-3series
  [switch]$KeepWorkspace
)

$ErrorActionPreference = 'Stop'
$RepoRoot  = (Resolve-Path "$PSScriptRoot/..").Path
$ActionsRoot = Join-Path $RepoRoot '.github/actions'
$pwshExe   = (Get-Process -Id $PID).Path

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Ok($m)   { Write-Host $m -ForegroundColor Green }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Bad($m)  { Write-Host $m -ForegroundColor Red }

# --------------------------------------------------------------------------
# Fixture: a minimal repo that satisfies the offline steps.
# --------------------------------------------------------------------------
function New-Fixture {
  param([Parameter(Mandatory)][string]$Series, [Parameter(Mandatory)][string]$Dir, [string]$RepoName)
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  $sfx = if ($Series -eq '3series') { '3Series' } else { '4Series' }
  $base = "Fixture.$sfx"

  "Microsoft Visual Studio Solution File, Format Version 12.00" | Set-Content (Join-Path $Dir "$base.sln")
  'MIT-ish fixture license.' | Set-Content (Join-Path $Dir 'LICENSE.md')
  "# $RepoName`nFixture repo for run-workflow-local.ps1." | Set-Content (Join-Path $Dir 'README.md')

  $essVer = if ($Series -eq '3series') { '1.15.6' } else { '2.14.0' }
  @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>$(if ($Series -eq '3series') { 'net35' } else { 'net472' })</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="PepperDashEssentials" Version="$essVer" />
  </ItemGroup>
</Project>
"@ | Set-Content (Join-Path $Dir "$base.csproj")

  # C# Essentials plugin factory: gives get-plugin-metadata something to find and
  # generate-config-schema a ToObject<T>() call site.
  $src = Join-Path $Dir 'src'
  New-Item -ItemType Directory -Force -Path $src | Out-Null
  @'
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using PepperDash.Essentials.Core;

namespace Fixture.Plugin
{
    public class FixtureFactory : EssentialsPluginDeviceFactory<FixtureDevice>
    {
        public FixtureFactory()
        {
            MinimumEssentialsFrameworkVersion = "2.0.0";
            TypeNames = new List<string> { "fixtureDevice", "fixtureDeviceAlt" };
        }

        public override EssentialsDevice BuildDevice(DeviceConfig dc)
        {
            var props = dc.Properties.ToObject<FixtureConfig>();
            return new FixtureDevice(dc.Key, dc.Name, props);
        }
    }

    public class FixtureConfig
    {
        public string Host { get; set; }
        public int Port { get; set; }
    }
}
'@ | Set-Content (Join-Path $src 'FixtureFactory.cs')

  if ($Series -eq '3series') {
    '<?xml version="1.0" encoding="utf-8"?><packages></packages>' | Set-Content (Join-Path $Dir 'packages.config')
    $props = Join-Path $Dir 'Properties'
    New-Item -ItemType Directory -Force -Path $props | Out-Null
    @'
using System.Reflection;
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyInformationalVersion("1.0.0")]
'@ | Set-Content (Join-Path $props 'AssemblyInfo.cs')
  }
}

# --------------------------------------------------------------------------
# Run one action script in the shared workspace; return the delta it wrote.
# --------------------------------------------------------------------------
function Invoke-Step {
  param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [hashtable]$Inputs = @{},
    [hashtable]$ExtraEnv = @{},
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$GhDir
  )
  $outFile = Join-Path $GhDir 'output'
  $envFile = Join-Path $GhDir 'env'
  $sumFile = Join-Path $GhDir 'summary'
  foreach ($f in $outFile, $envFile, $sumFile) { if (-not (Test-Path $f)) { '' | Set-Content $f } }
  $out0 = (Get-Content $outFile).Count
  $env0 = (Get-Content $envFile).Count

  $envLines = [System.Collections.Generic.List[string]]::new()
  $envLines.Add("`$env:GITHUB_OUTPUT='$outFile'")
  $envLines.Add("`$env:GITHUB_ENV='$envFile'")
  $envLines.Add("`$env:GITHUB_STEP_SUMMARY='$sumFile'")
  $envLines.Add("`$env:GITHUB_WORKSPACE='$Workspace'")
  foreach ($k in $Inputs.Keys) {
    $name = 'INPUT_' + ($k.ToUpper() -replace '[-\s]', '_')
    $envLines.Add("`$env:$name='$([string]$Inputs[$k] -replace "'","''")'")
  }
  foreach ($k in $ExtraEnv.Keys) {
    $envLines.Add("`$env:$k='$([string]$ExtraEnv[$k] -replace "'","''")'")
  }

  $runner = Join-Path $GhDir '_run.ps1'
  @"
$($envLines -join "`n")
Set-Location '$Workspace'
& '$ScriptPath'
exit `$LASTEXITCODE
"@ | Set-Content $runner

  $so = Join-Path $GhDir '_stdout'; $se = Join-Path $GhDir '_stderr'
  $p = Start-Process -FilePath $pwshExe `
    -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $runner) `
    -NoNewWindow -Wait -PassThru -RedirectStandardOutput $so -RedirectStandardError $se

  $newOut = @(Get-Content $outFile | Select-Object -Skip $out0)
  $newEnv = @(Get-Content $envFile | Select-Object -Skip $env0)
  $outputs = @{}; foreach ($l in $newOut) { if ($l -match '^(?<k>[^=]+)=(?<v>.*)$') { $outputs[$Matches.k] = $Matches.v } }
  $envVars = @{}; foreach ($l in $newEnv) { if ($l -match '^(?<k>[^=]+)=(?<v>.*)$') { $envVars[$Matches.k] = $Matches.v } }

  [pscustomobject]@{
    ExitCode = $p.ExitCode
    Outputs  = $outputs
    EnvVars  = $envVars
    Stdout   = (Get-Content $so -Raw -ErrorAction SilentlyContinue) ?? ''
    Stderr   = (Get-Content $se -Raw -ErrorAction SilentlyContinue) ?? ''
  }
}

# --------------------------------------------------------------------------
# Lane definition: ordered list of steps.
#   class: offline | needs-build | build | docker | dry-always
#   inputs: scriptblock -> hashtable  (closure over $ctx)
# --------------------------------------------------------------------------
function Get-Lane {
  param([string]$Name, [hashtable]$ctx)

  $series  = if ($Name -like '*3series*') { '3series' } else { '4series' }
  $isPlugin = $Name -like 'plugin-*'
  $steps = [System.Collections.Generic.List[hashtable]]::new()

  $steps.Add(@{ name = 'Get solution info'; action = 'get-sln-info'; script = 'get-sln-info.ps1'
      id = 'sln'; class = 'offline'; inputs = { @{ filter = $ctx.lane.slnFilter } } })

  if ($isPlugin) {
    if ($ctx.inputs.applyVersionPrefix -eq 'true') {
      $steps.Add(@{ name = 'Apply Essentials version prefix'; action = 'apply-essentials-version-prefix'
          script = 'apply-version-prefix.ps1'; id = 'prefix'; class = 'offline'
          inputs = {
            @{ version = $ctx.inputs.version; tag = $ctx.inputs.tag
               'essentials-major' = $(if ($ctx.lane.series -eq '3series') { '1' } else { $ctx.inputs.essentialsMajor })
               'csproj-filter' = $ctx.lane.csprojFilter }
          } })
    }
    if ($series -eq '3series') {
      $steps.Add(@{ name = 'Get project info'; action = 'get-project-info'; script = 'get-project-info.ps1'
          id = 'proj'; class = 'offline'
          inputs = { @{ 'package-prefix' = $ctx.inputs.packagePrefix; 'package-style' = $ctx.inputs.packageStyle } } })
    }
    $steps.Add(@{ name = 'Get plugin metadata'; action = 'get-plugin-metadata'; script = 'get-plugin-metadata.ps1'
        id = 'meta'; class = 'offline'
        inputs = { @{ 'build-type' = $ctx.env.BUILD_TYPE; package = $ctx.steps.proj.package } } })
  }

  if ($series -eq '3series') {
    $steps.Add(@{ name = 'Update AssemblyInfo'; action = 'update-assembly-info'; script = 'update-assembly-info.ps1'
        class = 'offline'; inputs = { @{ version = $ctx.effectiveVersion } } })
    $steps.Add(@{ name = 'Build solution (Docker sspbuilder)'; action = 'docker-build-3series'; script = 'docker-build.ps1'
        class = 'docker'
        inputs = { @{ 'solution-path' = $ctx.steps.sln.'solution-path'; 'build-type' = $ctx.env.BUILD_TYPE
                     'dockerhub-user' = '***'; 'dockerhub-password' = '***' } } })
  }
  else {
    $steps.Add(@{ name = 'Build solution'; action = 'dotnet-build'; script = 'dotnet-build.ps1'
        class = 'build'
        inputs = {
          @{ 'solution-file' = $ctx.steps.sln.'solution-file'; 'build-type' = $ctx.env.BUILD_TYPE
             version = $ctx.effectiveVersion
             'repository-url' = "https://github.com/$($ctx.github.repository)"
             'package-tags' = $ctx.steps.meta.'type-names'
             'release-notes' = $(if ($ctx.steps.meta.'type-names-list') { "Factory TypeNames: $($ctx.steps.meta.'type-names-list')" } else { '' }) }
        } })
  }

  if ($isPlugin -and $series -eq '3series') {
    $steps.Add(@{ name = 'Copy build output'; action = 'copy-build-output'; script = 'copy-build-output.ps1'
        class = 'needs-build'
        inputs = { @{ version = $ctx.effectiveVersion; 'build-type' = $ctx.env.BUILD_TYPE
                     package = $ctx.steps.proj.package; extensions = '.cpz .clz .cplz'
                     'include-dll' = 'true'; 'rename-mode' = 'all' } } })
    $steps.Add(@{ name = 'Create nuspec'; action = 'create-nuspec'; script = 'create-nuspec.ps1'
        id = 'nuspec'; class = 'offline'
        inputs = {
          @{ package = $ctx.steps.proj.package; title = $ctx.steps.proj.title
             version = $ctx.effectiveVersion; 'repo-name' = $ctx.steps.proj.'repo-name'
             'repo-is-plugin' = $ctx.steps.proj.'repo-is-plugin'
             'assembly-name' = $ctx.steps.meta.'assembly-name'
             'type-names' = $ctx.steps.meta.'type-names'
             'type-names-list' = $ctx.steps.meta.'type-names-list'
             'min-framework-version' = $ctx.steps.meta.'min-framework-version'
             'target-framework' = 'net35' }
        } })
    $steps.Add(@{ name = 'Pack NuGet package'; action = 'pack-nuget'; script = 'pack-nuget.ps1'
        class = 'build'
        inputs = { @{ 'nuspec-file' = $ctx.steps.nuspec.'nuspec-file'; version = $ctx.effectiveVersion } } })
    $steps.Add(@{ name = 'Check package name'; action = 'check-package-name'; script = 'check-package-name.ps1'
        class = 'needs-build'; softfail = $true
        inputs = { @{ bypass = $ctx.inputs.bypass } } })
  }

  if (-not $isPlugin -and $series -eq '3series') {
    $steps.Add(@{ name = 'Copy build output'; action = 'copy-build-output'; script = 'copy-build-output.ps1'
        class = 'needs-build'
        inputs = { @{ version = $ctx.inputs.version; 'build-type' = $ctx.env.BUILD_TYPE
                     extensions = '.cpz .clz'; 'include-dll' = 'true'
                     'rename-mode' = 'essentials'; 'copy-nuspec' = 'true' } } })
    $steps.Add(@{ name = 'Pack NuGet package'; action = 'pack-nuget'; script = 'pack-nuget.ps1'
        class = 'build'; softfail = $true
        inputs = { @{ 'nuspec-file' = $ctx.env.NUSPEC_FILE; version = $ctx.inputs.version } } })
  }

  if ($isPlugin -and $series -eq '4series') {
    $steps.Add(@{ name = 'Check package name'; action = 'check-package-name'; script = 'check-package-name.ps1'
        class = 'needs-build'; softfail = $true
        inputs = { @{ bypass = $ctx.inputs.bypass } } })
    $steps.Add(@{ name = 'Generate config schema'; action = 'generate-config-schema'; script = 'discover-config-types.ps1'
        id = 'schema'; class = 'build'; softfail = $true
        inputs = { @{ 'assembly-name' = $ctx.steps.meta.'assembly-name'; 'build-type' = $ctx.env.BUILD_TYPE
                     'output-dir' = 'output/schemas' } } })
    $steps.Add(@{ name = 'Bundle schema into nupkg'; action = 'add-files-to-nupkg'; script = 'add-files-to-nupkg.ps1'
        class = 'needs-build'; softfail = $true
        inputs = { @{ 'source-dir' = 'output/schemas'; 'target-path' = 'schemas'; pattern = '*.schema.json' } } })
    $steps.Add(@{ name = 'Embed devtools SPA'; action = 'embed-devtools-spa'; script = 'embed-devtools-spa.ps1'
        class = 'dry-always'
        inputs = { @{ 'devtools-version' = $ctx.inputs.devToolsVersion } } })
  }

  # Post-build: release + publish. Never executed here.
  $steps.Add(@{ name = 'Upload release'; action = 'upload-release'; class = 'dry-always'
      inputs = { @{ tag = $ctx.effectiveTag; artifacts = $ctx.lane.relArtifacts; prerelease = ($ctx.inputs.channel -ne '') } } })
  $steps.Add(@{ name = 'Publish to GitHub feed'; action = 'publish-nuget-github'; class = 'dry-always'
      inputs = { @{ 'github-token' = '***'; owner = $ctx.github.repository_owner } } })
  $steps.Add(@{ name = 'Publish to NuGet.org'; action = 'publish-nuget-org'; class = 'dry-always-gate'
      inputs = { @{ 'nuget-api-key' = '***' } } })

  $steps
}

# --------------------------------------------------------------------------
# Run a single lane.
# --------------------------------------------------------------------------
function Invoke-Lane {
  param([Parameter(Mandatory)][string]$Name)

  Write-Host ''
  Info "================  $Name  ================"

  # ---- resolve params / fixture ----
  $series = if ($Name -like '*3series*') { '3series' } else { '4series' }
  $laneRepo = if ($Repo) { $Repo }
              elseif ($RepoPath) { Split-Path -Leaf (Resolve-Path $RepoPath) }
              elseif ($Name -like 'plugin-*') { 'epi-fixture-device' }
              else { 'Essentials' }
  $lanePrefix = if ($PackagePrefix) { $PackagePrefix }
                elseif ($series -eq '3series') { 'PepperDash.Essentials.Plugin.' }
                else { 'PepperDash.Essentials.Plugins.' }
  $laneBypass = if ($Bypass -ne '') { $Bypass }
                elseif ($Name -eq 'plugin-3series-net35') { 'true' } else { 'false' }
  $laneTag = if ($Tag) { $Tag } else { "v$Version" }

  $work = Join-Path ([System.IO.Path]::GetTempPath()) ("wf-" + $Name + "-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
  $ws   = Join-Path $work 'workspace'
  $gh   = Join-Path $work 'gh'
  New-Item -ItemType Directory -Force -Path $ws, $gh | Out-Null
  foreach ($f in 'output', 'env', 'summary') { '' | Set-Content (Join-Path $gh $f) }

  if ($RepoPath) {
    Info "Copying $RepoPath -> throwaway workspace"
    Copy-Item -Path (Join-Path (Resolve-Path $RepoPath) '*') -Destination $ws -Recurse -Force
    Get-ChildItem -Path $ws -Directory -Filter '.git' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
  }
  else {
    Info "No -RepoPath: generating a $series fixture"
    New-Fixture -Series $series -Dir $ws -RepoName $laneRepo
  }

  $ctx = @{
    inputs = @{
      version = $Version; tag = $laneTag; channel = $Channel; newVersion = $NewVersion
      applyVersionPrefix = ([string]$ApplyVersionPrefix).ToLower()
      essentialsMajor = $EssentialsMajor; packageStyle = $PackageStyle
      packagePrefix = $lanePrefix; bypass = $laneBypass; devToolsVersion = ''
    }
    env    = @{ BUILD_TYPE = $(if ($Channel -eq '') { 'Release' } else { 'Debug' }) }
    github = @{ repository = "$Owner/$laneRepo"; repository_owner = $Owner }
    steps  = @{}
    effectiveVersion = $Version
    effectiveTag     = $laneTag
    # Static, lane-scoped values referenced from the step input scriptblocks.
    # (Those blocks are NOT closures, so they may only read $ctx.)
    lane = @{
      series       = $series
      slnFilter    = $(if ($series -eq '3series') { '*.3Series.sln' } else { '*.4Series.sln' })
      csprojFilter = '*.4Series.csproj'
      relArtifacts = $(if ($series -eq '3series') { 'output\*.*(cpz|cplz|clz)' } else { 'output\**\*.*(cpz|cplz)' })
    }
  }
  $sharedEnv = @{
    GITHUB_REPOSITORY       = "$Owner/$laneRepo"
    GITHUB_REPOSITORY_OWNER = $Owner
    GH_REPO_VISIBILITY      = $Visibility
    BUILD_TYPE              = $ctx.env.BUILD_TYPE
  }

  $compiled = $false      # did a real compile run this session?
  $rows = [System.Collections.Generic.List[pscustomobject]]::new()
  $failed = $false

  foreach ($step in (Get-Lane -Name $Name -ctx $ctx)) {
    $inputs = & $step.inputs
    $label  = $step.name
    $cls    = $step.class

    # class -> action
    $doRun = switch ($cls) {
      'offline'     { $true }
      'needs-build' { $compiled }
      'build'       { [bool]$RunBuild }
      'docker'      { [bool]$RunDocker }
      default       { $false }   # dry-always / dry-always-gate
    }

    if (-not $doRun) {
      $reason = switch ($cls) {
        'needs-build'     { 'no compile this run' }
        'build'           { 'pass -RunBuild to execute' }
        'docker'          { 'pass -RunDocker to execute' }
        'dry-always-gate' { 'publish step — never run locally' }
        default           { 'publish/release step — never run locally' }
      }
      Warn "  ~ $label  [DRY: $reason]"
      foreach ($k in ($inputs.Keys | Sort-Object)) { Write-Host "      $k = $($inputs[$k])" -ForegroundColor DarkGray }
      if ($cls -eq 'dry-always-gate') {
        $gate = ($Owner.ToLower() -eq 'pepperdash') -and ($Visibility -eq 'public')
        if ($gate) { Ok "      gate: owner=$Owner visibility=$Visibility  => WOULD publish to nuget.org" }
        else { Warn "      gate: owner=$Owner visibility=$Visibility  => SKIP (fail-closed)" }
      }
      $rows.Add([pscustomobject]@{ Step = $label; Result = 'dry'; Detail = $reason })
      continue
    }

    $scriptPath = Join-Path $ActionsRoot "$($step.action)/scripts/$($step.script)"
    if (-not (Test-Path $scriptPath)) { Bad "  ! $label  (missing $scriptPath)"; $failed = $true; break }

    $r = Invoke-Step -ScriptPath $scriptPath -Inputs $inputs -ExtraEnv $sharedEnv -Workspace $ws -GhDir $gh

    # merge env forward (process + ctx + shared)
    foreach ($k in $r.EnvVars.Keys) { $ctx.env[$k] = $r.EnvVars[$k]; $sharedEnv[$k] = $r.EnvVars[$k] }
    if ($step.id) { $ctx.steps[$step.id] = $r.Outputs }

    if ($step.id -eq 'prefix' -and $r.ExitCode -eq 0) {
      $ctx.effectiveVersion = $r.Outputs['version']
      $ctx.effectiveTag     = $r.Outputs['tag']
    }
    if ($step.action -in @('dotnet-build', 'docker-build-3series', 'pack-nuget') -and $r.ExitCode -eq 0) {
      $compiled = $true
    }

    if ($r.ExitCode -eq 0) {
      Ok "  + $label"
      foreach ($k in ($r.Outputs.Keys | Sort-Object)) { Write-Host "      out: $k = $($r.Outputs[$k])" -ForegroundColor DarkGray }
      foreach ($k in ($r.EnvVars.Keys | Sort-Object)) { Write-Host "      env: $k = $($r.EnvVars[$k])" -ForegroundColor DarkGray }
      $rows.Add([pscustomobject]@{ Step = $label; Result = 'ok'; Detail = (($r.Outputs.Keys | Sort-Object) -join ',') })
    }
    elseif ($step.softfail) {
      Warn "  ! $label  (exit $($r.ExitCode); continue-on-error in the workflow)"
      if ($r.Stderr.Trim()) { Write-Host "      $($r.Stderr.Trim().Split("`n")[-1])" -ForegroundColor DarkYellow }
      $rows.Add([pscustomobject]@{ Step = $label; Result = 'softfail'; Detail = "exit $($r.ExitCode)" })
    }
    else {
      Bad "  x $label  (exit $($r.ExitCode))"
      if ($r.Stdout.Trim()) { Write-Host $r.Stdout.Trim() -ForegroundColor DarkGray }
      if ($r.Stderr.Trim()) { Write-Host $r.Stderr.Trim() -ForegroundColor Red }
      $rows.Add([pscustomobject]@{ Step = $label; Result = 'FAIL'; Detail = "exit $($r.ExitCode)" })
      $failed = $true
      break
    }
  }

  Write-Host ''
  $rows | Format-Table -AutoSize | Out-String | Write-Host
  Write-Host "  step summary : $(Join-Path $gh 'summary')"
  Write-Host "  workspace    : $ws"
  if ($KeepWorkspace) { Warn "  (kept — remove $work when done)" }
  else { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }

  if ($failed) { Bad "LANE FAILED: $Name"; return $false }
  Ok "LANE OK: $Name"
  return $true
}

# --------------------------------------------------------------------------
$lanes = if ($All) {
  'plugin-3series-net35', 'plugin-4series-net472', 'plugin-4series-net8',
  'essentials-3series-net35', 'essentials-4series-net472', 'essentials-4series-net8'
} else { , $Workflow }

$allOk = $true
foreach ($l in $lanes) { if (-not (Invoke-Lane -Name $l)) { $allOk = $false } }

Write-Host ''
if ($allOk) { Ok 'ALL LANES PASSED (offline steps).'; exit 0 }
Bad 'ONE OR MORE LANES FAILED.'; exit 1
