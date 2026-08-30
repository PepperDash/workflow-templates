#requires -Version 7.0
<#
  Verifies the produced .nupkg id matches
  <expected-prefix><repo-without-'epi-' with '-' -> '.'> (case-insensitive).

  Inputs (env):
    INPUT_BYPASS            'true' to skip
    INPUT_OUTPUT_DIR        default 'output'
    INPUT_EXPECTED_PREFIX   default 'PepperDash.Essentials.Plugins.'
    GITHUB_REPOSITORY       'owner/repo'
#>
. "$PSScriptRoot/../../_common/action.ps1"

$bypass  = Get-ActionInput -Name 'bypass' -Default 'false'
$outDir  = Get-ActionInput -Name 'output-dir' -Default 'output'
$prefix  = Get-ActionInput -Name 'expected-prefix' -Default 'PepperDash.Essentials.Plugins.'

Add-ActionSummary "## Check Package Name`n"

if ($bypass -eq 'true') {
  Add-ActionSummary "Bypassed (bypass = true).`n"
  Write-Host "Bypassing package name check."
  exit 0
}

$repoName = ($env:GITHUB_REPOSITORY ?? '').Split('/')[-1]
if ([string]::IsNullOrWhiteSpace($repoName)) { Stop-Action "GITHUB_REPOSITORY is not set." }

$expected = $prefix + ($repoName -replace 'epi-', '').Replace('-', '.')
Write-Host "Repository Name: $repoName"
Write-Host "Expected Package Name: $expected"

$packageFile = Get-ChildItem -Path (Join-Path '.' $outDir) -Filter *.nupkg -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $packageFile) {
  Stop-Action "No NuGet package found in .\$outDir."
}

$actual = [System.IO.Path]::GetFileNameWithoutExtension($packageFile.FullName) -replace '\.\d+.*$'
if ($actual.ToLower() -ne $expected.ToLower()) {
  Stop-Action "Package name mismatch: expected '$expected' but found '$actual'."
}

Add-ActionSummary "- OK: ``$actual```n"
