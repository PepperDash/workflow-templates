# Testing the reusable actions & workflows

Everything here runs **locally and offline** — no GitHub, no runners, nothing
published.

## What is tested

| Layer | Tool | Location |
|---|---|---|
| Every composite-action script (inputs → outputs / summary / exit code) | Pester 5 | `tests/pester/*.Tests.ps1` |
| Build-workflow structure ("no publish before a green build", getversion creates no tag) | Pester 5 + `powershell-yaml` | `tests/pester/workflow-structure.Tests.ps1` |
| The config-schema generator (`SchemaGen`) | Pester 5 (builds a fixture, runs the built tool) | `tests/pester/schema-gen-tool.Tests.ps1` |
| Whole build lane, composed end-to-end (offline steps run for real, publish steps dry-run) | `pwsh` | `tests/run-workflow-local.ps1` |
| Workflow YAML lint | `actionlint` | `.github/workflows/*.yml` |

## Prerequisites

- **PowerShell 7+** (`pwsh`) — `brew install powershell` / [docs](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
- **Pester 5** and **powershell-yaml** — `tests/run-all.ps1` installs them into
  the current-user scope if missing
- **.NET SDK 8+** — for the `SchemaGen` tests (optional; skipped if absent)
- **actionlint** — `brew install actionlint` (optional; skipped if absent)

## Run everything

```pwsh
pwsh tests/run-all.ps1
```

Options: `-SkipDotnet`, `-SkipActionlint`, `-SkipPester`, `-SkipWorkflowSmoke`.
A JUnit report is written to `test-results.xml`.

## Run a subset

```pwsh
# one action
Invoke-Pester tests/pester/apply-essentials-version-prefix.Tests.ps1 -Output Detailed

# just the "no publish before build" guardrail
Invoke-Pester tests/pester/workflow-structure.Tests.ps1

# the schema generator
Invoke-Pester tests/pester/schema-gen-tool.Tests.ps1
```

## Dry-run a whole build workflow — `tests/run-workflow-local.ps1`

Executes the real composite-action scripts, in the order a build workflow calls
them, threading each step's outputs / env into the next — but on your machine,
with **no GitHub, no runner, and nothing published**.

```pwsh
# smoke-test every lane against a generated fixture (part of run-all.ps1)
pwsh tests/run-workflow-local.ps1 -All

# dry-run one lane against a real local checkout
pwsh tests/run-workflow-local.ps1 -Workflow plugin-4series-net8 `
     -RepoPath ../epi-lg-display -Repo epi-lg-display -Version 2.3.1

# also compile for real (needs the .NET SDK; still publishes nothing)
pwsh tests/run-workflow-local.ps1 -Workflow essentials-4series-net8 `
     -RepoPath ../Essentials -Repo Essentials -RunBuild
```

Step classes:

| Class | Behaviour |
|---|---|
| `offline` | run for real — `get-sln-info`, `get-project-info`, `apply-essentials-version-prefix`, `get-plugin-metadata`, `update-assembly-info`, `create-nuspec` |
| `needs-build` | run only if a compile happened this session — `copy-build-output`, `check-package-name`, `add-files-to-nupkg` |
| `build` | dry-run unless `-RunBuild` — `dotnet-build`, `pack-nuget`, `generate-config-schema` |
| `docker` | dry-run unless `-RunDocker` — `docker-build-3series` |
| `dry-always` | never executed — `upload-release`, `publish-nuget-github`, `embed-devtools-spa`, `cleanup-failed-release`. For `publish-nuget-org` the fail-closed `owner == pepperdash && visibility == public` gate is evaluated and printed. |

Useful flags: `-Owner` / `-Visibility` (exercise the nuget.org gate),
`-Channel Debug`, `-PackageStyle dotted`, `-ApplyVersionPrefix:$false`,
`-KeepWorkspace` (leave the throwaway workspace on disk to inspect).

## How the harness works

Composite-action logic lives in `.github/actions/<name>/scripts/<name>.ps1`
(or `.sh`). Each script reads inputs from `$INPUT_<UPPER_SNAKE>` and writes to
`$GITHUB_OUTPUT` / `$GITHUB_ENV` / `$GITHUB_STEP_SUMMARY` — all plain file paths.

`tests/pester/_helpers.ps1` → `Invoke-ActionScript` runs a script in a throwaway
temp workspace with those three env vars pointed at temp files, then returns:

```
ExitCode, Outputs (hashtable), EnvVars (hashtable), Summary (string), Stdout, Stderr, WorkDir
```

So a test is just: set inputs, invoke, assert on the parsed results. No mocking,
no Docker, no network. Scripts that shell out to `dotnet` / `nuget` / `docker` /
`gh` are tested for their input-validation, gating, and reporting paths; the
external build/publish itself is covered by running the real workflow on a PR.

## CI

`.github/workflows/self-test.yml` runs `tests/run-all.ps1` on every PR **to this
repo**. It builds nothing for downstream consumers and publishes nothing.
