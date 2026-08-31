#requires -Version 7.0
<#
  Resolves the path to the built plugin assembly.

  Inputs (env): INPUT_ASSEMBLY_NAME (optional), INPUT_BUILD_TYPE (default Release)
  Outputs: path
#>
. "$PSScriptRoot/../../_common/action.ps1"

$name = Get-ActionInput -Name 'assembly-name'
$buildType = Get-ActionInput -Name 'build-type' -Default 'Release'
$root = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }

$dlls = Get-ChildItem -Path $root -Recurse -Filter *.dll -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "[\\/]bin[\\/]$buildType" -and $_.FullName -notmatch '[\\/]packages[\\/]' }

$pick = $null
if ($name -ne '') { $pick = $dlls | Where-Object { $_.BaseName -eq $name } | Select-Object -First 1 }
if ($null -eq $pick) { $pick = $dlls | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }

if ($null -eq $pick) {
  Stop-Action "Could not find a built plugin .dll under a bin/$buildType path."
}

Add-ActionOutput -Name 'path' -Value $pick.FullName
Write-Host "Assembly: $($pick.FullName)"
