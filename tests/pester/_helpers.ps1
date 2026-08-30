# Test helpers: run a composite-action script in isolation and capture what it
# would have handed back to GitHub Actions.

$script:RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path

function Get-ActionScript {
  param([Parameter(Mandatory)][string]$Action, [Parameter(Mandatory)][string]$Script)
  Join-Path $script:RepoRoot ".github/actions/$Action/scripts/$Script"
}

<#
.SYNOPSIS
  Invoke an action script with a set of inputs and a scratch workspace.
.OUTPUTS
  [pscustomobject] with:
    ExitCode  int
    Outputs   hashtable  (parsed $GITHUB_OUTPUT: name -> value)
    EnvVars   hashtable  (parsed $GITHUB_ENV)
    Summary   string     (full $GITHUB_STEP_SUMMARY text)
    Stdout    string
    Stderr    string
    WorkDir   string     (the scratch dir the script ran in)
#>
function Invoke-ActionScript {
  param(
    [Parameter(Mandatory)][string]$Path,
    [hashtable]$Inputs = @{},
    [hashtable]$Env = @{},
    [string]$WorkDir,
    [switch]$KeepWorkDir
  )

  if (-not $WorkDir) {
    $WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("act-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
  }
  $outFile = Join-Path $WorkDir '_gh_output'
  $envFile = Join-Path $WorkDir '_gh_env'
  $sumFile = Join-Path $WorkDir '_gh_summary'
  '' | Set-Content $outFile; '' | Set-Content $envFile; '' | Set-Content $sumFile

  $envBlock = [System.Collections.Generic.List[string]]::new()
  $envBlock.Add("`$env:GITHUB_OUTPUT='$outFile'")
  $envBlock.Add("`$env:GITHUB_ENV='$envFile'")
  $envBlock.Add("`$env:GITHUB_STEP_SUMMARY='$sumFile'")
  foreach ($k in $Inputs.Keys) {
    $name = "INPUT_" + ($k.ToUpper() -replace '[-\s]', '_')
    $val = ($Inputs[$k] -replace "'", "''")
    $envBlock.Add("`$env:$name='$val'")
  }
  foreach ($k in $Env.Keys) {
    $val = ($Env[$k] -replace "'", "''")
    $envBlock.Add("`$env:$k='$val'")
  }

  $isBash = $Path -like '*.sh'
  $invoke = if ($isBash) { "& bash '$Path'" } else { "& '$Path'" }
  $runner = Join-Path $WorkDir '_run.ps1'
  @"
$($envBlock -join "`n")
Set-Location '$WorkDir'
$invoke
exit `$LASTEXITCODE
"@ | Set-Content $runner

  $stdout = Join-Path $WorkDir '_stdout'
  $stderr = Join-Path $WorkDir '_stderr'
  $p = Start-Process -FilePath (Get-Process -Id $PID).Path `
    -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $runner) `
    -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr

  $outputs = @{}
  foreach ($line in (Get-Content $outFile -ErrorAction SilentlyContinue)) {
    if ($line -match '^(?<k>[^=]+)=(?<v>.*)$') { $outputs[$Matches.k] = $Matches.v }
  }
  $envVars = @{}
  foreach ($line in (Get-Content $envFile -ErrorAction SilentlyContinue)) {
    if ($line -match '^(?<k>[^=]+)=(?<v>.*)$') { $envVars[$Matches.k] = $Matches.v }
  }

  $result = [pscustomobject]@{
    ExitCode = $p.ExitCode
    Outputs  = $outputs
    EnvVars  = $envVars
    Summary  = (Get-Content $sumFile -Raw -ErrorAction SilentlyContinue) ?? ''
    Stdout   = (Get-Content $stdout -Raw -ErrorAction SilentlyContinue) ?? ''
    Stderr   = (Get-Content $stderr -Raw -ErrorAction SilentlyContinue) ?? ''
    WorkDir  = $WorkDir
  }
  if (-not $KeepWorkDir) {
    Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  return $result
}

function New-FixtureCsproj {
  param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$EssentialsVersion, [string]$Name = 'Plugin.4Series.csproj')
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  @"
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="PepperDashEssentials" Version="$EssentialsVersion" />
  </ItemGroup>
</Project>
"@ | Set-Content (Join-Path $Dir $Name)
}
