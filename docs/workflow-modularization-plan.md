# Workflow Modularization Plan (issue #49)

Status: **proposal — awaiting review**
Branch: `refactor/workflow-modularization-49` (off `origin/main`)

## Goals

1. Break the build workflows into small **reusable blocks** so Essentials and
   Plugins share logic instead of copy‑pasting it.
2. Keep **Essentials (Core)** and **Plugins (EPI)** as separate entry points that
   compose the same blocks differently.
3. Add **.NET 8** build workflows for 4‑Series alongside the existing net472 ones.
4. Adopt a consistent file‑naming convention (issue #49).
5. **Do not break existing consumers.** Every consuming repo pins `@main`, so the
   current files stay in place, untouched. New files are added next to them. Repos
   migrate their caller at their own pace; the old files are removed in a later
   PR once no callers remain.

## Primitive choice: composite actions, not nested reusable workflows

Almost all the duplication is **steps inside a single build job**
(`Update AssemblyInfo.cs`, `Copy build output files`, `Publish to Nuget.org`, …),
not whole jobs. Splitting those into `workflow_call` workflows would give each
fragment a fresh runner and a fresh workspace, forcing artifact upload/download
between "build" and "copy output" on the self‑hosted `dmz-windows-2019` runner —
slower and more fragile.

| Reuse level | Mechanism | Why |
|---|---|---|
| Step group inside a job | **composite action** in `.github/actions/<name>/action.yml` | runs in‑job, shares workspace + runner group |
| Whole job (own runner) | **reusable workflow** (`on: workflow_call`) | getversion, build, test, checkcommit, readme |

Note: composite actions cannot read `secrets`. Every consumer uses
`secrets: inherit`, which only reaches the reusable workflow. So the reusable
build workflow receives secrets and threads them into publish actions as explicit
`with:` inputs (`NUGET_API_KEY`, `GITHUB_TOKEN`, `DOCKERHUB_USER`,
`DOCKERHUB_PASSWORD`).

## File naming convention

Consuming repos keep the `‑caller` suffix on their own files. Files **in this
repo** use:

```
{entrypoint}-{series}-{tfm}-{action}.yml
```

* `entrypoint` — `essentials` (Core) | `plugin` (EPI)
* `series` — `3series` | `4series`
* `tfm` — `net35` (3‑Series) | `net472` | `net8`
* `action` — `build`

Workflows that are not series/tfm‑specific collapse to `{action}.yml`:
`getversion.yml`, `run-tests.yml`, `check-commit-message.yml`, `update-readme.yml`.

## Target reusable workflows (new files)

| New file | Replaces / relates to | Notes |
|---|---|---|
| `getversion.yml` | `essentialsplugins-getversion.yml`, `essentials-plugin-getversion.yml` | semantic‑release → plain semver; **does not** create the Git release/tag (the build applies the Essentials prefix and tags). Includes `fetch-depth: 0` and the pinned `conventional-changelog-conventionalcommits@9`. |
| `run-tests.yml` | `essentialsplugins-run-tests.yml` | unchanged content, renamed |
| `check-commit-message.yml` | `essentialsplugins-checkCommitMessage.yml` | unchanged content, renamed |
| `update-readme.yml` | `update-readme.yml` | keep name; drop the manual second checkout by referencing `metadata.py` via `uses:` of this repo |
| `essentials-3series-net35-build.yml` | `essentials-3Series-builds.yml` | Core, 3‑Series, Docker `sspbuilder`, keeps `.dll` artifacts, **no package‑name check** |
| `essentials-4series-net472-build.yml` | *new* (Core currently piggybacks on the plugin 4‑Series workflow with `bypassPackageCheck: true`) | Core, 4‑Series, `dotnet build` net472 |
| `essentials-4series-net8-build.yml` | *new* | Core, 4‑Series, `dotnet build` net8 |
| `plugin-3series-net35-build.yml` | `essentialsplugins-3Series-builds.yml` + `essentials-v1-plugin-build.yml` | EPI, 3‑Series, Docker build, Essentials‑v1 version prefix (major 1000+) via input |
| `plugin-4series-net472-build.yml` | `essentialsplugins-4Series-builds.yml` + `essentials-v2-plugin-build.yml` | EPI, 4‑Series net472, Essentials‑vN prefix detected from `.4Series.csproj`, `devToolsVersion` SPA embed, package‑name check |
| `plugin-4series-net8-build.yml` | *new* | EPI, 4‑Series net8, same prefix + checks |

The `version-formatting` branch's `essentials-v1/v2-plugin-build.yml` and
`essentials-plugin-getversion.yml` are **folded into** the files above:
the Essentials‑major version‑prefix behaviour becomes the
`apply-essentials-version-prefix` composite action plus an input on the plugin
build workflows, rather than a parallel family of files. The versioning‑plan doc
(`.github/instructions/versioning-plan.instructions.md`) is re‑applied on this
branch.

## Target composite actions (`.github/actions/`)

| Action | Inputs (key) | Outputs | Used by |
|---|---|---|---|
| `get-sln-info` | `filter` (`*.4Series.sln`) | `solution-file`, `solution-path` | all builds |
| `get-project-info` | – | `make`, `model`, `title`, `package`, `repo-is-plugin` | plugin builds, essentials‑3series |
| `apply-essentials-version-prefix` | `version`, `tag`, `series` (`3series` hardcodes 1000) or detect from `.4Series.csproj` | `version`, `tag` | plugin builds |
| `update-assembly-info` | `version` | – | 3‑Series + net472 builds |
| `docker-build-3series` | `solution-path`, `build-type`, `dockerhub-user`, `dockerhub-password` | – | 3‑Series builds |
| `dotnet-build` | `solution-file`, `build-type`, `version`, `tfm` | – | 4‑Series builds |
| `copy-build-output` | `build-type`, `extensions`, `package`, `version`, `is-essentials` | – | all builds (parameterised rename + extension list) |
| `create-nuspec` | `package`, `title`, `version`, `repo-name`, `tags`, `license-type`, `target-framework` | `nuspec-file` | plugin builds |
| `pack-nuget` | `nuspec-file`, `version` | – | all builds |
| `check-package-name` | `bypass` | – | **plugin builds only** |
| `embed-devtools-spa` | `devtools-version` | – | 4‑Series plugin builds |
| `publish-nuget-github` | `github-token`, `owner` | – | all builds |
| `publish-nuget-org` | `nuget-api-key` | – | all builds — **sole owner** of the fail‑closed `owner == pepperdash && visibility == public` runtime gate |
| `cleanup-failed-release` | `tag`, `gh-token` | – | all builds (one `bash`+`gh` implementation, works on Windows runners) |
| `upload-release` | `tag`, `artifacts`, `prerelease`, `body-file` | – | all builds |

## Lane composition

**Essentials / Core** (`essentials-*`): checkout → `update-assembly-info` (3‑Series)
or `/p:Version` (4‑Series) → build (`docker-build-3series` | `dotnet-build`) →
`copy-build-output` (`is-essentials: true`, includes `.dll`) → `pack-nuget`
(checked‑in `.nuspec`) → `publish-nuget-github` → `publish-nuget-org` →
`upload-release`. **No `check-package-name`.**

**Plugin / EPI** (`plugin-*`): checkout → `get-project-info` →
`apply-essentials-version-prefix` → `update-assembly-info` → build →
`copy-build-output` → `create-nuspec` → `pack-nuget` → `check-package-name` →
`embed-devtools-spa` (4‑Series) → `upload-release` → `publish-nuget-github` →
`publish-nuget-org`.

## Public NuGet publishing

Unchanged behaviour: the runtime check
`github.repository_owner == 'PepperDash' && repository visibility == 'public'`
stays as the **only** gate, consolidated into `publish-nuget-org`. Fail‑closed —
a private repo physically cannot publish to nuget.org regardless of caller
config. No new caller input.

## Consumer migration

* `docs/migrating-callers.md` — old→new mapping table, before/after caller YAML
  for each repo type, and a copy‑pasteable **agent prompt** to convert a
  consuming repo's caller file (detect net472 vs net8 from the `.csproj`
  `TargetFramework`, preserve `secrets: inherit` / `needs:` / `if:`).
* No shims: old files are left exactly as they are on `main` and keep working.
* A follow‑up PR removes the deprecated files once `gh` shows no remaining
  `uses:` references across the org.

## Dead code found (handle in a separate PR, not this one)

* `essentialsplugins-builds.yml` — pre‑semantic‑release; its nuget.org gate uses
  `github.repository_visibility` (not a valid context) so that publish has been a
  silent no‑op.

## Out of scope for this PR

* `.vscode/settings.json` local change (stashed on `version-formatting`).
* Deleting any existing workflow file.
* Updating consuming repos (done per‑repo using the migration guide).

## Build / commit sequence

1. This plan doc (commit 1) → open **draft PR** for review.
2. Composite actions + unit‑style `workflow_dispatch` test harness.
3. New reusable build workflows composing the actions.
4. `getversion.yml`, `run-tests.yml`, `check-commit-message.yml` renames.
5. `docs/` catalog refresh + `docs/migrating-callers.md`.
6. Re‑apply `.github/instructions/versioning-plan.instructions.md`.
7. Mark PR ready.
