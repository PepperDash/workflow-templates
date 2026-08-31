#requires -Version 7.0
<#
  Runs `nuget pack` for a nuspec unless it is the EssentialsPluginTemplate.

  Inputs (env): INPUT_NUSPEC_FILE (required), INPUT_VERSION (required),
                INPUT_OUTPUT_DIR (default 'output')
#>
. "$PSScriptRoot/../../_common/action.ps1"

$nuspec  = Get-ActionInput -Name 'nuspec-file'
$version = Get-ActionInput -Name 'version' -Required
$outDir  = Get-ActionInput -Name 'output-dir' -Default 'output'

Add-ActionSummary "## Pack NuGet Package`n"

if ([string]::IsNullOrWhiteSpace($nuspec)) {
  Stop-Action "No nuspec file name supplied. Did create-nuspec run and set an output?"
}
if ($nuspec -like '*EssentialsPluginTemplate*') {
  Add-ActionSummary "Skipped — template repo (``$nuspec``).`n"
  Write-Host "Template repo; skipping nuget pack."
  exit 0
}

$filePath = ".\$nuspec.nuspec"
if (-not (Test-Path -Path $filePath)) {
  Stop-Action "NuGet nuspec file '$filePath' not found. Check that the build produced it."
}

nuget pack $filePath -version $version -OutputDirectory ".\$outDir"
if ($LASTEXITCODE -ne 0) {
  Stop-Action "nuget pack exited with code $LASTEXITCODE."
}

$pkgs = Get-ChildItem -Path ".\$outDir" -Recurse -Filter *.nupkg -ErrorAction SilentlyContinue
if (@($pkgs).Count -eq 0) {
  Stop-Action "nuget pack reported success but no .nupkg was produced."
}
$pkgs | ForEach-Object { Add-ActionSummary "- $($_.Name)`n" }
