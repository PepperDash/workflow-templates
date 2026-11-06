# NuGet.org Trusted Publishing: plan to retire `NUGET_API_KEY`

Status: **draft v1** · Written 2026-11-06 · Scope: 4-Series workflows only (3-Series / Essentials v1 stays on the API key, see section 3).

## 1. Why

On 2026-11-05 the org secret `NUGET_API_KEY` expired. Every publish to nuget.org returned
`403 (The specified API key has expired)`, and nobody noticed for a while because the publish step is
`continue-on-error: true` (for example `essentialsplugins-4Series-builds.yml`, "Publish to Nuget.org (public repos only)"). The job
stayed green and no packages reached nuget.org. Evidence: PepperDash/Essentials run 42106416531 and
PepperDash/epi-crestron-nvx run 42234059171.

Long-lived API keys have two recurring costs: a hard expiry (365 days max) that fails silently, and a secret
that every caller can read through `secrets: inherit` on `@main`. Trusted Publishing replaces the key with a
short-lived credential that GitHub issues per run.

## 2. How Trusted Publishing works (as documented)

1. The job requests an OIDC token from GitHub (needs `permissions: id-token: write`).
2. `NuGet/login@v1` sends the token and the nuget.org username to nuget.org.
3. nuget.org checks the token against a **trusted publishing policy** (repo owner, repo, workflow filename, optional environment) and returns an API key valid for about 1 hour.
4. The workflow pushes with that key.

A new policy must see one successful login within 7 days to become permanent. After that it is bound to
GitHub's immutable repo and owner IDs. A missed window can be re-activated for another 7 days. The feature was
being rolled out gradually, so the account may not show it yet.

Sources: [Microsoft Learn](https://learn.microsoft.com/nuget/nuget-org/trusted-publishing),
[.NET blog](https://devblogs.microsoft.com/dotnet/enhanced-security-is-here-with-the-new-trust-publishing-on-nuget-org/),
[Andrew Lock](https://andrewlock.net/easily-publishing-nuget-packages-from-github-actions-with-trusted-publishing).

## 3. What changes for us

| Area | Today | With Trusted Publishing |
|---|---|---|
| Credential | Org secret `NUGET_API_KEY` | None stored; per-run key, about 1 hour |
| Publish step | `nuget setApiKey ${{ secrets.NUGET_API_KEY }}` inline in each workflow, and `publish-nuget-org` in the #49 actions | `NuGet/login@v1` then push with the returned key |
| Caller permissions | Callers need nothing for nuget | Every publishing caller job needs `id-token: write` (a reusable workflow cannot grant itself more than its caller gives) |
| nuget.org setup | One key by the account owner | One policy per publishing repo (and per workflow file, see Q1) |
| Rotation | Manual yearly | None |
| Secret exposure | `secrets: inherit` with `@main` exposes it to every caller | No secret to expose; trust is scoped to repo + workflow file |

**Not fixed by this change:** the `continue-on-error: true` masking, and prerelease packages from feature-branch
pushes being published to nuget.org. Both are handled separately in Phase 1.

**3-Series stays on the key.** `essentials-3Series-builds.yml` and `essentialsplugins-3Series-builds.yml` are out
of scope for the actions migration. If they keep publishing, `NUGET_API_KEY` cannot be deleted. It can only be
scoped down, until they are retired or given the same change.

## 4. Open questions (resolve in the pilot)

| # | Question | Why it matters | How to resolve |
|---|---|---|---|
| Q1 | Does the policy's "workflow filename" match the **caller** workflow or the **reusable** workflow that runs the login step? | Decides one shared policy versus one policy per caller repo | Pilot on one repo; read the OIDC claims (`workflow_ref` vs `job_workflow_ref`) and try to create the policy against each |
| Q2 | Is Trusted Publishing enabled on our nuget.org account/org? | Blocks everything | Check the nuget.org user menu for "Trusted Publishing" |
| Q3 | Which nuget.org account owns the packages, and who can create policies? | Policies are created by the owner | Record in the runbook (also open item A1/A5 in the migration plan) |
| Q4 | Do packages use IDs outside `PepperDash.*`? | Affects fallback key scope: `PepperDashCore` and `PepperDashEssentials` exist | Keep the fallback key glob at `PepperDash.*,PepperDash*` |
| Q5 | Do private or pre-release flows need an `environment:` on the policy? | Optional extra gate | Decide after Q1 |

## 5. Phases

### Phase 0: restore publishing now (stopgap, no code)

- Create a new nuget.org API key: glob `PepperDash.*,PepperDash*`, Push scope, 365 days. Set a calendar reminder two weeks before expiry.
- Update the **org** secret `NUGET_API_KEY`. Confirm the secret's "Updated" date is today and the publishing repos are in its access list.
- Re-run a known-failed publish (Essentials run 42106416531 build job; epi-crestron-nvx run 42234059171). The push uses `-SkipDuplicate`, so a re-run is safe.
- **Done when:** a re-run shows `Your package was pushed` against nuget.org and the packages appear on nuget.org.

### Phase 1: make failures visible (independent of auth method)

- Remove `continue-on-error: true` from the publish step, or keep it but add a final step that fails the job when the push failed. Decide which.
- Surface a clear summary line (`❌ Failed to push <pkg>: <reason>`) in the step summary, as `publish-nuget-org.ps1` already does.
- Decide whether feature-branch prerelease pushes should go to nuget.org at all. Proposed: GitHub Packages only for non-`main`/`release` branches.
- **Done when:** an intentionally bad key produces a red check.

### Phase 2: pilot Trusted Publishing on one repo

- Pick one low-risk public plugin repo (not Essentials).
- On nuget.org, create a policy for that repo and its workflow file. Try the caller filename first, then the reusable one if Q1 requires it.
- Add `permissions: id-token: write` to the caller's publish job. Add a `NuGet/login@v1` step to the publish path with the nuget.org username, guarded so it only runs when the repo is a public PepperDash repo (same guard as today).
- Push with the returned key. Keep the secret path available behind an input so a rollback is one line.
- Trigger a publish and confirm the policy activates (within the 7-day window).
- **Done when:** a pilot publish succeeds with no `NUGET_API_KEY` in the job, Q1 and Q2 are answered, and the answer is recorded here.

### Phase 3: put it in the actions

- Update `publish-nuget-org` (to become `action-publish-nuget-org@v1`, see D11 in the migration plan) to run `NuGet/login@v1` and drop the `nuget-api-key` input. Keep a deprecated optional input for one release so callers can migrate gradually. Release as a new minor, not a breaking change, until callers are done.
- Update the 4-Series reusable workflows (`essentials-4series-net472/net8-build`, `plugin-4series-net472/net8-build`) to stop passing the secret.
- Amend D11 / 11g ("`NUGET_API_KEY` stays an org secret, unchanged") to reflect this.
- Update the legacy 4-Series workflow (`essentialsplugins-4Series-builds.yml`) only if it is still used after the migration. Otherwise leave it on the key.
- **Done when:** the new workflows publish through Trusted Publishing from the pilot repo using the released action.

### Phase 4: roll out to callers

- Add the `id-token: write` permission to the publishing caller workflows and to the `PepperDash/.github` starter callers so new repos get it by default.
- Create the nuget.org policy for each publishing repo, in batches. Per Q1 this is either one shared policy or one per repo. Track the batch in a checklist.
- Roll out in waves: public plugin repos first, then Essentials and PepperDashCore last.
- **Done when:** every public publishing repo has published successfully without the secret, and the checklist is complete.

### Phase 5: retire the key

- If no 3-Series workflow still publishes: delete the `NUGET_API_KEY` org secret and revoke the key on nuget.org.
- Otherwise: scope the org secret to the remaining 3-Series repos only, and note the remaining dependency here.
- **Done when:** the secret is deleted or minimally scoped, and the runbook says which.

## 6. Risks and rollback

| Risk | Mitigation |
|---|---|
| Q1 goes the wrong way (policy per caller repo) | About 100 policies to create. Do it in batches and script the checklist. The key remains the fallback meanwhile |
| Policy not activated within 7 days | Re-activate from the nuget.org Trusted Publishing page; first publish should happen soon after creating each policy |
| Forgetting `id-token: write` in a caller | `NuGet/login` fails with a 403. Add a pre-flight check in the action that prints a clear message when the OIDC token request URL is missing |
| Fork PRs / non-PepperDash repos | The public-PepperDash guard stays; the login step never runs for them |
| Trusted Publishing not available on the account | Stay on Phase 0 and 1; revisit when it is enabled |
| Rollback | Re-enable the optional `nuget-api-key` input and the org secret. Nothing in phases 2-4 deletes the secret before phase 5 |

## 7. Decisions needed

1. Who owns creating nuget.org policies (Q3)?
2. In Phase 1: remove `continue-on-error`, or keep it and add a failing final step?
3. In Phase 1: should non-`main`/`release` branches publish to nuget.org at all?
4. Does this plan live inside the #49 epic (it changes `publish-nuget-org` and D11), or become its own issue?
