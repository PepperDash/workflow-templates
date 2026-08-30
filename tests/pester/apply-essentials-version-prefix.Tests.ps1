BeforeAll {
  . "$PSScriptRoot/_helpers.ps1"
  $script:ScriptPath = Get-ActionScript -Action 'apply-essentials-version-prefix' -Script 'apply-version-prefix.ps1'
}

Describe 'apply-essentials-version-prefix' {

  Context 'explicit essentials-major' {
    It 'prefixes 3-Series (major 1): 2.3.1 -> 1002.3.1' {
      $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = '2.3.1'; 'essentials-major' = '1' }
      $r.ExitCode | Should -Be 0
      $r.Outputs['version'] | Should -Be '1002.3.1'
      $r.Outputs['tag']     | Should -Be 'v1002.3.1'
      $r.Outputs['essentials-major'] | Should -Be '1'
      $r.EnvVars['VERSION'] | Should -Be '1002.3.1'
    }

    It 'prefixes 4-Series (major 2): 2.3.1 -> 2002.3.1' {
      $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = '2.3.1'; 'essentials-major' = '2' }
      $r.Outputs['version'] | Should -Be '2002.3.1'
      $r.Outputs['tag']     | Should -Be 'v2002.3.1'
    }

    It 'preserves a prerelease suffix' {
      $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = '2.3.1-beta.1'; 'essentials-major' = '2' }
      $r.Outputs['version'] | Should -Be '2002.3.1-beta.1'
      $r.Outputs['tag']     | Should -Be 'v2002.3.1-beta.1'
    }

    It 'is idempotent: applying twice equals applying once' {
      $once  = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = '2.3.1'; 'essentials-major' = '1' }
      $twice = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = $once.Outputs['version']; 'essentials-major' = '1' }
      $twice.Outputs['version'] | Should -Be $once.Outputs['version']
      $twice.Outputs['version'] | Should -Be '1002.3.1'
    }

    It 'idempotent after a minor bump: 1002.4.0 + major 1 -> 1002.4.0' {
      $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = '1002.4.0'; 'essentials-major' = '1' }
      $r.Outputs['version'] | Should -Be '1002.4.0'
    }

    It 'idempotent after a breaking bump within range: 1003.0.0 + major 1 -> 1003.0.0' {
      $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = '1003.0.0'; 'essentials-major' = '1' }
      $r.Outputs['version'] | Should -Be '1003.0.0'
    }
  }

  Context 'auto-detect from csproj' {
    It 'reads the PepperDashEssentials major from a .4Series.csproj' {
      $work = Join-Path ([System.IO.Path]::GetTempPath()) ("fx-" + [guid]::NewGuid().ToString('n'))
      New-FixtureCsproj -Dir (Join-Path $work 'src') -EssentialsVersion '2.16.0'
      $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = '5.1.2' } -WorkDir $work
      $r.ExitCode | Should -Be 0
      $r.Outputs['version'] | Should -Be '2005.1.2'
      Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'fails clearly when no csproj is present' {
      $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = '1.0.0' }
      $r.ExitCode | Should -Be 1
      $r.Summary  | Should -Match '❌ .*No csproj matching'
    }
  }

  Context 'bad input' {
    It 'rejects a non-semver version' {
      $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = 'not-a-version'; 'essentials-major' = '2' }
      $r.ExitCode | Should -Be 1
      $r.Summary  | Should -Match '❌ .*does not match semver'
    }

    It 'rejects a missing version input' {
      $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ 'essentials-major' = '2' }
      $r.ExitCode | Should -Be 1
      $r.Summary  | Should -Match "Required input 'version'"
    }

    It 'rejects a non-integer essentials-major' {
      $r = Invoke-ActionScript -Path $ScriptPath -Inputs @{ version = '1.0.0'; 'essentials-major' = 'abc' }
      $r.ExitCode | Should -Be 1
    }
  }
}
