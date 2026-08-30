BeforeAll {
  . "$PSScriptRoot/_helpers.ps1"
  $script:ProjectInfo  = Get-ActionScript -Action 'get-project-info' -Script 'get-project-info.ps1'
  $script:CheckPkgName = Get-ActionScript -Action 'check-package-name' -Script 'check-package-name.ps1'
}

Describe 'get-project-info' {
  It 'parses org/epi-make-model' {
    $r = Invoke-ActionScript -Path $ProjectInfo -Env @{ GITHUB_REPOSITORY = 'PepperDash/epi-lg-display' }
    $r.ExitCode | Should -Be 0
    $r.Outputs['make']  | Should -Be 'lg'
    $r.Outputs['model'] | Should -Be 'display'
    $r.Outputs['title'] | Should -Be 'LgDisplay'
    $r.Outputs['repo-is-plugin'] | Should -Be 'true'
  }

  It 'dotted style (default) -> <prefix>Make.Model' {
    $r = Invoke-ActionScript -Path $ProjectInfo -Env @{ GITHUB_REPOSITORY = 'PepperDash/epi-lg-display' }
    $r.Outputs['package'] | Should -Be 'PepperDash.Essentials.Plugins.Lg.Display'
  }

  It 'concatenated style -> <prefix>MakeModel' {
    $r = Invoke-ActionScript -Path $ProjectInfo -Inputs @{ 'package-style' = 'concatenated' } -Env @{ GITHUB_REPOSITORY = 'PepperDash/epi-lg-display' }
    $r.Outputs['package'] | Should -Be 'PepperDash.Essentials.Plugins.LgDisplay'
  }

  It 'handles a variant segment: epi-make-model-variant' {
    $r = Invoke-ActionScript -Path $ProjectInfo -Env @{ GITHUB_REPOSITORY = 'PepperDash/epi-samsung-mdc-display' }
    $r.Outputs['make']  | Should -Be 'samsung'
    $r.Outputs['model'] | Should -Be 'mdcdisplay'
  }

  It 'non-plugin repo (single segment) -> repo-is-plugin false' {
    $r = Invoke-ActionScript -Path $ProjectInfo -Env @{ GITHUB_REPOSITORY = 'PepperDash/Essentials' }
    $r.Outputs['repo-is-plugin'] | Should -Be 'false'
    $r.Outputs['title'] | Should -Be 'Essentials'
  }

  It 'fails when GITHUB_REPOSITORY is unset' {
    $r = Invoke-ActionScript -Path $ProjectInfo
    $r.ExitCode | Should -Be 1
    $r.Summary  | Should -Match 'GITHUB_REPOSITORY is not set'
  }
}

Describe 'get-project-info and check-package-name round trip' {
  It 'the dotted package id passes the package-name check for the same repo' {
    $repo = 'PepperDash/epi-lg-display'
    $info = Invoke-ActionScript -Path $ProjectInfo -Env @{ GITHUB_REPOSITORY = $repo }
    $pkg  = $info.Outputs['package']

    # Stage a .nupkg named like the get-project-info package id + a version.
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("rt-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'output') | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $work "output/$pkg.2002.3.1.nupkg") | Out-Null

    $check = Invoke-ActionScript -Path $CheckPkgName -Env @{ GITHUB_REPOSITORY = $repo } -WorkDir $work
    $check.ExitCode | Should -Be 0 -Because "get-project-info's '$pkg' must satisfy check-package-name for $repo"
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'a mismatched package id fails the check' {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("rt-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'output') | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $work "output/PepperDash.Essentials.Plugins.Wrong.Name.1.0.0.nupkg") | Out-Null
    $check = Invoke-ActionScript -Path $CheckPkgName -Env @{ GITHUB_REPOSITORY = 'PepperDash/epi-lg-display' } -WorkDir $work
    $check.ExitCode | Should -Be 1
    $check.Summary  | Should -Match '❌ .*Package name mismatch'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}
