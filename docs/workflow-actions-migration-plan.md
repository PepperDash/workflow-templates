# Workflow-templates → composite actions: review of #49 / PR #57 and migration plan

Status: **draft v2** · Written 2026-10-27 · Decisions D1–D5 and D7–D12 recorded 2026-10-27; **all decisions D1–D12 recorded; next step is the D12 work breakdown**; D12 (work breakdown) follows once this plan is agreed · Supersedes `docs/workflow-modularization-plan.md` on `refactor/workflow-modularization-49` once agreed.

Repos involved: `PepperDash/workflow-templates` (public), `PepperDash/essentials-build-tools` (internal; tools public on nuget.org), `PepperDash/EssentialsPluginTemplate`, `PepperDash/.github` (org starter workflows), ~115 consuming repos.

---

## 1. Summary

The direction in PR #57 is right: composite actions for in-job steps, reusable workflows for job seams, separate Essentials and Plugin lanes, non-breaking rollout. The plan below keeps all of that and changes five things:

1. **Re-scope.** Issue #49 is a one-paragraph naming proposal; PR #57 is ~4,900 lines and its description still says "plan only". Track the work as an epic and split the PR.
2. **Drop `generate-config-schema` from the PR.** It contradicts a recorded decision (schema generation is `pd-schemagen` in essentials-build-tools, wired through the template's MSBuild targets, with no workflow-templates change).
3. **Add a pinning and release policy before splitting repos.** About 115 repos call `@main`; the new workflows pin actions to a feature branch. Splitting actions into repos multiplies this problem unless versioned tags come first.
4. **One repo per action** (16 repos, `action-{descriptor}`), each independently versioned and releasable. Tiers (section 5.2) set the *order* of extraction, not a cut-off.
5. **Treat essentials-build-tools as the source of truth for README badges and docs**, reached locally through VS Code tasks and MSBuild parameters, at commit time, and (bonus) in the cloud after a push. This replaces `update-readme.yml` and retires `metadata.py` (section 6). DocFX is deferred to a day-2/3 plan (section 7).

**Blocking fact found while reviewing:** neither `PepperDash.Essentials.BuildTools.Readme` nor `...SchemaGen` is on nuget.org yet (both return 404), and the template branch `git-config-updates` already pins `readme` 0.1.0. Until the packages are published, any build of that branch fails at `dotnet tool restore`. Publishing is therefore Phase 0.

### Scope exclusion: 3-Series / Essentials v1

Anything targeting Crestron **3-Series** processors with **Essentials v1** (.NET CompactFramework 3.5, `net35`) is **out of scope** for this effort. Concretely:

- The legacy 3-Series workflows (`essentials-3Series-builds.yml`, `essentialsplugins-3Series-builds.yml`) and the 3-Series callers stay untouched and keep working as they do today. They get no deprecation warning, no migration and no new action versions.
- PR #57's `essentials-3series-net35-build.yml` and `plugin-3series-net35-build.yml`, the `docker-build-3series` action, and the Essentials-v1 branch of `apply-essentials-version-prefix` (hard-coded major 1000) are dropped from #57 and not extracted. Only the v2+ prefix detection from `*.4Series.csproj` remains.
- No 3-Series canary, no `dmz-windows-2019` runner verification, no Docker `sspbuilder` work. The Pester and dry-runner coverage for those lanes is removed with them.
- Naming (D1) applies to 4-Series lanes only. The `net35` examples in #49 are not adopted for now.
- Revisit later as a separate effort if 3-Series maintenance is ever needed.

---

## 2. What #49 and PR #57 actually contain

| Item | Reality |
|---|---|
| Issue #49 | Proposes `{entry_point}-{arch_support}-{action}-caller.yml`, e.g. `essentials-net35-builds-caller.yml`, `plugins-net472-builds-caller.yml`, `react-builds-caller.yml`. Open, no comments. Labels: Workflow, planning. |
| PR #57 (draft) | 18 composite actions + `_common` helpers, 7 new build workflows, `getversion.yml`, Pester tests, a local dry-runner, a self-test workflow. Zero reviews. No `docs/migrating-callers.md` yet. |
| Naming drift | #49 uses plural `builds` and a caller-file name with an `arch` segment (`net35`). The PR uses singular `build` and `{entrypoint}-{series}-{tfm}-{action}` for the reusable workflows. The issue's examples are *caller* names; the PR names the *reusable* files. These are different files and the decision has not been recorded on the issue. |
| Existing callers | ~115 repos call `.../workflows/<file>@main`. New org repos get callers from `PepperDash/.github/workflow-templates/*-caller.yml` (6 starters). |

---

## 3. Concerns and improvements

Severity: **H** = fix before merging anything, **M** = fix inside the plan, **L** = cleanup.

| # | Sev | Concern | Recommendation |
|---|---|---|---|
| C1 | H | **`@main` everywhere.** Consumers pin `@main`; the new workflows pin actions to `@refactor/workflow-modularization-49` with a comment "flip to `@main` before merging". A broken merge to `main` breaks every consumer at once, and with per-action repos it breaks them through two levels of indirection. | Tag releases. Action repos release semver plus a moving `v1`. workflow-templates pins its actions to `@v1` (first-party) or a full SHA (third-party) and is itself tagged; new callers use `@v1`. Dependabot (`github-actions` ecosystem, already configured in workflow-templates) bumps the pins. See section 4. |
| C2 | H | **`generate-config-schema` shipped in #57 contradicts the schema decision.** The action fails silently on net472 plugins (Essentials referenced with `ExcludeAssets=runtime`, Crestron's SimplSharpNewtonsoft, `SimplSharpPro.exe`) and the lane marks it `continue-on-error: true`, so failures are invisible. | Remove the action, its Pester tests, `schema-gen/`, and the two lane steps from #57. Schemas come from `pd-schemagen` via template targets and a committed `schemas/` folder. To ship them in the nupkg, include `schemas/**` as a pack item in the csproj, with no workflow change. |
| C3 | H | **Tools not published.** See section 1. | Phase 0. |
| C4 | M | **Scope drift.** One naming issue became a 4,900-line PR. | Open an epic that links the issues in section 8, close #49 against the naming decision only, and split #57 into the PRs listed in Phase 2. |
| C5 | M | **`continue-on-error: true` hides failed publishes.** `publish-nuget-org.ps1` correctly fails (`Stop-Action "Failed to push: …"`), but the lane marks the step `continue-on-error`, so the run is green when nuget.org push failed. A dev sees a green check and no package. | Keep the publish steps non-fatal (the job stays green), but add a final `if: always()` step that detects an expected publish that did not succeed and emits `::error::<message>` (names the registry, the package and the failing step) **and** appends the same message to `$GITHUB_STEP_SUMMARY`. The `::error::` workflow command creates a run annotation; the summary append puts the text on the job summary page, so a failed publish is identifiable without opening the step log. The job result is unchanged. Put this in one shared action (e.g. a `report-publish-status` step inside `upload-release`/`publish-nuget-*`) so every lane behaves the same. Make this explicit in section 4's release semantics. |
| C6 | M | **Unpinned third-party refs.** `jacobtomlinson/gha-find-replace@master` (twice, in the legacy getversion), and `curl … rhysd/actionlint/main/…` in `self-test.yml`. | Pin by SHA. Prefer replacing `gha-find-replace` with a `sed`/pwsh step in the getversion action, since it only edits `.releaserc.json`. |
| C7 | M | **`update-readme.yml` is fragile.** It checks out `workflow-templates` at `main`, runs `metadata.py` (regex parser, `logging.DEBUG` noise, `os.walk` order, every join marked `R`), and **force-pushes** `robot-docs`. Protected branches block bot pushes; concurrent runs on different branches overwrite each other. | Replace with the essentials-build-tools C# tools (section 6): local VS Code tasks and build parameters first, optional cloud sync after push. Delete `update-readme.yml` and `metadata.py`. |
| C8 | M | **Old files fail silently into deprecation.** The plan leaves legacy workflows untouched, so nothing tells consumers to migrate. | Add one `::warning::` step to each legacy workflow naming its replacement and the migration doc. Behaviour is unchanged. |
| C9 | M | **Starter workflows not in scope.** `PepperDash/.github/workflow-templates/` is how new repos get callers. Without updating it, new repos keep landing on deprecated workflows. | Add to Phase 5. |
| C10 | M | **`_common/action.ps1` (`../../_common`) is sourced by 21 scripts.** It cannot cross repo boundaries. | See section 5.3. |
| C11 | L | **Double `pwsh`.** Steps use `shell: pwsh` then `run: pwsh -File …`, spawning a nested process. | Use `shell: pwsh` with `& "$env:GITHUB_ACTION_PATH/scripts/x.ps1"` (and propagate `$LASTEXITCODE`), or `shell: pwsh` with the script body inline. Do it once in the repo template so all actions inherit it. |
| C12 | L | **`essentialsplugins-builds.yml` is dead code** (nuget.org gate uses the non-existent `github.repository_visibility`, so that publish is a silent no-op). | Delete in its own PR, as already noted. |
| C13 | L | **Public-gate correctness depends on `github.event.repository.visibility`** inside a `workflow_call` workflow (it reads the *caller's* event payload). Verified only by unit tests, not on a real private/public pair. | Make it a canary exit criterion (Phase 4): one public and one private repo must produce opposite outcomes. |

What is already good and should be kept: composite-for-steps / reusable-for-jobs split; fail-closed public publishing gate in exactly one action; no tag/release before a green compile; idempotent re-runs; Pester coverage per action script; the offline lane dry-runner; non-breaking rollout.

---

## 4. Pinning, versioning and release policy (new, prerequisite for the split)

| Rule | Detail |
|---|---|
| Versioning | Every action repo and workflow-templates use semver tags `vMAJOR.MINOR.PATCH` plus a moving `vMAJOR`. Conventional commits drive the bump (already the org standard). Use immutable releases for the exact tags if the org setting is available. |
| Who moves `v1` | Only the release workflow, from a tag on `main`. A tag ruleset limits create/update/delete of `v*` to repo admins, same shape as essentials-build-tools' `protect-release-tags`. |
| Action → workflow pin | workflow-templates references first-party actions as `@v1`. Third-party actions by full commit SHA with a version comment. Dependabot keeps both current. |
| Workflow → caller pin | New callers use `workflow-templates/…@v1`. Existing `@main` callers keep working until migrated. Never delete a file from `main` while a caller still references it (check with `gh search code`). |
| Breaking change | Bump the major, publish `v2` beside `v1`, migrate callers in batches, retire `v1` last. Never retarget `v1` to a breaking change. |
| Rollback | Move `v1` back to the previous good tag. Because consumers → workflow-templates@v1 → action@v1 is two hops, document in the runbook which hop to roll back first (the leaf action). |
| Release semantics | Compile must succeed before any tag, release or package exists (kept). Publishing steps are non-fatal, and the job stays green. If an expected publish did not happen, a final step writes `::error::<message>` and the same message to the job summary so it can be identified (C5). |

---

## 5. Splitting actions into individual repos

### 5.1 Requirements and cost

**Decision (D2):** one repo per action, each manageable (versioned, released, rolled back, owned) without affecting another action or the workflows. The layout is clean (`uses: PepperDash/action-publish-nuget-org@v1`, `action.yml` at repo root), but each repo carries a release workflow, ruleset, CODEOWNERS, Dependabot, tests and CI. At 16 repos that is a recurring load, so the per-repo template (5.4) and tier ordering (5.2) keep it cheap.

**Naming (D2/D3):** `PepperDash/action-{descriptor}`, descriptor is kebab-case, verb first, matching the action's current folder name: `action-publish-nuget-org`, `action-dotnet-build`, `action-create-nuspec`. Reasons for the `action-` prefix over a suffix or `gh-action-`: sorts together in the org list, mirrors the `uses:` line, and leaves the `essentials-*` / `pd-*` namespaces for products.

Hard requirements:

- Action repos must be **public** (D3 asked whether `internal` is possible; it is not, for this estate). The org is on the Enterprise plan, so the `internal` visibility exists, but: (1) a public repo cannot use an action from an internal repo, and public plugin repos are the ones that publish to nuget.org; (2) `workflow-templates` is public and its reusable workflows reference these actions, so they would fail for public callers; (3) even for private callers every internal action repo needs *Settings → Actions → Access → accessible from repositories in the organization* set, 16 times. Making `workflow-templates` internal as well would break every public plugin repo. Internal remains an option only if the public-plugin lanes move out of scope. Mitigations for the public exposure: no secrets or internal data in any action (secrets are passed as `with:` inputs), CODEOWNERS plus rulesets limiting who can change them, and the immutable-release tags in section 4.
- Secrets cannot be read inside a composite action, so workflows keep passing them as explicit `with:` inputs (already the design).
- Action code must contain no PepperDash-internal data, since the repos are public.

### 5.2 Extraction order (tiers are sequence, not a cut-off)

Inventory is the 18 actions in PR #57 minus `generate-config-schema` (dropped) and `docker-build-3series` (3-Series is out of scope) = **16 repos**. The four discovery actions are no longer merged (D2 overrides the earlier recommendation).

| Order | Repos (`action-<name>`) | Why this order |
|---|---|---|
| **1** (own change cadence or security weight) | `publish-nuget-org` (owns the public-publish gate: strictest CODEOWNERS, 2 approvals), `publish-nuget-github`, `apply-essentials-version-prefix`, `upload-release`, `cleanup-failed-release`, `embed-devtools-spa` | Small, independent, or change for reasons unrelated to the build. First extraction also proves the template and release flow |
| **2** (interfaces settle with the lanes) | `dotnet-build`, `copy-build-output`, `create-nuspec`, `pack-nuget`, `add-files-to-nupkg`, `check-package-name` | Change together with the build lanes; extract after Phase 2 lands so the interfaces are stable |
| **3** (tiny discovery steps) | `get-sln-info`, `get-project-info`, `get-plugin-metadata`, `update-assembly-info` | ~30 lines each; extract last using the same template. Four repos is the cost of D2 |

### 5.3 Blockers and how to clear them

| Blocker | Resolution |
|---|---|
| `_common/action.ps1` and `action.sh` are shared by 21 scripts via a relative path | Vendor a ~60-line `scripts/common.ps1` into each repo from the repo template, with a CI check that fails when the vendored copy drifts from the template. Revisit a PowerShell module only if the helper grows. |
| `tests/pester/_helpers.ps1` and `tests/run-workflow-local.ps1` compose sibling action directories | Per-action unit tests move with each action. Lane-level integration tests stay in workflow-templates and resolve actions by tag through a small `actions.lock` manifest that the dry-runner reads. |
| Testing an unreleased action change in a real lane | The action repo's CI runs its own Pester suite and a smoke workflow that calls the action by `./` path. A consumer lane test in workflow-templates may point at a branch ref in a PR only, never in a merged file. |
| Pin flip comment ("flip to `@main` before merging") | Disappears: the pin is `@v1` from the start. |

### 5.4 Standard for every action repo (template repo `PepperDash/action-template`)

- `action.yml` (root), `scripts/` (+ vendored `common.ps1`), `tests/` (Pester), `README.md` with input/output table and usage snippet.
- CI: Pester + `actionlint` (pinned by SHA) on every branch push (no path filters on required checks, as in essentials-build-tools).
- `release.yml`: on tag `v*.*.*` from `main`, create the GitHub release and move `vMAJOR`.
- Rulesets: `protect-main` (PR, 1 approval, required checks, linear history, no bypass) and `protect-release-tags`, applied by a copy of `scripts/apply-repo-settings.ps1`.
- `.github/dependabot.yml` (github-actions), `CODEOWNERS`, conventional-commit lint, `LICENSE`.
- A short `docs/runbook.md`: how to release, how to roll back, how to test.

### 5.5 Approvals and the publish action (D11)

Decided: PRs need 1 approval, as in every other repo. `publish-nuget-org` becomes an action but the call stays the same: consumers keep calling the same reusable workflow with `secrets: inherit`, and the workflow calls `action-publish-nuget-org@v1` with `nuget-api-key` as today. Facts from the current workflows: the publish has **no `environment:` approval gate**; its only guard is the fail-closed public check inside the step; `NUGET_API_KEY` is passed from secrets.

Decisions (all recorded 2026-10-27):

| # | Point | Decision |
|---|---|---|
| 11a | Reviewers | 1 approval on every action repo, including `action-publish-nuget-org`. Same as the rest of the org |
| 11b | Reviewer coverage | All repos are org-owned and created repos remain managed by org admins, so no per-repo team or CODEOWNERS group is required. Org admins are the fallback approver, which removes the solo-maintainer deadlock |
| 11c | Stale approvals | Dismiss stale approvals on all action repos |
| 11d | Bypass | None on `action-publish-nuget-org`; admin bypass elsewhere only with the audit log reviewed |
| 11e | Who moves `v1` | Only the release workflow, from a tag on `main` |
| 11f | `environment:` gate | None. Environment-level values are org-level and held in the workflow files; repos trigger via callers and the workflow holds the actions. Adding `environment:` would change the call, so it is out of scope |
| 11g | `NUGET_API_KEY` | Stays an org secret, managed at org level, unchanged. Not re-scoped by this plan |

Consequence of 11a plus 11f: the single PR approval on `action-publish-nuget-org` and the `v1` tag rule (11e) are the only controls on the publish path, so keep the public-gate tests mandatory in that repo's required checks.

Related, already decided: a failed publish does not fail the job; it emits `::error::` plus a summary line (D10/C5). Note the risk this carries with no environment gate: nobody is watching a green run that did not publish, so the summary text is the only signal.

---

## 6. essentials-build-tools as the README and schema target

Goal: when a plugin's code changes and is pushed, its README badges and generated docs are already correct, without a person remembering a step.

**Decision (D7):** the C# dotnet tools in essentials-build-tools (`pd-readme`, `pd-schemagen`) replace `update-readme.yml` and `metadata.py`. They are the developer's tool first (VS Code tasks and MSBuild/build parameters, run locally) and a cloud step second (bonus: the same tools run after a push).

### 6.1 Layer 1: local build and VS Code tasks (build implemented in the template; tasks to add)

`src/Directory.Build.targets` on `git-config-updates`:

- **Badges** are rewritten before every local build and checked (build error on drift) when `CI=true` or `-p:ReadmeMode=Check`.
- **Docs** (marker sections) are *not* part of the normal build locally; they run on demand (`dotnet msbuild -t:UpdateReadmeDocs` or `dotnet pd-readme docs`), but **are checked in CI**.
- **VS Code tasks (to add to the template's `.vscode/tasks.json`)**: `Readme: update badges`, `Readme: update docs`, `Readme: check`, and `Schema: generate`, each wrapping the `dotnet pd-readme` / `dotnet pd-schemagen` command or the matching MSBuild target and parameter (`-p:ReadmeMode=Check|Update`). Documented in the template README so a dev never types the CLI.
- Net effect today: a developer who changes a join map or `TypeNames` and does not run the docs command gets a **CI failure** on push. That is a friction trap.

### 6.2 Layer 2: commit-time (recommended addition)

Husky.Net is already in the template and only has a `commit-msg` hook. Add a `pre-commit` task that runs `dotnet pd-readme badges` and `dotnet pd-readme docs` when staged `*.cs`/`*.csproj` change and stages `README.md`. This meets the "when changes are pushed" goal at the cheapest point: the README is part of the same commit. Document `HUSKY=0` as the escape hatch (already used for CI).

### 6.3 Layer 3: CI (what workflow-templates provides)

Two jobs, both optional per repo:

1. **Gate** (default, zero workflow change): the plugin's own targets already run `--check` under `CI=true`. workflow-templates only needs to guarantee, on every runner (`windows-latest`; the self-hosted `dmz-windows-2019` group is only used by the out-of-scope 3-Series lanes): a .NET 8+ runtime, `dotnet tool restore` working, and nuget.org reachable. If a repo's `nuget.config` lists a private feed that needs auth (see branch `feature/authenticate-github-packages-feed`), verify tool restore still resolves nuget.org.
2. **Post-push sync in the cloud (bonus, replaces `update-readme.yml`)**: optional per repo. A reusable workflow (or action `action-readme-sync`) restores the repo's pinned tool from `.config/dotnet-tools.json` (so output equals what developers see locally; default pinned version for repos without the manifest), runs `pd-readme badges` and `pd-readme docs` on push to `main`, and opens or updates a **pull request** (`robot-docs/<base>`) instead of force-pushing. Needs `contents: write, pull-requests: write` and the org setting "Allow GitHub Actions to create and approve pull requests". Built only after Layers 1 to 2 are adopted; it is the safety net, not the primary path.

### 6.4 Format changes and rollout

- `pd-readme docs` output differs from `metadata.py` (documented at the top of `ReadmeDocs.cs`: deterministic ordering, join access `R/W/RW` instead of always `R`, Config Example always regenerated, factories found by base class). The first run on an existing plugin therefore produces a diff. Ship it as a one-time "adopt pd-readme" PR per repo, not as a surprise failure.
- Any output-format change bumps the tool's minor (or major) version; the template pin and README move in the same PR. Dependabot (if it covers `dotnet-tools.json`; verify) then proposes bumps to plugins.
- Plugins target net472 or net8 only (never both), and the tools read source files and the built assembly, so no multi-targeting of the tools is needed.

### 6.5 Policy decision: when should a stale README fail?

| Option | Effect |
|---|---|
| A. Always fail (current default under `CI=true`) | Strict; blocks the web-UI-edit and rebase workflows |
| B. Fail on `main`/release builds, warn elsewhere | Lets branches go green; catches drift before release |
| C. Never fail; the auto-fix PR repairs it | Lowest friction; README can lag until the PR merges |

**Decided (D6): Option A.** The known cost is a developer who edits in the GitHub web UI (or resolves a README conflict by hand) and gets a red check they cannot fix without the tool. Mitigations that keep A workable:

- The failure message names the exact fix (`dotnet pd-readme docs` or the VS Code task `Readme: update docs`) and the README section that drifted, never a bare diff.
- Husky pre-commit hook (6.2) and VS Code tasks (6.1) make the local fix one step.
- The tool version is pinned in `.config/dotnet-tools.json`, so format changes reach a plugin only via a deliberate bump PR, not as a surprise red build (6.4).
- Revisit B if web-UI-edit failures turn out to be frequent after the canaries (Phase 4).

---

## 7. DocFX versus the current `pd-readme` (C# tool)

**Decision (D8):** deferred to a day-2/day-3 plan. Nothing in sections 8 to 10 depends on it. The analysis below is kept for that plan.

They solve different problems, so the recommendation is complementary use, not a swap.

| | `pd-readme` | DocFX |
|---|---|---|
| Output | Rewrites marker sections *inside* README.md; rewrites badges | Static site (HTML/YAML) from XML doc comments plus Markdown articles; does not edit README sections |
| Inputs it understands | Essentials conventions: `TypeNames`, `MinimumEssentialsFrameworkVersion`, `JoinData/JoinMetadata/JoinCapabilities`, feedbacks, `<example>` config blocks | Generic C# API (types, members, doc comments); no Essentials semantics |
| Needs a build | No (reads source; badges read csproj) | `docfx metadata` needs MSBuild/Roslyn with references resolved, so a restorable project; net472 + Crestron SimplSharp references are the risk |
| Hosting | None (README is the artifact) | A site per plugin. Pages for private repos needs GitHub Enterprise Cloud; ~60 consumers are private |
| CI gate | `--check` already built in | Needs its own build + deploy workflow per repo |
| Maintenance | One repo, regex parsers (fragile on unusual formatting) | A new toolchain, config (`docfx.json`) and templates per repo |

Recommendation:

1. **Keep `pd-readme` for README badges and docs.** DocFX cannot produce the join tables, supported types, or config example into README without custom plugins that would duplicate `pd-readme`.
2. **If regex fragility is the real concern**, the cheaper step is a **Roslyn syntax-tree implementation inside `pd-readme`** (no semantic model, so no restore and no Crestron references), keeping the same output. Add golden-file tests against the real plugin set to prove byte-identical output.
3. **Run a time-boxed DocFX spike (2 days) for an API reference site** only for Essentials core and PepperDashCore (public, no private-Pages problem). Spike exit criteria: `docfx metadata` succeeds on net472 and net8 builds on CI runners; a published site builds in under 5 minutes; XML doc coverage is good enough to be useful; hosting works (GitHub Pages). Outcome: go/no-go for an optional `docs-site` reusable workflow. It must not block this migration.

---

## 8. Phased plan with exit criteria

Sizing: S ≤ 1 day, M ≈ 2–4 days, L ≈ 1–2 weeks of effort. Phases 1–3 can overlap; each has a hard exit gate.

### Phase 0: unblock tools and runners (S–M)

- Resolve essentials-build-tools open questions A1–A7 (nuget reviewers, approval count, `release` branch, last-push approval, API key owner and scope, `PepperDash.` prefix reservation, repo name final). Finish protection (fix `protect-main`; `protect-release-tags`; squash-only merge settings; `nuget` environment and `NUGET_API_KEY`).
- Tag `readme-v0.1.0` and `schemagen-v0.1.0`; approve the `nuget` environment.
- Verify on `windows-latest`: .NET 8+ runtime present, nuget.org reachable, `dotnet tool restore` works under the repo's `nuget.config`.
- Verify the tools against one real net472 plugin (with Crestron SimplSharp refs) and one real net8 plugin.

Exit: both packages visible on nuget.org; a real plugin builds in CI on `windows-latest` with `ReadmeMode=Check`; a direct push to `main` is rejected on essentials-build-tools.

### Phase 1: policy and tracking (S)

- Open the epic and the child issues; record the naming decision on #49 (section 10, D1).
- Adopt the pinning/versioning policy (section 4); create the `action-template` repo (5.4) and the runbook.
- Tag the current workflow-templates `main` as `v0.9.0` (baseline), so a rollback point exists before anything changes.

Exit: policy merged as `docs/versioning-policy.md`; `action-template` repo exists with rulesets applied.

### Phase 2: split and land PR #57 in reviewable pieces (M)

1. Remove `generate-config-schema` (C2).
2. PR A: `getversion.yml` + pinned third-party actions (C6) + legacy `::warning::` steps (C8).
3. PR B: Tier 1 actions in place in workflow-templates (still `./`-style paths), with tests.
4. PR C: Essentials and plugin build lanes (net472 and net8) composing the actions.
5. PR D: VS Code tasks and docs in the template, optional post-push sync (6.3); `update-readme.yml` and `metadata.py` removed after the first successful canary.
6. PR E: `docs/migrating-callers.md` with the old→new mapping and the agent conversion prompt (detect net472 vs net8 from `<TargetFramework>`; preserve `secrets: inherit`, `needs:`, `if:`).

Exit: each PR green on `self-test.yml` (actionlint + Pester), reviewed by two people, merged to `main`. No consumer behaviour changed yet.

### Phase 3: extract action repos (M per tier)

For each of the 16 actions in the order of section 5.2: create from `action-template`, move the action and its tests, vendor `common.ps1`, release `v1.0.0`, then switch workflow-templates to `@v1` and delete the in-repo copy in the same PR. Keep one action per PR so a revert is one revert.

Exit (per tier): lane dry-run (`tests/run-workflow-local.ps1 -All`) green using released tags; no `./.github/actions/<name>` references remain for that tier.

### Phase 4: canary consumers (M)

Migrate callers in one repo of each type, using the migration guide and the agent prompt, and run each through a real release:

| Canary | Covers |
|---|---|
| `EssentialsPluginTemplate` | The template, `git-config-updates` targets, README gate |
| A public net472 plugin | Public gate: publishes to nuget.org |
| A private net472 plugin | Public gate: must **not** publish to nuget.org (C13) |
| A net8 plugin | The new net8 lane |
| `Essentials` and `PepperDashCore` | Essentials (Core) lanes, `.dll` artifacts, no package-name check |

Exit: every canary produces the expected release, nupkg (or none, for the private repo) and README state; one deliberate failing-compile run leaves **no** tag, release or package; a deliberately stale README is caught by the gate and repaired by the local VS Code task (and by the post-push sync where enabled).

### Phase 5: batch migration (L)

- Script the migration: `gh search code` to list callers, one PR per repo using the agent prompt, grouped by type, 10–15 repos per batch, each batch watched before the next.
- Update `PepperDash/.github/workflow-templates/*-caller.yml` and `.properties.json` so new repos start on the new workflows (C9).
- Track progress in the epic (a checklist per repo). Dependabot then keeps `@v1` current.

Exit: `gh search code "workflow-templates/.github/workflows/essentialsplugins-"` returns no consumer references for two consecutive weeks.

### Phase 6: retire deprecated files (S)

Delete the legacy workflows (and the dead `essentialsplugins-builds.yml`) in one PR once Phase 5's exit holds; then delete `metadata.py`, `test-scripts/`, and the old docs pages. Tag `v2.0.0` of workflow-templates if the old names were part of its public surface.

Exit: no references remain; `docs/` catalog matches what exists.

### Optional follow-ups (not blocking)

DocFX (day-2/3 plan, section 7); Roslyn-based `pd-readme` (only if a regex miss appears, D9); `pd-schemagen --portal`; pre-commit hook rolled out to all plugins via the template.

---

## 9. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Wrong action release breaks many repos | Med | High | Canaries first; `v1` tag controlled; rollback runbook; staged batches |
| Private nuget feed in a plugin's `nuget.config` breaks `dotnet tool restore` | Low–Med | Med | Source mapping for tool packages, or a `--add-source` fallback; test one such repo |
| Per-action repo overhead (16 repos) grows | High | Med | Extraction order, `action-template`, shared runbook, Dependabot, scripted `apply-repo-settings.ps1` |
| First `pd-readme` run produces README diffs in every plugin | High | Low | Planned "adopt" PR with a note in the migration guide |
| Public gate misfires on `workflow_call` context | Low | High (private code on nuget.org) | Canary pair; keep fail-closed default |

---

## 10. Decisions (all answered 2026-10-27)

| # | Decision | Status | Outcome |
|---|---|---|---|
| D1 | Reusable workflow naming | ✅ Answered | **Decided:** `{entrypoint}-{series}-{tfm}-{action}.yml` (4-Series only). Callers renamed only inside the migration PRs |
| D2 | Action repo split | ✅ Answered | **Decided:** one repo per action (16), each independently manageable. Tiers set extraction order only |
| D3 | Repo naming and visibility | ✅ Answered | **Naming decided:** `PepperDash/action-{descriptor}`. **Decided: public** (`internal` not viable, section 5.1; `workflow-templates` is public) |
| D4 | Caller pin style | ✅ Answered | **Decided:** `@v1` first-party, SHA third-party, `@main` supported until migrated |
| D5 | Remove `generate-config-schema` from #57 | ✅ Answered | **Decided:** remove |
| D6 | Stale README behaviour | ✅ Answered | **Decided: Option A** (always fail under `CI=true`), accepting the web-UI-edit friction. Mitigations in 6.5 |
| D7 | `update-readme.yml` after migration | ✅ Answered | **Decided:** replace with essentials-build-tools (VS Code tasks and build parameters locally; cloud post-push as bonus). Retire and remove `metadata.py` |
| D8 | DocFX | ✅ Answered | **Decided:** deferred to a day-2/3 plan |
| D9 | Roslyn rewrite of `pd-readme` | ✅ Answered | **Decided:** keep in the plan as contingency; trigger is a regex miss found in a real plugin; golden-file tests first |
| D10 | Publish failures non-fatal | ✅ Answered | **Decided:** job stays green; `::error::` plus job-summary message (C5) |
| D11 | Approval rules for action repos and NuGet publish | ✅ Answered | **Decided** (section 5.5): 1 approval everywhere including the publish action; stale approvals dismissed; no bypass on the publish action; only the release workflow moves `v1`; no `environment:` gate; `NUGET_API_KEY` stays an org secret |
| D12 | Work ownership | ✅ Answered | **Decided:** break the work into small items for several implementers. Draft written: `docs/workflow-actions-work-breakdown.md`; owner names still to assign |

---

## 11. Appendix: current-state facts used above

- `essentials-build-tools`: `pd-readme badges|docs [--check]` (tag `readme-v*`) and `pd-schemagen` (tag `schemagen-v*`); main has no tags yet; nuget.org returns 404 for both packages (checked 2026-10-27).
- Template `git-config-updates`: pins `pepperdash.essentials.buildtools.readme` 0.1.0 in `.config/dotnet-tools.json`; `Directory.Build.targets` calls `dotnet pd-readme` with `--check` under `CI=true`; `.husky` has only `commit-msg`.
- workflow-templates: no release tags; Dependabot configured for `github-actions` weekly; self-test workflow covers Pester + actionlint; 3-Series lanes (out of scope) run on runner group `dmz-windows-2019`; 4-Series lanes run on `windows-latest` (legacy and new alike, so no runner change in #57).
- Unpinned third-party refs: `gha-find-replace@master` in `essentialsplugins-getversion.yml`; actionlint downloaded from `main` in `self-test.yml`.
