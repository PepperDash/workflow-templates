# Testing the reusable actions & workflows

Everything here runs **locally and offline** — no GitHub, no runners, nothing
published.

## What is tested

| Layer | Tool | Location |
|---|---|---|
| Every composite-action script (inputs → outputs / summary / exit code) | Pester 5 | `tests/pester/*.Tests.ps1` |
| Build-workflow structure ("no publish before a green build", getversion creates no tag) | Pester 5 + `powershell-yaml` | `tests/pester/workflow-structure.Tests.ps1` |
| The config-schema generator (`SchemaGen`) | xUnit | `tests/SchemaGen.Tests/` |
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

Options: `-SkipDotnet`, `-SkipActionlint`, `-SkipPester`. A JUnit report is
written to `test-results.xml`.

## Run a subset

```pwsh
# one action
Invoke-Pester tests/pester/apply-essentials-version-prefix.Tests.ps1 -Output Detailed

# just the "no publish before build" guardrail
Invoke-Pester tests/pester/workflow-structure.Tests.ps1

# the schema generator
dotnet test tests/SchemaGen.Tests
```

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
