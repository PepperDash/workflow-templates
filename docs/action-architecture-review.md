# Action Architecture Review — Decision Record (DRAFT)

**Status:** Draft, awaiting senior developer / architect decision
**Context:** Issue #49, branch `refactor/workflow-modularization-49`
**Date:** 2026-10-26
**Reviewer asks:** two decisions are needed.

1. **Repository strategy** for the composite actions: one repo, a monorepo with independent per-action versioning, or one repo per action.
2. **Action replacement list:** which PepperDash-maintained actions or steps to replace with public actions, and which to keep.

> **Provenance and caveats.** The inventory was produced by reading all 19 actions (plus the shared `_common` helpers) in `.github/actions/` and the workflows that call them. The repo-strategy guidance is general GitHub Actions practice, not a formal standard. **No current versions or availability of the public actions named here were verified.** Check each candidate (maintenance status, latest release, license, Windows runner support) before adopting it.

---

## 1. Background

The build workflows in this repo were refactored (#49) into composite actions under `.github/actions/<name>/`. Each action has an `action.yml`, a PowerShell or bash script, and Pester unit tests. Shared helpers live in `_common/`. The build lanes are:

- 3-Series plugin / Essentials
- 4-Series net472 / net8 plugin
- 4-Series Essentials

The workflows, test harness and an offline dry-runner are also in this repo. The workflows currently reference the actions as:

```
PepperDash/workflow-templates/.github/actions/<name>@refactor/workflow-modularization-49
```

That branch ref is temporary and must change before merge (see §6).

**New requirement driving this review:** different actions must be updatable at different times without breaking other repos that consume them.

---

## 2. Decision 1 — Repository strategy

### 2.1 Options

| Option | Description | Versioning unit |
|---|---|---|
| **A. Single repo, repo-wide semver** | All actions in one repo, one tag (`v1`, `v1.2.3`) for everything | The whole repo |
| **B. Monorepo, per-action tags** | All actions in one repo, each tagged independently (`get-sln-info/v1.2.0`, moving `get-sln-info/v1`) | Each action |
| **C. One repo per action** | Each action in its own repo | Each repo |

### 2.2 Key fact: pinning protects consumers

Breakage happens only when a ref that consumers float on is moved. Layout does not cause it. A consumer pinned to an exact tag or SHA never sees changes in any option. The options differ in how much release and update noise you accept and how independently an action can ship.

### 2.3 Comparison

| Concern | A. Repo-wide semver | B. Monorepo + per-action tags | C. Repo per action |
|---|---|---|---|
| Independent update timing | Weak. Any release bumps the version for all actions | Strong | Strongest |
| Breaking change in one action | Forces a new major for all | Moves only that action's major | Moves only that repo's major |
| Consumer upgrade noise | High (bump PRs for unchanged actions) | Low | Low |
| Shared tests / CI (Pester, structure guardrails, dry-runner) | One place | One place | Duplicated N times |
| Release tooling needed | Minimal | Moderate: monorepo release automation | Per-repo release setup |
| Permissions / ownership | One | One (CODEOWNERS can split) | Per repo; best for different owners |
| Marketplace publishing | Not possible (needs action at repo root) | Not possible | Possible |
| Maintenance overhead | Lowest | Low–moderate | Highest |

### 2.2.1 How each option is consumed

```yaml
# A: repo-wide
uses: PepperDash/workflow-templates/.github/actions/get-sln-info@v1

# B: per-action tag (git tag names may contain slashes)
uses: PepperDash/workflow-templates/.github/actions/get-sln-info@get-sln-info/v1

# C: own repo
uses: PepperDash/action-get-sln-info@v1
```

### 2.4 Recommendation: Option B

Per-action tags in a monorepo give the independent update timing the requirement asks for. The Pester suite, guardrails and dry-runner stay in one place, and the number of repos doesn't grow.

**Choose C for a specific action only if** it needs Marketplace publishing (action at repo root with a single `action.yml`), has a different owner or release cadence, is consumed by other teams independently, is large (JS or Docker action with its own build), or needs different access control.

**Choose A only if** consumers are few and always upgrade together. It is the cheapest option and is the fallback if the release automation in B isn't wanted. Renovate or Dependabot then handles the bumps.

### 2.5 Mechanics for Option B

- **Release automation.** release-please in monorepo (manifest) mode can cut per-action releases and tags from conventional commits. The repo already uses conventional commits and semantic-release elsewhere (see §4). Evaluate fit against the existing release tooling.
- **Moving major tags.** Maintain `<action>/v1` as a moving tag for backward-compatible changes. Never move an exact version tag (`<action>/v1.2.3`).
- **Breaking changes.** Release them under a new major (`<action>/v2`) and leave `v1` untouched.
- **Verification before moving a major tag.** Run the dry-runner and Pester suite against both the old and new refs.

### 2.6 Cross-references between actions (decisive gotcha)

- A composite action used from another repo **cannot** reference a sibling with `./.github/actions/x`. That path resolves against the caller's workspace. Sibling calls must be `org/repo/path@ref`.
- That inner ref must be pinned to a specific tag or SHA. Otherwise a consumer pinned to `create-nuspec@v1` silently picks up newer `get-project-info`.
- Keep inter-action calls to a minimum. Prefer having the **workflow compose the actions**, as the #49 build lanes already do.
- **Finding:** none of the 19 `action.yml` files calls a sibling PepperDash action. Composition happens in the workflows, so no inner-ref pinning is needed today. Third-party calls inside actions (`upload-release` → `ncipollo/release-action`, `actions/download-artifact`; `generate-config-schema` → `actions/setup-dotnet`, `actions/upload-artifact`; `dotnet-build` → `actions/upload-artifact`; `docker-build-3series` → `azure/docker-login`; `pack-nuget` → `nuget/setup-nuget`) are pinned like any other third-party action.
- **Hidden coupling to decide on:** the scripts dot-source the shared helpers via a relative path (`$PSScriptRoot/../../_common/action.ps1` / `action.sh`). GitHub fetches the whole repo at the referenced ref, so this works. But with per-action tags (Option B), a change to `_common/` is effectively a change to every action that uses it. Options: (a) treat `_common` as its own versioned unit and re-release all dependents when it changes, (b) keep `_common` strictly backward-compatible, or (c) copy the helpers into each action (this would be needed for Option C). This is a deciding factor for Option B vs. C.

### 2.7 General practices (apply to every option)

- Reusable **workflows** must live in `.github/workflows/` at the repo root. They cannot be in sub-folders. Composite actions have no such restriction.
- Pin consumers to a tag or SHA. Provide a moving major tag for convenience. Use a SHA for anything security-sensitive.
- If the repo is private or internal, set the repo's Actions access setting so other repos in the org can use it.
- Keep Pester tests, scripts and `action.yml` co-located per action.
- GitHub's own `actions/*` org uses one repo per action because each is a public Marketplace product. That is not a reason to copy the pattern for internal shared actions.

---

## 3. Decision 2 — Action replacement list

Inventory of all 19 actions plus third-party steps used by the workflows. "Public" means GitHub-maintained, Docker-maintained, or an established third-party action. Third-party actions carry supply-chain risk, so pin them by SHA.

### 3.1 Candidates to replace with public actions

| # | PepperDash action / step | Replace with | Effort | Notes |
|---|---|---|---|---|
| 1 | `essentialsplugins-builds.yml:232,248`: `fleskesvor/create-release@feature/support-target-commitish` and `actions/upload-release-asset@v1` | `ncipollo/release-action` | Low | **Highest priority.** One is a feature-branch ref of a third-party fork, the other is archived and deprecated. Every other lane already uses ncipollo. |
| 2 | `jacobtomlinson/gha-find-replace` (4 uses; 2 pinned `@master`, 2 `@v3`) in `getversion.yml` and `essentialsplugins-getversion.yml` | Inline `sed` / `pwsh -replace`, or pass the branch to semantic-release via `--branches` | Low | Third-party dependency for a one-line substitution. `@master` is unpinned. |
| 3 | `azure/docker-login@v2` (`docker-build-3series` plus workflow-level uses in `essentials-3Series-builds.yml:96`, `essentialsplugins-builds.yml:161`, `essentialsplugins-3Series-builds.yml:96`) | `docker/login-action` | Low | Replaces the login step only. The sspbuilder build itself stays custom. |
| 4 | `publish-nuget-github` | `actions/setup-dotnet` with `source-url` + `NUGET_AUTH_TOKEN`, then `dotnet nuget push --skip-duplicate` | Low | Official, no extra action. The script is mostly a loop around `nuget push`. |
| 5 | `publish-nuget-org` (the push step only) | `dotnet nuget push`, or `NuGet/login` for trusted publishing (OIDC) | Low–Med | OIDC removes the stored API key. Verify `NuGet/login` availability and nuget.org trusted-publishing setup for the org. **Keep the owner/public gate** (see §3.2). |
| 6 | `pack-nuget` | Inline `nuget pack` or `dotnet pack` step (`nuget/setup-nuget` already used) | Low | About 5 lines plus the template-repo skip, which becomes an `if:`. |
| 7 | `upload-release` (wrapper) | `ncipollo/release-action` directly | Low | The wrapper already calls it. The remaining value is changelog download, `validate.sh`, `ensure-body.sh`. Keep the wrapper only if those conventions should stay centralized. |
| 8 | `dotnet-build` | Inline `dotnet build` | Low | Extras are the log artifact and the summary. Optional; reasonable to keep. |
| 9 | `cleanup-failed-release` | Optional: `dev-drprasad/delete-tag-and-release` | Low | Third-party. The `gh` + `git` script is small and works. Recommendation: keep. |

### 3.2 PepperDash-owned actions to keep (no public equivalent)

| Group | Actions | Why custom |
|---|---|---|
| Naming / metadata | `get-project-info`, `get-plugin-metadata`, `check-package-name`, `apply-essentials-version-prefix` | Encode the `org/epi-make-model` repo-naming convention, Essentials factory `TypeNames` / `MinimumEssentialsFrameworkVersion` extraction, and the Essentials-major version prefix (`prefixed_major = Essentials major × 1000 + semver major % 1000`). |
| Packaging | `create-nuspec`, `copy-build-output`, `add-files-to-nupkg`, `embed-devtools-spa` | Crestron artifacts (`.cpz`/`.clz`/`.cplz`), nuspec generation, injecting files into `.nupkg`, and embedding the devtools SPA zip into `.cpz`. |
| Config schema | `generate-config-schema` | Auto-detects `dc.Properties.ToObject<T>()` config types and reflects them with NJsonSchema (includes a small C# generator project). |
| Legacy / platform | `update-assembly-info`, `docker-build-3series` | Rewrites legacy `AssemblyInfo.cs/.vb` (skip for SDK-style `/p:Version`); sspbuilder Docker build for 3-Series. |
| Publishing gate | the fail-closed owner/visibility check in `publish-nuget-org` | Single source of truth for public publishing. Keep it even if the push is replaced. It could move to a workflow `if:` on `github.repository_owner` and `github.event.repository.visibility`, which is more visible. |
| Borderline | `get-sln-info` | Could be an inline `Get-ChildItem`, but its outputs are shared across lanes. Recommendation: keep. |

### 3.3 Already using official or standard actions (no change)
`actions/checkout`, `actions/upload-artifact`, `actions/download-artifact`, `actions/setup-dotnet`, `actions/setup-node`, `actions/setup-python`, `nuget/setup-nuget`, `microsoft/setup-msbuild`, `ncipollo/release-action`.

### 3.4 Versioning (`getversion.yml`)
Version and changelog come from semantic-release run via `npx`, with `conventional-changelog-conventionalcommits` pinned to 9 (workflow comments document a template incompatibility with v10+). Public alternatives exist (`gittools/actions` GitVersion, `cycjimmy/semantic-release-action`).

**Recommendation: do not switch.** GitVersion changes how versions are derived and would lose the changelog output. The wrapper action makes the plugin-version pin harder to control.

### 3.5 Suggested order of work
1. Replace `fleskesvor/create-release` + `actions/upload-release-asset` with `ncipollo/release-action` (item 1).
2. Replace `gha-find-replace` (item 2).
3. Swap `azure/docker-login` for `docker/login-action` (item 3).
4. Retire `publish-nuget-github` and `pack-nuget` for inline `dotnet`/`nuget` steps (items 4, 6) and evaluate OIDC for nuget.org (item 5).
5. Decide on the thin wrappers (items 7–9) after Decision 1, since the repo strategy affects how much a wrapper costs to maintain.

---

## 4. Related observations

- **Own-action refs.** All internal `uses:` point at `@refactor/workflow-modularization-49`. They must move to tags (per Decision 1) before merge.
- **Third-party pinning.** Pin remaining third-party actions to a commit SHA. Dependabot is already configured (`.github/dependabot.yml`) and can maintain SHA pins.
- **Self-hosted runner constraint.** `cleanup-failed-release` documents that `gh` + Git Bash are verified only on `ubuntu-latest` and `windows-latest`, not on the self-hosted `dmz-windows-2019` group. Any replacement must respect the runner groups in use.
- **Path-stripping assumption.** `get-sln-info` computes `solution-path` by removing the first four path segments, which assumes a Windows hosted-runner workspace layout (such as `D:\a\repo\repo\`). That is fine for the Docker lane today but would produce the wrong path on Linux runners. Out of scope for this decision, flagged for awareness.

## 5. Decisions requested

| # | Decision | Recommended | Alternatives |
|---|---|---|---|
| D1 | Repository strategy | **B.** Monorepo with per-action tags, using release-please manifest mode | A: repo-wide semver (simplest). C: per-action repos only for actions with Marketplace, ownership, or separate-lifecycle needs |
| D2 | Replacement list | Approve items 1–4 and 6; evaluate 5 (OIDC); defer 7–9 to after D1 | Keep wrappers for central conventions |
| D3 | Release automation for D1-B | release-please (monorepo/manifest) | Hand-managed tags with a documented script |
| D4 | Third-party pinning policy | SHA pins, maintained by Dependabot | Tag pins for GitHub-owned actions only |

## 6. Open items before implementation
- Confirm the current version, maintenance status, license and Windows support of every public action chosen (not verified in this review).
- Decide how `_common/` is versioned under Option B (see §2.6, "Hidden coupling").
- Replace the `@refactor/workflow-modularization-49` refs with the chosen tag scheme.
- Confirm Actions access settings so other org repos (essentials-build-tools, plugin-template) can consume the actions.
- Run the dry-runner (`docs/testing.md`) and Pester suite against old and new refs when changing any action.
