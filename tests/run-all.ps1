#requires -Version 7.0
<#
.SYNOPSIS
  Runs the full local test suite for the reusable workflows/actions:
    1. Pester unit tests for every composite-action script + workflow structure
    2. dotnet test / build for the SchemaGen tool
    3. actionlint over the workflow YAML (if actionlint is on PATH)

  Nothing here touches GitHub or publishes anything.

.EXAMPLE
  pwsh tests/run-all.ps1
  pwsh tests/run-all.ps1 -SkipDotnet -SkipActionlint
#>
[CmdletBinding()]
param(
  [switch]$SkipPester,
  [switch]$SkipDotnet,
  [switch]$SkipActionlint
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
$failures = [System.Collections.Generic.List[string]]::new()

function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

if (-not $SkipPester) {
  Section 'Pester'
  if (-not (Get-Module -ListAvailable Pester | Where-Object Version -ge '5.0.0')) {
    Write-Host 'Installing Pester 5...'
    Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
  }
  Import-Module Pester -MinimumVersion 5.0.0
  $cfg = New-PesterConfiguration
  $cfg.Run.Path = Join-Path $PSScriptRoot 'pester'
  $cfg.Run.PassThru = $true
  $cfg.Output.Verbosity = 'Detailed'
  $cfg.TestResult.Enabled = $true
  $cfg.TestResult.OutputPath = Join-Path $repoRoot 'test-results.xml'
  $result = Invoke-Pester -Configuration $cfg
  if ($result.FailedCount -gt 0) { $failures.Add("Pester: $($result.FailedCount) failed") }
}

if (-not $SkipDotnet) {
  Section 'SchemaGen (dotnet build)'
  if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    $proj = Join-Path $repoRoot '.github/actions/generate-config-schema/schema-gen/SchemaGen.csproj'
    dotnet build $proj -c Release --nologo
    if ($LASTEXITCODE -ne 0) { $failures.Add('SchemaGen build failed') }
    # Behavioural coverage lives in tests/pester/schema-gen-tool.Tests.ps1
    # (runs the built tool against a fixture library).
  } else {
    Write-Warning 'dotnet not found; skipping SchemaGen build (its Pester test self-skips too).'
  }
}

if (-not $SkipActionlint) {
  Section 'actionlint'
  if (Get-Command actionlint -ErrorAction SilentlyContinue) {
    Push-Location $repoRoot
    try {
      actionlint
      if ($LASTEXITCODE -ne 0) { $failures.Add('actionlint reported problems') }
    } finally { Pop-Location }
  } else {
    Write-Warning 'actionlint not found; skipping. (brew install actionlint)'
  }
}

Section 'Result'
if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Host "FAIL  $_" -ForegroundColor Red }
  exit 1
}
Write-Host 'All checks passed.' -ForegroundColor Green
