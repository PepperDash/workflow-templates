BeforeAll {
  . "$PSScriptRoot/_helpers.ps1"
  $script:ScriptPath = Get-ActionScript -Action 'create-nuspec' -Script 'create-nuspec.ps1'

  function Invoke-CreateNuspec {
    param([hashtable]$Inputs, [string[]]$RootFiles = @())
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("ns-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    foreach ($f in $RootFiles) { Set-Content -Path (Join-Path $work $f) -Value 'x' }
    $r = Invoke-ActionScript -Path $ScriptPath -Inputs $Inputs `
      -Env @{ GITHUB_WORKSPACE = $work; GITHUB_REPOSITORY = 'PepperDash/epi-lg-display' } -WorkDir $work -KeepWorkDir
    $nuspecPath = Join-Path $work 'project.nuspec'
    $xml = if (Test-Path $nuspecPath) { [xml](Get-Content -Raw $nuspecPath) } else { $null }
    $r | Add-Member -NotePropertyName NuspecXml -NotePropertyValue $xml
    $r | Add-Member -NotePropertyName WorkRoot -NotePropertyValue $work
    return $r
  }
}

Describe 'create-nuspec' {
  It 'is a no-op for a non-plugin repo' {
    $r = Invoke-CreateNuspec -Inputs @{ package='X'; title='X'; version='1.0.0'; 'repo-name'='x'; 'repo-is-plugin'='false' }
    $r.ExitCode | Should -Be 0
    $r.Outputs['nuspec-file'] | Should -Be ''
    $r.NuspecXml | Should -BeNullOrEmpty
    Remove-Item $r.WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'embeds id, version, repository URL, assembly name and TypeNames' {
    $r = Invoke-CreateNuspec -Inputs @{
      package='PepperDash.Essentials.Plugins.Lg.Display'; title='LgDisplay'; version='2002.3.1'
      'repo-name'='epi-lg-display'; 'repo-is-plugin'='true'
      'assembly-name'='LgDisplayPlugin'; 'type-names'='lgDisplay lg'; 'type-names-list'='lgDisplay, lg'
      'min-framework-version'='2.16.0'; 'target-framework'='net47'
    } -RootFiles @('LICENSE.md','README.md')

    $r.ExitCode | Should -Be 0
    $md = $r.NuspecXml.package.metadata
    $md.id       | Should -Be 'PepperDash.Essentials.Plugins.Lg.Display'
    $md.version  | Should -Be '2002.3.1'
    $md.projectUrl | Should -Be 'https://github.com/PepperDash/epi-lg-display'
    $md.repository.url | Should -Be 'https://github.com/PepperDash/epi-lg-display'
    $md.tags     | Should -Match '\blgDisplay\b'
    $md.tags     | Should -Match '\blg\b'
    $md.description | Should -Match 'Assembly: LgDisplayPlugin'
    $md.description | Should -Match 'Factory TypeNames: lgDisplay, lg'
    $md.releaseNotes | Should -Match 'lgDisplay, lg'
    ($r.NuspecXml.package.files.file.target) | Should -Contain 'lib\net47'
    Remove-Item $r.WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'omits LICENSE.md / README.md file entries when they are absent' {
    $r = Invoke-CreateNuspec -Inputs @{
      package='P'; title='P'; version='1.0.0'; 'repo-name'='epi-x-y'; 'repo-is-plugin'='true'
    }
    ($r.NuspecXml.package.files.file.src) | Should -Not -Contain 'LICENSE.md'
    $r.Summary | Should -Match 'LICENSE.md not found'
    Remove-Item $r.WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'produces well-formed XML even with special chars in the description' {
    $r = Invoke-CreateNuspec -Inputs @{
      package='P'; title='A & B <plugin>'; version='1.0.0'; 'repo-name'='epi-a-b & <x>'; 'repo-is-plugin'='true'
    }
    $r.ExitCode | Should -Be 0
    { [xml](Get-Content -Raw (Join-Path $r.WorkRoot 'project.nuspec')) } | Should -Not -Throw
    Remove-Item $r.WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
