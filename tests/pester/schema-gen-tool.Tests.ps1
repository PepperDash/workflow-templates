# Integration test for the bundled SchemaGen tool: builds a fixture net8 config
# library and runs the tool against it. Skipped when the .NET SDK is unavailable.

BeforeDiscovery {
  $script:HasDotnet = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)
}

Describe 'SchemaGen tool' -Skip:(-not $HasDotnet) {
  BeforeAll {
    . "$PSScriptRoot/_helpers.ps1"
    $script:Proj = Join-Path $RepoRoot '.github/actions/generate-config-schema/schema-gen/SchemaGen.csproj'

    # Fixture config library.
    $script:Fx = Join-Path ([System.IO.Path]::GetTempPath()) ("sgfx-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $Fx | Out-Null
    @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup><PackageReference Include="Newtonsoft.Json" Version="13.0.3" /></ItemGroup>
</Project>
'@ | Set-Content (Join-Path $Fx 'Fx.csproj')
    @'
using System.Collections.Generic;
using Newtonsoft.Json;
namespace Fx {
  public class SampleConfig {
    [JsonProperty("id")] public string Id { get; set; }
    [JsonProperty("volumeUpperLimit")] public int VolumeUpperLimit { get; set; }
    [JsonProperty("friendlyNames")] public List<FriendlyName> FriendlyNames { get; set; }
  }
  public class FriendlyName {
    [JsonProperty("inputKey")] public string InputKey { get; set; }
    [JsonProperty("hideInput")] public bool HideInput { get; set; }
  }
}
'@ | Set-Content (Join-Path $Fx 'Config.cs')

    dotnet build (Join-Path $Fx 'Fx.csproj') -c Release --nologo 2>&1 | Out-Null
    $script:FxDll = Get-ChildItem -Path $Fx -Recurse -Filter Fx.dll | Select-Object -First 1 -ExpandProperty FullName
  }

  AfterAll { if ($Fx) { Remove-Item $Fx -Recurse -Force -ErrorAction SilentlyContinue } }

  It 'the fixture library built' { $FxDll | Should -Not -BeNullOrEmpty }

  It 'generates a schema that respects [JsonProperty] names and nests types' {
    $out = Join-Path ([System.IO.Path]::GetTempPath()) ("sgout-" + [guid]::NewGuid().ToString('n'))
    dotnet run --project $Proj -c Release -- --assembly $FxDll --types 'SampleConfig' --out $out 2>&1 | Out-Null
    $LASTEXITCODE | Should -Be 0

    $file = Join-Path $out 'SampleConfig.schema.json'
    Test-Path $file | Should -BeTrue
    $schema = Get-Content -Raw $file | ConvertFrom-Json
    $schema.type | Should -Be 'object'
    $schema.properties.id | Should -Not -BeNullOrEmpty            # JsonProperty name, not "Id"
    $schema.properties.volumeUpperLimit | Should -Not -BeNullOrEmpty
    $schema.definitions.FriendlyName | Should -Not -BeNullOrEmpty # nested -> $ref/definitions
    Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'exits 2 for an unknown type name' {
    $out = Join-Path ([System.IO.Path]::GetTempPath()) ("sgout-" + [guid]::NewGuid().ToString('n'))
    dotnet run --project $Proj -c Release -- --assembly $FxDll --types 'NoSuchConfig' --out $out 2>&1 | Out-Null
    $LASTEXITCODE | Should -Be 2
    Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
  }
}
