# Workflow actions migration: work breakdown

Status: **draft for assignment** · Written 2026-10-27 · Implements `docs/workflow-actions-migration-plan.md` (all decisions D1–D12 recorded there; section numbers below refer to it).

How to use this document: each row is one work item sized for one person and one PR (or one settings change). Pick an item whose dependencies are done, put your name in **Owner**, and open an issue titled with the item ID. Sizes: **S** ≤ 1 day, **M** 2–4 days, **L** ≈ 1–2 weeks.

Out of scope everywhere: 3-Series / Essentials v1 (plan section 1), DocFX (day-2/3 plan), Roslyn rewrite of `pd-readme` (contingency, D9).

---

## 1. Streams and order

Streams A and B start immediately and run in parallel. Everything in C waits on the gate named in its row.

| Stream | Purpose | Starts when | Can run in parallel with |
|---|---|---|---|
| **A. Tools** | Publish the essentials-build-tools packages and verify them | now | B |
| **B. Policy and repo template** | Versioning rules, `action-template` repo, repo-settings script | now | A |
| **C. Land PR #57 in pieces** | Split the existing branch into reviewable PRs | B1 done for C4 onward; C1–C3 start now | D (after C-gate) |
| **D. Extract 16 action repos** | One repo per action | `action-template` exists (B3) and C3 merged | E, F |
| **E. Developer tooling** | VS Code tasks, pre-commit hook, README gate behaviour | A3 done | D |
| **F. Cross-cutting fixes** | Publish-failure reporting, legacy warnings, pinning | now (independent items) | all |
| **G. Canaries, migration, retirement** | Prove it on real repos, migrate ~115 callers, delete legacy | gates in section 4 | none; sequential |

---

## 2. Work items

### Stream A: Tools (essentials-build-tools)

| ID | Item | Size | Depends on | Done when |
|---|---|---|---|---|
| A1 | Resolve open questions A1–A7 from the essentials-build-tools plan (nuget reviewers, approval count, `release` branch, last-push approval, API key owner and scope, `PepperDash.` prefix reservation, final repo name) | S | none | Answers recorded in that repo's docs |
| A2 | Finish repo protection: fix `protect-main`, add `protect-release-tags`, squash-only merges, `nuget` environment and `NUGET_API_KEY` | S | A1 | Direct push to `main` rejected (test it) |
| A3 | Tag `readme-v0.1.0` and `schemagen-v0.1.0`, approve the `nuget` environment, publish | S | A2 | Both packages visible on nuget.org, `dotnet tool restore` works from a clean machine |
| A4 | Verify tools on a `windows-latest` runner: .NET 8+ present, nuget.org reachable, tool restore works under a repo `nuget.config` with a private feed (branch `feature/authenticate-github-packages-feed`) | S | A3 | Written result in the plan appendix; risk "private feed breaks tool restore" closed or mitigated |
| A5 | Verify `pd-readme` against one real net472 plugin (Crestron SimplSharp refs) and one real net8 plugin, with `ReadmeMode=Check` in CI | M | A3 | Both build green in CI; the first-run README diff for each is recorded (plan 6.4) |

### Stream B: Policy and repo template

| ID | Item | Size | Depends on | Done when |
|---|---|---|---|---|
| B1 | Open the epic and child issues from this document; record naming decision D1 on #49 and close #49 against it | S | none | Epic links one issue per item |
| B2 | Write `docs/versioning-policy.md` from plan section 4 (semver plus moving `vMAJOR`, pin styles, rollback hop order, release semantics) | S | none | Merged, reviewed |
| B3 | Create `PepperDash/action-template` (plan 5.4): `action.yml` skeleton, `scripts/` with vendored `common.ps1`, Pester + `actionlint` (SHA-pinned) CI, `release.yml`, Dependabot, CODEOWNERS, `LICENSE`, `docs/runbook.md`, and a CI check that fails when the vendored `common.ps1` drifts from the template | M | B2 | A throwaway repo created from it passes CI and can release `v0.0.1` |
| B4 | Write `scripts/apply-repo-settings.ps1` for action repos per plan 5.5: `protect-main` (PR, **1 approval**, dismiss stale approvals, required checks, linear history), `protect-release-tags` (only the release workflow may create or move `v*`), no bypass on `action-publish-nuget-org`, repo public | M | B3 | Script is idempotent; applied to the throwaway repo; second run changes nothing |
| B5 | Tag current `workflow-templates` `main` as `v0.9.0` (rollback baseline) | S | none | Tag exists |

### Stream C: Land PR #57 in reviewable pieces

Branch: `refactor/workflow-modularization-49`. One PR per row.

| ID | Item | Size | Depends on | Done when |
|---|---|---|---|---|
| C1 | **Scope cut:** remove `generate-config-schema` (C2), its Pester tests and `schema-gen/`, and its lane steps; remove the 3-Series lanes (`essentials-3series-net35-build.yml`, `plugin-3series-net35-build.yml`), `docker-build-3series`, the Essentials-v1 prefix branch, and their Pester/dry-runner coverage | M | none | `self-test.yml` green; no reference to the removed items remains (grep) |
| C2 | **PR A:** `getversion.yml`, third-party refs pinned by SHA (C6), `gha-find-replace` replaced by a `sed`/pwsh step | S | C1 | Green; no `@master`/`@main` third-party refs |
| C3 | **PR B:** Tier-1 actions in place (`./`-style paths) with tests; `pwsh` invocation fixed once (C11) | M | C1 | Pester green; actions call scripts without nested `pwsh` |
| C4 | **PR C:** Essentials and plugin 4-Series net472 and net8 lanes composing the actions (4 lanes plus essentials) | M | C3 | `tests/run-workflow-local.ps1 -All` green |
| C5 | **PR E:** `docs/migrating-callers.md`: old→new file mapping, the agent conversion prompt (detect net472 vs net8 from `<TargetFramework>`; keep `secrets: inherit`, `needs:`, `if:`) | S | C4 | Reviewed by someone who did not write the lanes |
| C6 | Delete dead `essentialsplugins-builds.yml` (C12) after confirming no caller references it (`gh search code`) | S | none | Merged on its own |

PR D (readme tooling) is stream E.

### Stream D: Extract the 16 action repos

**D0** (once, M, depends on B3, B4, C3): make `tests/run-workflow-local.ps1` and `tests/pester/_helpers.ps1` resolve actions through an `actions.lock` manifest (tag per action) instead of sibling folders, so lane tests keep working after actions leave the repo (plan 5.3). Done when the dry-runner passes with at least one action resolved from a released tag.

Then one row per action. Every extraction item uses the **same checklist** (section 3) and is size **S** unless noted. Items in the same wave are independent and can go to different people at the same time.

| Wave | Items (repo is `PepperDash/action-<name>`) | Depends on |
|---|---|---|
| **1** | D1 `publish-nuget-org` (M: owns the public gate, must keep the gate tests as a **required check**), D2 `publish-nuget-github`, D3 `apply-essentials-version-prefix`, D4 `upload-release`, D5 `cleanup-failed-release`, D6 `embed-devtools-spa` | D0 |
| **2** | D7 `dotnet-build`, D8 `copy-build-output`, D9 `create-nuspec`, D10 `pack-nuget`, D11 `add-files-to-nupkg`, D12 `check-package-name` | Wave 1 merged and C4 merged (interfaces settled) |
| **3** | D13 `get-sln-info`, D14 `get-project-info`, D15 `get-plugin-metadata`, D16 `update-assembly-info` | Wave 2 merged |

Wave exit: lane dry-run green using released tags; no `./.github/actions/<name>` reference remains for that wave's actions.

### Stream E: Developer tooling (README gate, decisions D6/D7)

| ID | Item | Size | Depends on | Done when |
|---|---|---|---|---|
| E1 | Add VS Code tasks to the template: `Readme: update badges`, `Readme: update docs`, `Readme: check`, `Schema: generate` (`dotnet pd-readme` / `pd-schemagen` or MSBuild `-p:ReadmeMode=`), documented in the template README | S | A3 | Each task runs on a fresh clone |
| E2 | Failure messages for Option A: when the README gate fails, print the drifted section and the exact fix command or task name (tool change in essentials-build-tools plus a template check) | M | A3 | A deliberately stale README produces a message a new developer can act on without help |
| E3 | Husky `pre-commit` hook in the template: on staged `*.cs`/`*.csproj`, run `pd-readme badges` and `docs`, stage `README.md`; honour `HUSKY=0` | S | A3 | Committing a join-map change produces a commit that includes the README change |
| E4 | **PR D:** optional post-push sync in the cloud (plan 6.3 item 2), PR-based, opt-in per repo, pinned tool from `.config/dotnet-tools.json`; then remove `update-readme.yml` and `metadata.py` after the first successful canary | M | E1, E2, G1 | A stale README on `main` yields a `robot-docs/main` PR; legacy files deleted |
| E5 | Confirm Dependabot covers `.config/dotnet-tools.json`; if not, a scheduled check that opens an issue on tool updates | S | A3 | Documented result |
| E6 | One-time "adopt pd-readme" PR template and checklist (first run diffs every plugin, plan 6.4) | S | A5 | Template merged; used by G3 |

### Stream F: Cross-cutting fixes (all independent)

| ID | Item | Size | Depends on | Done when |
|---|---|---|---|---|
| F1 | `report-publish-status` step (C5/D10): non-fatal publish, final `if: always()` step emits `::error::<registry, package, failing step>` and appends the same text to `$GITHUB_STEP_SUMMARY`; job result unchanged | M | C3 | A forced publish failure leaves a green job with the error annotation and summary line (test in Pester and one real run) |
| F2 | `::warning::` step in every remaining legacy 4-Series workflow naming its replacement and `migrating-callers.md` (C8); behaviour unchanged | S | C5 | Warning visible on a legacy run |
| F3 | Pin `actionlint` download in `self-test.yml` by version and checksum (C6) | S | none | No `curl …/main/` remains |
| F4 | Confirm `github.event.repository.visibility` behaviour inside `workflow_call` on a real public and private repo pair (C13) | S | C4 | Opposite outcomes recorded; fail-closed default confirmed |

### Stream G: Canaries, migration, retirement

| ID | Item | Size | Depends on | Done when |
|---|---|---|---|---|
| G1 | Canary: `EssentialsPluginTemplate` migrated, README gate on | M | C4, E1–E3, Wave 2 | Real release produces the expected package and README state |
| G2 | Canaries: public net472 plugin (publishes to nuget.org), private net472 plugin (must **not** publish), net8 plugin | M | G1, F4 | Public publishes, private does not; a deliberate failing compile leaves **no** tag, release or package |
| G3 | Canaries: `Essentials` and `PepperDashCore` (Core lanes, `.dll` artifacts, no package-name check) | M | G1 | Expected release artifacts |
| G4 | Update `PepperDash/.github/workflow-templates/*-caller.yml` and `.properties.json` so new repos start on the new workflows (C9) | S | G2, G3 | New repo from a starter uses `@v1` workflows |
| G5 | Migration script: `gh search code` to list callers, one PR per repo from the agent prompt, grouped by type | M | G2, G3 | Dry run lists all callers and generates PRs without opening them |
| G6 | Batch migration, 10–15 repos per batch, each batch watched before the next | L | G5, Wave 3, F2 | Tracking checklist in the epic is complete |
| G7 | Retirement: delete legacy workflows, `metadata.py`, `test-scripts/`, old docs; tag `v2.0.0` if old names were public surface | S | G6 plus two clean weeks (plan 8, Phase 5 exit) | `gh search code` returns no references; docs match what exists |

---

## 3. Per-action extraction checklist (D1–D16)

Copy this into each extraction issue.

1. Create `PepperDash/action-<name>` from `action-template`; run `apply-repo-settings.ps1` (public, 1 approval, stale approvals dismissed, tag ruleset). Publish action: no bypass.
2. Move `action.yml`, `scripts/` and the action's Pester tests; vendor `common.ps1`; remove the `../../_common` path.
3. Write the README input/output table and a usage snippet.
4. CI green on the action repo (Pester, `actionlint`, vendored-file drift check, smoke workflow calling the action by `./` path).
5. Release `v1.0.0` through the release workflow and confirm `v1` points at it.
6. In `workflow-templates`: switch the `uses:` lines to `@v1`, add the tag to `actions.lock`, delete the in-repo copy, in one PR. A revert is one revert.
7. Run `tests/run-workflow-local.ps1 -All`; attach the result to the PR.
8. Add the repo to the epic checklist and CODEOWNERS if the org requires it.

---

## 4. Gates

| Gate | Condition | Unblocks |
|---|---|---|
| **G-tools** | A3 done (both packages on nuget.org) | A4, A5, E1–E3, E5 |
| **G-land** | C1–C4 merged to `main` with `self-test.yml` green and two reviewers | Stream D wave 2 |
| **G-extract** | Wave 1 released and consumed through `@v1` | Wave 2 |
| **G-canary** | G1–G3 each produce the expected release | G4–G6 |
| **G-retire** | Two consecutive weeks with no consumer references to legacy workflows | G7 |

Rollback at any point: move `v1` of the offending action back to the previous good tag (leaf action first, plan section 4).

---

## 5. Suggested split for several implementers

| Person | Items | Why |
|---|---|---|
| 1. Tools owner | A1–A5, E2, E5 | Lives in essentials-build-tools |
| 2. Repo/policy owner | B1–B5, D0, F3 | Owns `action-template`, settings script and `actions.lock` |
| 3. Lane owner | C1–C6, F4 | Knows the PR #57 branch |
| 4. Template/dev-tooling owner | E1, E3, E4, E6, G1 | Owns `EssentialsPluginTemplate` |
| 5–6. Extraction implementers | Waves 1–3 (D1–D16), split by wave | Same checklist, independent repos |
| 7. Reliability owner | F1, F2 | Publish reporting and legacy warnings |
| Rotating | G2–G7 | Needs one person per canary type, then the migration lead |

Rules that keep parallel work from colliding: one action per PR; never change another action's repo from your item; any change to `action-template` after B3 is a separate PR announced in the epic, because vendored `common.ps1` copies must be refreshed.

---

## 6. Open items for the assigner

- Owner names for each row (section 5 is a suggestion).
- The `NUGET_API_KEY` org-level scope and nuget.org key expiry were not verified in this plan; A1 should record them in the runbook.
- Confirm the org setting "Allow GitHub Actions to create and approve pull requests" is acceptable before E4.
