#requires -Version 7.0
<#
  Rewrites AssemblyVersion / AssemblyInformationalVersion in every AssemblyInfo.cs
  and AssemblyInfo.vb under the workspace.

  Inputs (env): INPUT_VERSION (required)
#>
. "$PSScriptRoot/../../_common/action.ps1"

$version = Get-ActionInput -Name 'version' -Required
$root = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }

Add-ActionSummary "## Update Assembly Info`n"

$r = [regex]::Match($version, '\d+\.\d+\.\d+.*')
if (-not $r.Success) {
  Stop-Action "Input version '$version' does not match x.y.z format."
}

$baseVersion = [regex]::Match($version, '(\d+\.\d+\.\d+).*').Groups[1].Value
$newAsmVer  = 'AssemblyVersion("' + $baseVersion + '.*")'
$newInfoVer = 'AssemblyInformationalVersion("' + $version + '")'

$count = 0
foreach ($name in 'AssemblyInfo.cs', 'AssemblyInfo.vb') {
  Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name } | ForEach-Object {
    $count++
    Write-Host "  $($_.FullName)"
    $tmp = $_.FullName + '.tmp'
    Get-Content $_.FullName |
      ForEach-Object { $_ -replace 'AssemblyVersion\(".*"\)', $newAsmVer } |
      ForEach-Object { $_ -replace 'AssemblyInformationalVersion\(".*"\)', $newInfoVer } | Set-Content $tmp
    Move-Item $tmp $_.FullName -Force
  }
}

if ($count -eq 0) {
  Add-ActionSummary "⚠️ No AssemblyInfo.cs / AssemblyInfo.vb files found.`n"
} else {
  Add-ActionSummary "- Updated $count AssemblyInfo file(s) to ``$version``.`n"
}
