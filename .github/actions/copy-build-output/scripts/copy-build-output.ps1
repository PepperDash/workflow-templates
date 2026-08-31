#requires -Version 7.0
<#
  Collects build artifacts (.cpz/.clz/.cplz + matching .dll) from the solution
  tree into ./output and renames them to embed the version.

  Inputs (env INPUT_*): version, build-type, package, extensions, include-dll,
    bin-filter (bin|bin-config), rename-mode (all|essentials), copy-nuspec
#>
. "$PSScriptRoot/../../_common/action.ps1"

$version    = Get-ActionInput -Name 'version' -Required
$buildType  = Get-ActionInput -Name 'build-type' -Required
$package    = Get-ActionInput -Name 'package'
$extInput   = Get-ActionInput -Name 'extensions' -Default '.cpz .clz .cplz'
$includeDll = Get-ActionInput -Name 'include-dll' -Default 'false'
$binFilter  = Get-ActionInput -Name 'bin-filter' -Default 'bin-config'
$renameMode = Get-ActionInput -Name 'rename-mode' -Default 'all'
$copyNuspec = Get-ActionInput -Name 'copy-nuspec' -Default 'false'

$root = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }
$sourceDir = $root
$destinationDir = Join-Path $root 'output'

Add-ActionSummary "## Copy build output files`n"

$validExtensions = $extInput.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
if ($validExtensions.Count -eq 0) { Stop-Action "No artifact extensions supplied." }
if ($includeDll -eq 'true') { $validExtensions += '.dll' }
$includePatterns = $validExtensions | ForEach-Object { "*$_" }

$binRegex = if ($binFilter -eq 'bin-config') { "[\\/]bin[\\/]$buildType" } else { "[\\/]bin[\\/]" }
Write-Host "Extensions: $($validExtensions -join ', ')  Bin filter: $binRegex  Version: $version"

if (Test-Path -Path $destinationDir) {
  Get-ChildItem -Path $destinationDir -Recurse | Remove-Item -Force -Recurse
} else {
  New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
}

if ($copyNuspec -eq 'true') {
  Get-ChildItem -Path $sourceDir -Recurse -Filter *.nuspec -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Copying $($_.Name) to repo root"
    Copy-Item $_.FullName -Destination $root -Force
    Add-ActionEnv -Name 'NUSPEC_FILE' -Value $_.BaseName
  }
}

$filesToCopy = Get-ChildItem -Path $sourceDir -Recurse -Include $includePatterns -ErrorAction SilentlyContinue | Where-Object {
  $_.FullName -notmatch '[\\/]packages[\\/]' -and $_.FullName -match $binRegex
}

if (@($filesToCopy).Count -eq 0) {
  Stop-Action "No build artifacts ($($validExtensions -join ', ')) found under a path matching '$binRegex'. Did the build succeed?"
}

$allFilesToCopy = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($file in $filesToCopy) {
  $allFilesToCopy.Add($file)
  Get-ChildItem -Path $sourceDir -Recurse -ErrorAction SilentlyContinue | Where-Object {
    ($_.BaseName -eq $file.BaseName -or ($package -ne '' -and $_.BaseName -eq $package)) -and $_.Extension -eq '.dll'
  } | ForEach-Object { $allFilesToCopy.Add($_) }
}
$unique = $allFilesToCopy | Sort-Object FullName -Unique

Write-Host "Copying $($unique.Count) file(s) to $destinationDir"
$unique | ForEach-Object { Copy-Item $_.FullName -Destination $destinationDir -Force }

# Which extensions get renamed. In "essentials" mode the DLLs keep their names.
$renameExtensions = [System.Collections.Generic.List[string]]::new()
$validExtensions | ForEach-Object { $renameExtensions.Add($_) }
if ($renameMode -eq 'all' -and $renameExtensions -notcontains '.dll') { $renameExtensions.Add('.dll') }
if ($renameMode -eq 'essentials') { $renameExtensions = $renameExtensions | Where-Object { $_ -ne '.dll' } }

Get-ChildItem -Path $destinationDir | Where-Object { $renameExtensions -contains $_.Extension } | ForEach-Object {
  $oldName = $_.Name; $baseName = $_.BaseName; $extension = $_.Extension
  if ($renameMode -eq 'essentials') {
    if ($baseName -match 'PepperDashEssentials' -or $baseName -match 'PepperDashCore' -or $baseName -match 'PepperDash_Core') {
      $newName = ("$baseName.$version$extension" -replace '\.3Series', '')
      Write-Host "- '$oldName' -> '$newName'"
      Rename-Item -Path $_.FullName -NewName $newName -Force
    }
  }
  else {
    if ($baseName -match '(.+)\.3[Ss]eries$') {
      $newName = "$($Matches[1]).$version.3Series$extension"
    } else {
      $newName = "$baseName.$version$extension"
    }
    Write-Host "- '$oldName' -> '$newName'"
    Rename-Item -Path $_.FullName -NewName $newName -Force
  }
}

$final = Get-ChildItem -Path $destinationDir
if (@($final).Count -eq 0) { Stop-Action "Nothing was copied to $destinationDir." }
$final | ForEach-Object { Add-ActionSummary "- $($_.Name)`n" }
