BeforeAll {
  . "$PSScriptRoot/_helpers.ps1"
  $script:ScriptPath = Get-ActionScript -Action 'copy-build-output' -Script 'copy-build-output.ps1'

  function New-BuildTree {
    param([string[]]$RelPaths)
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("cbo-" + [guid]::NewGuid().ToString('n'))
    foreach ($rel in $RelPaths) {
      $p = Join-Path $work $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
      Set-Content -Path $p -Value 'bin'
    }
    return $work
  }
}

Describe 'copy-build-output' {
  It 'collects .cpz + matching .dll from bin/<config> and versions them (plugin mode)' {
    $work = New-BuildTree @(
      'src/bin/Release/MyPlugin.cpz',
      'src/bin/Release/MyPlugin.dll',
      'packages/Other/Other.cpz'
    )
    $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version='2002.3.1'; 'build-type'='Release' } `
      -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work -KeepWorkDir
    $r.ExitCode | Should -Be 0
    $out = Get-ChildItem (Join-Path $work 'output') | Select-Object -ExpandProperty Name
    $out | Should -Contain 'MyPlugin.2002.3.1.cpz'
    $out | Should -Contain 'MyPlugin.2002.3.1.dll'
    $out | Should -Not -Contain 'Other.cpz'   # packages/ excluded
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'essentials mode: versions the .cpz but leaves DLLs unrenamed' {
    $work = New-BuildTree @(
      'bin/PepperDashEssentials.cpz',
      'bin/PepperDashEssentials.dll'
    )
    $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{
      version='2002.0.5'; 'build-type'='Release'; 'rename-mode'='essentials'
      'include-dll'='true'; 'bin-filter'='bin'; extensions='.cpz .clz'
    } -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work -KeepWorkDir
    $r.ExitCode | Should -Be 0
    $out = Get-ChildItem (Join-Path $work 'output') | Select-Object -ExpandProperty Name
    $out | Should -Contain 'PepperDashEssentials.2002.0.5.cpz'
    $out | Should -Contain 'PepperDashEssentials.dll'          # NOT renamed
    $out | Should -Not -Contain 'PepperDashEssentials.2002.0.5.dll'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'keeps a .3Series moniker and inserts the version before it' {
    $work = New-BuildTree @('src/bin/Release/MyPlugin.3Series.cpz')
    $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version='1002.3.1'; 'build-type'='Release' } `
      -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work -KeepWorkDir
    (Get-ChildItem (Join-Path $work 'output') | Select-Object -ExpandProperty Name) | Should -Contain 'MyPlugin.1002.3.1.3Series.cpz'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'fails clearly when no artifacts are found' {
    $work = New-BuildTree @('src/Something.txt')
    $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version='1.0.0'; 'build-type'='Release' } `
      -Env @{ GITHUB_WORKSPACE = $work } -WorkDir $work
    $r.ExitCode | Should -Be 1
    $r.Summary  | Should -Match '❌ .*No build artifacts'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}
