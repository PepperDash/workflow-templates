#requires -Version 7.0
<#
  Runs the bundled NJsonSchema tool against the resolved assembly + discovered
  types and reports how many schema files were produced.

  Inputs (env):
    INPUT_ASSEMBLY_PATH   path to the plugin dll        (required)
    INPUT_TYPES           ";"-joined config type names  (required)
    INPUT_OUTPUT_DIR      workspace-relative out dir     (default output/schemas)
    ACTION_PATH           the composite action's path    (required)
  Outputs: schema-count
#>
. "$PSScriptRoot/../../_common/action.ps1"

$assembly = Get-ActionInput -Name 'assembly-path' -Required
$types    = Get-ActionInput -Name 'types' -Required
$outRel   = Get-ActionInput -Name 'output-dir' -Default 'output/schemas'
$actionPath = if ($env:ACTION_PATH) { $env:ACTION_PATH } else { (Resolve-Path "$PSScriptRoot/..").Path }

$root = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }
$outDir = Join-Path $root $outRel
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$proj = Join-Path $actionPath 'schema-gen/SchemaGen.csproj'
dotnet run --project $proj -c Release -- --assembly $assembly --types $types --out $outDir
$exit = $LASTEXITCODE

$count = (Get-ChildItem -Path $outDir -Filter *.schema.json -ErrorAction SilentlyContinue | Measure-Object).Count
Add-ActionOutput -Name 'schema-count' -Value $count

if ($exit -ne 0 -and $count -eq 0) {
  Stop-Action "Schema generation failed (exit $exit) and produced no files."
}
if ($exit -ne 0) {
  Add-ActionSummary "⚠️ Schema generator exited $exit but $count file(s) were written.`n"
}
