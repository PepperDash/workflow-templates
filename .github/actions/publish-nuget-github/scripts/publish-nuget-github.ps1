#requires -Version 7.0
<#
  Pushes every .nupkg in the output dir to the org GitHub Packages feed.

  Inputs (env): INPUT_GITHUB_TOKEN (required), INPUT_OWNER, INPUT_OUTPUT_DIR
#>
. "$PSScriptRoot/../../_common/action.ps1"

$token  = Get-ActionInput -Name 'github-token' -Required
$owner  = Get-ActionInput -Name 'owner' -Default $env:GITHUB_REPOSITORY_OWNER
$outDir = Get-ActionInput -Name 'output-dir' -Default 'output'

Add-ActionSummary "## Publish`n### GitHub Feed`n"

$source = "https://nuget.pkg.github.com/$owner/index.json"
$nupkgFiles = Get-ChildItem -Path ".\$outDir" -Recurse -Filter *.nupkg -ErrorAction SilentlyContinue
if (@($nupkgFiles).Count -eq 0) {
  Stop-Action "No .nupkg files found in .\$outDir."
}

if (-not (nuget sources list | Select-String -Pattern ([regex]::Escape($source)))) {
  nuget sources add -name github -source $source -username pepperdash -password $token
}

$failed = @()
foreach ($pkg in $nupkgFiles) {
  Write-Host "Pushing $($pkg.Name) to GitHub feed..."
  nuget push $pkg.FullName -source $source -apikey $token -SkipDuplicate
  if ($LASTEXITCODE -ne 0) {
    $failed += $pkg.Name
    Add-ActionSummary "❌ Failed to push $($pkg.Name) (exit $LASTEXITCODE)`n"
  } else {
    Add-ActionSummary "- Pushed $($pkg.Name)`n"
  }
}
if ($failed.Count -gt 0) {
  Stop-Action "Failed to push: $($failed -join ', ')"
}
