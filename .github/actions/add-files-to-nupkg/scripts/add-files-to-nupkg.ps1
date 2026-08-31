#requires -Version 7.0
<#
  Injects a folder of files into every .nupkg under a directory, at a target path
  inside the package.

  Inputs (env): INPUT_SOURCE_DIR (required), INPUT_TARGET_PATH (default 'schemas'),
    INPUT_NUPKG_DIR (default 'output'), INPUT_PATTERN (default '*'),
    INPUT_REQUIRED (default 'false')
#>
. "$PSScriptRoot/../../_common/action.ps1"

$srcRel   = Get-ActionInput -Name 'source-dir' -Required
$target   = (Get-ActionInput -Name 'target-path' -Default 'schemas').Trim('/').Trim('\')
$nupkgRel = Get-ActionInput -Name 'nupkg-dir' -Default 'output'
$pattern  = Get-ActionInput -Name 'pattern' -Default '*'
$required = Get-ActionInput -Name 'required' -Default 'false'

$root = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }

Add-ActionSummary "## Add files to nupkg`n"

$srcDir = Join-Path $root $srcRel
$files = @()
if (Test-Path $srcDir) { $files = @(Get-ChildItem -Path $srcDir -Filter $pattern -File) }
if ($files.Count -eq 0) {
  $msg = "No files matching '$pattern' in $srcRel."
  if ($required -eq 'true') { Stop-Action $msg }
  Add-ActionSummary "$msg Nothing to inject.`n"
  exit 0
}

$nupkgs = @(Get-ChildItem -Path (Join-Path $root $nupkgRel) -Recurse -Filter *.nupkg -ErrorAction SilentlyContinue)
if ($nupkgs.Count -eq 0) {
  $msg = "No .nupkg found under $nupkgRel."
  if ($required -eq 'true') { Stop-Action $msg }
  Add-ActionSummary "$msg`n"
  exit 0
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

foreach ($nupkg in $nupkgs) {
  $zip = [System.IO.Compression.ZipFile]::Open($nupkg.FullName, [System.IO.Compression.ZipArchiveMode]::Update)
  try {
    foreach ($f in $files) {
      $entryName = "$target/$($f.Name)"
      $existing = $zip.GetEntry($entryName)
      if ($existing) { $existing.Delete() }
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $entryName) | Out-Null
    }
  } finally {
    $zip.Dispose()
  }
  Add-ActionSummary "- $($nupkg.Name): added $($files.Count) file(s) under ``$target/``.`n"
}
