# Discovery-time: enumerate the modular build workflows so -ForEach can expand.
$script:WfDir = Join-Path (Resolve-Path "$PSScriptRoot/../..").Path '.github/workflows'
$script:BuildWorkflows = @(Get-ChildItem -Path $WfDir -Filter '*-build.yml' |
  Where-Object { $_.Name -match '^(plugin|essentials)-' })

BeforeAll {
  . "$PSScriptRoot/_helpers.ps1"
  $script:CompileActions = @('dotnet-build', 'docker-build-3series')
  $script:PublishActions = @('upload-release', 'publish-nuget-github', 'publish-nuget-org')

  function Get-Steps($wf) {
    $job = $wf.jobs.Values | Select-Object -First 1
    ,@($job.steps)
  }
  function Step-Uses($step) { if ($step.ContainsKey('uses')) { [string]$step['uses'] } else { '' } }
  function Step-If($step)   { if ($step.ContainsKey('if'))   { [string]$step['if'] }   else { '' } }
  function Step-Run($step)  { if ($step.ContainsKey('run'))  { [string]$step['run'] }  else { '' } }
}

Describe 'build workflow structure: no publish before a green compile' {
  It 'has at least one modular build workflow to check' {
    $BuildWorkflows.Count | Should -BeGreaterThan 0
  }

  It '<_> : the compile step is not continue-on-error' -ForEach $BuildWorkflows {
    $wf = Get-Yaml $_.FullName
    $steps = Get-Steps $wf
    $compile = $steps | Where-Object { $u = Step-Uses $_; $CompileActions | Where-Object { $u -match "/$_@|/$_`$" } }
    $compile | Should -Not -BeNullOrEmpty -Because "$($_.Name) must run a known compile action"
    foreach ($c in $compile) {
      [bool]$c['continue-on-error'] | Should -BeFalse -Because "a failed compile must fail the job"
    }
  }

  It '<_> : every publish/release step is gated on success()' -ForEach $BuildWorkflows {
    $wf = Get-Yaml $_.FullName
    foreach ($step in (Get-Steps $wf)) {
      $u = Step-Uses $step
      if ($PublishActions | Where-Object { $u -match "/$_@" }) {
        (Step-If $step) | Should -Match 'success\(\)' -Because "$u must not run after a failed step"
      }
    }
  }

  It '<_> : nothing before the compile step creates a tag or release' -ForEach $BuildWorkflows {
    $wf = Get-Yaml $_.FullName
    $steps = Get-Steps $wf
    $compileIdx = -1
    for ($i = 0; $i -lt $steps.Count; $i++) {
      $u = Step-Uses $steps[$i]
      if ($CompileActions | Where-Object { $u -match "/$_@" }) { $compileIdx = $i; break }
    }
    $compileIdx | Should -BeGreaterThan -1
    for ($i = 0; $i -lt $compileIdx; $i++) {
      $u = Step-Uses $steps[$i]; $r = Step-Run $steps[$i]
      $u | Should -Not -Match 'ncipollo/release-action'
      $u | Should -Not -Match '/upload-release@'
      $r | Should -Not -Match 'gh release create'
      $r | Should -Not -Match 'git tag '
      $r | Should -Not -Match 'git push .*--tags'
    }
  }
}

Describe 'getversion.yml creates no tag or release' {
  It 'has no release-creating step' {
    $path = Join-Path $WfDir 'getversion.yml'
    Test-Path $path | Should -BeTrue
    $wf = Get-Yaml $path
    foreach ($step in (Get-Steps $wf)) {
      (Step-Uses $step) | Should -Not -Match 'ncipollo/release-action'
      (Step-Run  $step) | Should -Not -Match 'gh release create'
      (Step-Run  $step) | Should -Not -Match 'semantic-release/github'
    }
  }

  It 'still produces the change-log artifact' {
    $wf = Get-Yaml (Join-Path $WfDir 'getversion.yml')
    $usesUpload = (Get-Steps $wf) | Where-Object { (Step-Uses $_) -match 'actions/upload-artifact' }
    $usesUpload | Should -Not -BeNullOrEmpty
  }
}
