# CI/CD plan: reset

Status: **draft, 2026-11-05** · Supersedes `workflow-actions-migration-plan.md` and `workflow-actions-work-breakdown.md` (plus their plain-language copies). Those stay in the repo as reference. Where they disagree with this page, this page wins.

Goal: a pipeline that is hard to break and easy to change. A fix to one step should not mean editing a 300-line workflow, and a bad change should not reach every plugin repo at once.

Scope: 4-Series (net472 and net8). 3-Series / Essentials v1 stays out of scope.

---

## 1. Where things actually stand (verified 2026-11-05)

| Fact | Evidence |
|---|---|
| Nothing from PR #57 is on `main`. The new lanes pin their actions to `@refactor/workflow-modularization-49`, so they cannot be merged as they are. | `plugin-4series-net472-build.yml` header comment |
| The scope cut agreed earlier (drop `generate-config-schema` and the 3-Series lanes) has not been made on the branch. | Both are still in the tree |
| Neither build-tools package is on nuget.org. Both return 404, unchanged since 2026-10-27. essentials-build-tools has no tags. | `curl` against the nuget flat container |
| The template branch `git-config-updates` pins `pepperdash.essentials.buildtools.readme` 0.1.0, so `dotnet tool restore` fails there. | `.config/dotnet-tools.json` |
| The template's caller still uses `essentialsplugins-*@main`. About 115 repos do the same, so any merge to `main` reaches all of them immediately. | template `EssentialsPlugins-builds-caller.yml` |
| The schema extractor lives only in essentials-build-tools (`feature/metadata-extract`, not merged). The `tools/metadata-extract/` folder here is untracked build output. | `git ls-files tools` is empty |

The earlier plan grew to 16 action repos, 7 streams and 12 decisions. That is why it is hard to follow. This page keeps only what lowers risk, in the order it lowers it.

---

## 2. Steps, in order

Each step ships on its own and has one check that says it is done.

### Step 1. Unblock the tools

Publish `readme` and `schemagen` from essentials-build-tools (merge `feature/metadata-extract`, tag, approve the `nuget` environment). If publishing is not ready this week, unpin the tool from the template branch instead so it can build.

Done when: `dotnet tool restore` works on a clean machine and in the template's CI.

### Step 2. Stop consumers riding `main`

This is the biggest robustness gain available, and it needs no refactor.

- Tag `workflow-templates` (`v0.9.0` as the baseline, then `v1`) and move callers from `@main` to the tag.
- A `uses:` line cannot take an expression, and a reusable workflow's own action references are resolved from the workflow's repo, not the caller's. So the actions a workflow calls must be pinned to the same tag. Use one of:
  - a moving `v1` tag that the release workflow moves, with the actions in the same repo; or
  - a release step that rewrites the action refs to the exact tag.
- Restrict who can create or move `v*` tags (tag ruleset).
- Dependabot already covers `github-actions` here. Pin third-party actions by SHA (`jacobtomlinson/gha-find-replace@master` in `essentialsplugins-getversion.yml`, `actionlint` downloaded from `main` in `self-test.yml`).

Done when: a deliberately broken commit on `main` does not change what a pinned caller runs.

### Step 3. Harden the existing monolith

Fix these in `essentialsplugins-4Series-builds.yml` first. They are small and each one removes a real failure mode. The same list becomes the checklist for the new lane.

| Gap in the file today | Fix |
|---|---|
| Package-name check is `continue-on-error: true`, so a mismatch never blocks | Make it blocking, or fail loudly with `::error::` |
| All three publish steps are `continue-on-error: true`, so a run can be green with no package | Keep non-fatal if wanted, but add a final `if: always()` step that emits `::error::` and a summary line when an expected publish did not happen |
| `${{ inputs.* }}` and `${{ secrets.GITHUB_TOKEN }}` are interpolated straight into `run:` scripts | Pass them through `env:` and read `$env:NAME` (stops injection through inputs, keeps secrets out of command lines) |
| No `concurrency:` group, so two pushes can race on tagging | `concurrency: group: build-${{ github.ref }}` |
| No `permissions:` block (the reusable workflow inherits the caller's token) | Declare `contents: write, packages: write` explicitly |
| No `timeout-minutes` | Set one per job |
| `shell: powershell` mixed with `shell: pwsh` | Standardise on `pwsh` |
| Legacy `essentialsplugins-getversion.yml` creates the tag and release before the build | Already fixed by `getversion.yml`; move callers to it |

Done when: each row is closed or consciously declined in the PR.

### Step 4. Land one modular lane

Pick **plugin net472** only. Cut `generate-config-schema` and the 3-Series pieces from the branch first (the existing C1 item), then take the lane to parity with the monolith:

- Pin its actions per Step 2 (no feature-branch refs).
- Keep the actions inside `workflow-templates` for now (see decision D-A below).
- Canary it on `EssentialsPluginTemplate`, one public plugin and one private plugin. Public must publish to nuget.org, private must not.
- Force a failing compile once and confirm it leaves no tag, release or package.

Done when: those three canaries and the failing-compile test behave as stated, from a real run.

### Step 5. README tooling (separate track)

After Step 1. In the template:

1. VS Code tasks: `Readme: update badges`, `Readme: update docs`, `Readme: check`, `Schema: generate`.
2. Husky `pre-commit` hook that runs the tool on staged `*.cs` / `*.csproj` and stages `README.md` (`HUSKY=0` to skip).
3. Failure messages that name the drifted section and the exact fix command.
4. Only then, optionally, a post-push sync that opens a PR (replaces `update-readme.yml` and `metadata.py`).

Done when: changing a join map and committing produces a commit that already contains the README change.

### Step 6. Deferred, on purpose

net8 and Essentials/Core lanes (copy the net472 lane once it is proven), cloud README sync, DocFX, the Roslyn rewrite of `pd-readme`, migrating the ~115 callers in batches, deleting the legacy workflows. None of these block anything above.

---

## 3. Decisions to confirm

I have assumed the recommended answer below so work can start. Change either and the plan adjusts.

**D-A. Action repo layout.** Earlier decision D2 was 16 repos, one per action. Your goal ("change one action without touching the monolith") is met by composite actions in one versioned repo. Sixteen repos multiply release workflows, rulesets, Dependabot config and test setup by sixteen, and that overhead is most of the old plan's size.
Recommendation: keep actions in `workflow-templates`, versioned by the `v1` tag. Split a single action into its own repo only when it needs its own release cadence or owner (the publish action is the likeliest). This does not close the door on D2; it defers it until there is a reason.

**D-B. Non-fatal publish (earlier D10).** "Job stays green when the publish failed" conflicts with "bulletproof". With no environment approval gate on the publish path, a green run without a package is easy to miss.
Recommendation: keep publish steps non-fatal only if the final `::error::` plus summary step exists and the run is visibly marked. Otherwise make the nuget.org push fail the job.

---

## 4. What not to do

- Do not merge the branch with feature-branch action refs.
- Do not delete a legacy workflow while any repo still calls it (`gh search code` first).
- Do not start extracting action repos before Steps 1 to 4 are done.
