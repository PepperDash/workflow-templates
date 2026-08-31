BeforeAll {
  . "$PSScriptRoot/_helpers.ps1"
  $script:Discover = Get-ActionScript -Action 'generate-config-schema' -Script 'discover-config-types.ps1'

  function New-CsTree {
    param([hashtable]$Files)
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("disc-" + [guid]::NewGuid().ToString('n'))
    foreach ($rel in $Files.Keys) {
      $p = Join-Path $work $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
      Set-Content -Path $p -Value $Files[$rel]
    }
    return $work
  }
}

Describe 'generate-config-schema / discover-config-types' {
  It 'extracts a simple ToObject<T>() type' {
    $work = New-CsTree @{ 'src/Factory.cs' = 'var c = dc.Properties.ToObject<LgDisplayPropertiesConfig>();' }
    $r = Invoke-ActionScript -Path $Discover -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.Outputs['types'] | Should -Be 'LgDisplayPropertiesConfig'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'extracts a namespace-qualified type and dedupes across files' {
    $work = New-CsTree @{
      'src/A.cs' = 'x.ToObject<My.Ns.FooConfig>(); y.ToObject<BarConfig>();'
      'src/B.cs' = 'z.ToObject<BarConfig>();'
    }
    $r = Invoke-ActionScript -Path $Discover -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    ($r.Outputs['types'] -split ';' | Sort-Object) | Should -Be @('BarConfig','My.Ns.FooConfig')
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'ignores generated sources under obj/ and bin/' {
    $work = New-CsTree @{
      'obj/Debug/G.cs' = 'a.ToObject<ShouldNotAppear>();'
      'src/Real.cs'    = 'b.ToObject<RealConfig>();'
    }
    $r = Invoke-ActionScript -Path $Discover -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.Outputs['types'] | Should -Be 'RealConfig'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'returns empty and notes it when there are no call sites' {
    $work = New-CsTree @{ 'src/Plain.cs' = 'class X {}' }
    $r = Invoke-ActionScript -Path $Discover -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.Outputs['types'] | Should -Be ''
    $r.Summary | Should -Match 'No .*ToObject.* call sites found'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'an explicit types input short-circuits discovery' {
    $work = New-CsTree @{ 'src/Real.cs' = 'b.ToObject<Discovered>();' }
    $r = Invoke-ActionScript -Path $Discover -Inputs @{ types = 'ExplicitA;ExplicitB' } -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.Outputs['types'] | Should -Be 'ExplicitA;ExplicitB'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}
