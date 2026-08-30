#requires -Version 7.0
<#
  Restores packages.config and builds a 3-Series solution with the
  pepperdash/sspbuilder image. Docker Hub login is done in action.yml.

  Inputs (env INPUT_*): solution-path, build-type, restore-packages
#>
. "$PSScriptRoot/../../_common/action.ps1"

$solutionPath = Get-ActionInput -Name 'solution-path' -Required
$buildType    = Get-ActionInput -Name 'build-type' -Required
$restore      = Get-ActionInput -Name 'restore-packages' -Default 'true'

if ($restore -eq 'true') {
  if (-not (Test-Path -Path .\packages.config)) {
    Add-ActionSummary "## Restore NuGet Packages`n⚠️ No packages.config at the repo root; skipping.`n"
  } else {
    nuget install .\packages.config -OutputDirectory .\packages -ExcludeVersion
    if ($LASTEXITCODE -ne 0) { Stop-Action "nuget install exited with code $LASTEXITCODE." }
  }
}

Add-ActionSummary "## Build Solution (3-Series / sspbuilder)`n"
Write-Host "Building $solutionPath ($buildType)"
docker run --rm --mount "type=bind,source=$($env:GITHUB_WORKSPACE),target=c:\project" pepperdash/sspbuilder:latest c:\cihelpers\vsidebuild.exe -Solution "c:\project\$solutionPath" -BuildSolutionConfiguration $buildType
if ($LASTEXITCODE -ne 0) {
  Stop-Action "**BUILD FAILED** — sspbuilder exited with code $LASTEXITCODE."
}
Add-ActionSummary "**BUILD SUCCESS** — $buildType`n"
