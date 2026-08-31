BeforeAll {
  . "$PSScriptRoot/_helpers.ps1"
  $script:ScriptPath = Get-ActionScript -Action 'get-sln-info' -Script 'get-sln-info.ps1'
}

Describe 'get-sln-info' {
  It 'finds a .4Series.sln nested in src/ and reports its base name' {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("sln-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'src') | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $work 'src/MyPlugin.4Series.sln') | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $work 'src/MyPlugin.3Series.sln') | Out-Null

    $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ filter = '*.4Series.sln' } -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.ExitCode | Should -Be 0
    $r.Outputs['solution-file'] | Should -Be 'MyPlugin.4Series'
    $r.Outputs['solution-name'] | Should -Be 'MyPlugin.4Series.sln'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'fails with a clear message when nothing matches' {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("sln-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ filter = '*.4Series.sln' } -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.ExitCode | Should -Be 1
    $r.Summary  | Should -Match '❌ .*No solution file matching'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'requires the filter input' {
    $r = Invoke-ActionScript -Path $ScriptPath
    $r.ExitCode | Should -Be 1
    $r.Summary  | Should -Match "Required input 'filter'"
  }
}
