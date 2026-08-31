BeforeAll {
  . "$PSScriptRoot/_helpers.ps1"
  $script:ScriptPath = Get-ActionScript -Action 'get-plugin-metadata' -Script 'get-plugin-metadata.ps1'

  function New-PluginFixture {
    param([string[]]$Files)  # array of "relpath|||content"
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("meta-" + [guid]::NewGuid().ToString('n'))
    foreach ($f in $Files) {
      $parts = $f -split '\|\|\|', 2
      $path = Join-Path $work $parts[0]
      New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
      Set-Content -Path $path -Value $parts[1]
    }
    return $work
  }
}

Describe 'get-plugin-metadata' {
  It 'extracts TypeNames from "new List<string> {...}" (no parens)' {
    $cs = @'
namespace X { public class FooFactory : EssentialsPluginDeviceFactory<Foo> {
  public FooFactory() { TypeNames = new List<string> {"lgDisplay", "lg"}; MinimumEssentialsFrameworkVersion = "1.8.0"; }
}}
'@
    $work = New-PluginFixture -Files @("src/FooFactory.cs|||$cs")
    $r = Invoke-ActionScript -Path $ScriptPath -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.ExitCode | Should -Be 0
    $r.Outputs['is-csharp-plugin'] | Should -Be 'true'
    $r.Outputs['type-names'] | Should -Be 'lgDisplay lg'
    $r.Outputs['type-names-list'] | Should -Be 'lgDisplay, lg'
    $r.Outputs['min-framework-version'] | Should -Be '1.8.0'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'extracts TypeNames from "new List<string>() { ... }" (parens, odd spacing)' {
    $cs = @'
namespace X { public class BarFactory : EssentialsPluginDeviceFactory<Bar> {
  public BarFactory() {
      TypeNames = new List<string>()   {   "barThing"   } ;
  }
}}
'@
    $work = New-PluginFixture -Files @("src/BarFactory.cs|||$cs")
    $r = Invoke-ActionScript -Path $ScriptPath -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.Outputs['type-names'] | Should -Be 'barThing'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'dedupes across multiple factory files and picks the highest min framework version' {
    $a = 'namespace X { class AFactory : EssentialsPluginDeviceFactory<A> { public AFactory(){ TypeNames = new List<string>{"shared","a"}; MinimumEssentialsFrameworkVersion = "1.8.0"; } } }'
    $b = 'namespace X { class BFactory : EssentialsPluginDeviceFactory<B> { public BFactory(){ TypeNames = new List<string>{"shared","b"}; MinimumEssentialsFrameworkVersion = "2.16.0"; } } }'
    $work = New-PluginFixture -Files @("src/AFactory.cs|||$a", "src/BFactory.cs|||$b")
    $r = Invoke-ActionScript -Path $ScriptPath -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    ($r.Outputs['type-names'] -split ' ' | Sort-Object) | Should -Be @('a','b','shared')
    $r.Outputs['min-framework-version'] | Should -Be '2.16.0'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'ignores a factory with no TypeNames and .cs under obj/' {
    $noNames = 'namespace X { class CFactory : EssentialsPluginDeviceFactory<C> { public CFactory(){ } } }'
    $inObj   = 'namespace X { class DFactory : EssentialsPluginDeviceFactory<D> { public DFactory(){ TypeNames = new List<string>{"shouldNotAppear"}; } } }'
    $work = New-PluginFixture -Files @("src/CFactory.cs|||$noNames", "obj/Debug/DFactory.cs|||$inObj")
    $r = Invoke-ActionScript -Path $ScriptPath -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.Outputs['is-csharp-plugin'] | Should -Be 'false'
    $r.Outputs['type-names'] | Should -Be ''
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'non-plugin repo -> is-csharp-plugin false, empty values, exit 0' {
    $work = New-PluginFixture -Files @('src/Program.cs|||class Program { static void Main(){} }')
    $r = Invoke-ActionScript -Path $ScriptPath -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.ExitCode | Should -Be 0
    $r.Outputs['is-csharp-plugin'] | Should -Be 'false'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}
