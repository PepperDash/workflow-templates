# Reorganising our build automation: the plan in plain language

> **Superseded 2026-11-05 by [ci-cd-plan.md](ci-cd-plan.md).** Kept for reference; where this disagrees with that page, that page wins.

Status: **draft for review** · 2026-10-27 · This is a plain-language companion to `docs/workflow-actions-migration-plan.md`. The technical version is the reference; if the two ever disagree, the technical one wins.

Who this is for: anyone who needs to understand or approve the plan without knowing how build automation (CI/CD) works.

---

## 1. Short glossary

| Term | What it means here |
|---|---|
| **Repository (repo)** | A project folder stored on GitHub, with its full change history. |
| **Build** | Turning source code into the file that gets installed on a device or shared as a package. |
| **Workflow** | A written recipe that GitHub runs automatically, for example "when someone saves code, build it, test it and publish it". We have a shared set in the `workflow-templates` repo. |
| **Action** | One reusable step inside a recipe, such as "package the files" or "publish to nuget.org". Many workflows reuse the same actions. |
| **Caller** | A small file in each plugin repo that says "run the shared recipe from `workflow-templates`". About 115 repos have one. |
| **NuGet / nuget.org** | The public shop where finished software packages are published so other people can download them. |
| **Tag and version** | A label on a specific saved point in the code, like `v1.2.0`. `v1` is a label that always points to the newest `v1.x.x`. |
| **Pull request (PR)** | A proposed change that someone else reviews and approves before it is merged into the main code. |
| **Approval** | A reviewer's sign-off on a pull request. |
| **Pinning** | Saying exactly which version of something to use, so it does not change under you. |
| **Secret** | A password or key stored safely by GitHub, for example the key that lets us publish to nuget.org. |
| **README** | The front page of a repo. Ours includes badges (small status pictures) and tables describing the device. |
| **essentials-build-tools** | Our own set of small programs that can write the README badges and tables automatically from the code. |
| **Canary** | A trial run on one real repo before rolling a change out to everyone. |

---

## 2. What we are doing and why

Today the shared build recipes are long. Each one repeats the same steps, so a fix has to be made in many places. About 115 repos depend on them, and most of those repos always take the **newest** version of the recipe. That means one bad change to the main recipe breaks every one of those repos at once.

The plan:

1. Break the recipes into small reusable steps (actions), each in **its own repo**, with its own version labels, so one step can be changed or rolled back without touching anything else.
2. Give every repo a **version label** to depend on (`v1`) instead of "whatever is newest", so changes reach people deliberately.
3. Replace the old README updater with our own tools so READMEs are correct when a developer saves their work.
4. Move the 115 repos over in small, watched batches, trying each kind of repo first.

Nothing in the old setup is removed until the new one has been proven. Repos keep working throughout.

**Out of scope:** the older 3-Series / Essentials v1 projects. They stay exactly as they are, and DocFX (a documentation website tool) is postponed to a later plan.

---

## 3. Problems found, and what we do about them

| Problem | Why it matters | What we do |
|---|---|---|
| Everyone uses "newest" | One broken change hits every repo | Version labels (`v1`) for everything, with a rule that `v1` only moves through the official release process |
| An unwanted feature in the proposal (automatic schema generation) | It fails quietly and goes against an earlier decision | Remove it. Schemas come from our own tool, set up in the project template |
| Our publishing tools are not yet on nuget.org | Anything that tries to use them would fail | First task: publish them |
| A failed publish looks like a success | Someone sees a green tick but no package exists | The run stays green, but a clear red message and a summary line say which package failed and where |
| Some outside steps are not locked to a version | They could change without us knowing | Lock them to an exact version |
| The current README updater is fragile | It can overwrite other people's work and is blocked by protected branches | Replace it (section 6) |
| Old workflows give no warning | Nobody knows to move | Add a visible "please migrate" warning, with no change in behaviour |
| New repos start from the old templates | Fresh repos begin out of date | Update the starter templates |
| A "publishing only for public repos" check is only tested in isolation | Private code must never reach the public nuget.org | A real test with one public and one private repo, which must give opposite results |

---

## 4. Versions and releases (the safety rules)

- Every action repo and `workflow-templates` use version labels such as `v1.2.3`, plus a moving `v1`.
- Only the official release process may move `v1`. People cannot move it by hand.
- Repos refer to our own steps by `v1`. Steps from other companies are locked to an exact version.
- A breaking change gets a new major label (`v2`) next to `v1`; repos move over in batches and `v1` retires last.
- **Rollback:** if a release is bad, point `v1` back to the last good version, fixing the smallest step first.
- **Safety rule:** the build must succeed **before** any label, release or package is created. A failed build leaves nothing behind.

---

## 5. One repo per step

You decided each reusable step gets its own repo. There will be **16**, named `action-` followed by what they do, for example `action-publish-nuget-org`.

**Public, not internal.** You asked whether they could be kept internal. They cannot, because public plugin repos (the ones that publish to nuget.org) cannot use steps stored in an internal repo, and `workflow-templates` is itself public. Instead we keep passwords out of the step code, restrict who can change them, and lock down releases.

**Order of work:** we create the repos in three groups, not all at once.

| Group | Steps | Why this order |
|---|---|---|
| First | publish to nuget.org, publish to GitHub, apply the Essentials version prefix, upload release, clean up failed release, embed the devtools web app | Small, independent, and prove the process |
| Second | dotnet build, copy build output, create package description, pack package, add files to package, check package name | Wait until the build recipes settle |
| Third | four small "discover project info" steps | Tiny, done last |

**Every action repo gets the same starter kit** (a template repo): tests, automatic checks, a release process, an update checker, owners, and a short how-to-release-and-roll-back guide.

**Approval rules (decided):**

- One approval on every pull request, including the publishing step.
- Out-of-date approvals are dismissed: if code changes after approval, it needs approving again.
- No one can bypass the rules on the publishing step. Elsewhere, admins can, but the audit log is reviewed.
- Only the release process moves `v1`.
- No extra "environment approval" gate for publishing. Adding one would change how every repo calls the workflow.
- The nuget.org key stays a secret held at the organisation level, unchanged.
- Because there is just one approval and no extra gate, the tests for the "public only" check must always pass before a change to the publishing step can merge.

---

## 6. README updates: how it will work

Goal: when a developer changes code, the README badges and tables are already correct, without anyone remembering a step.

1. **On the developer's machine:** buttons in VS Code (tasks) run our essentials-build-tools to refresh badges and tables. Badges refresh on every local build.
2. **When saving a change (commit):** an automatic hook refreshes the README and adds it to the same commit.
3. **After pushing (bonus, optional per repo):** a cloud job refreshes the README and opens a pull request with the fix.
4. **The strictness setting (decided):** if a README is out of date, the build **always fails**. We accept that someone editing in the GitHub website, with no tool installed, will see a red check. To soften it, the failure message will name the exact fix.

The old README updater and its script `metadata.py` are deleted once the new way has been proven on a real repo. The first run on each existing repo will change its README a little, so each repo gets a one-time "adopt the new README tool" pull request.

---

## 7. The phases

| Phase | What happens | Rough size |
|---|---|---|
| 0. Unblock tools | Publish essentials-build-tools to nuget.org and test it on one old-style and one new-style plugin | Small to medium |
| 1. Rules and tracking | Open a tracking issue, write the version policy, create the starter-kit repo, label today's code as `v0.9.0` so we can return to it | Small |
| 2. Land the existing proposal in pieces | Split the big pull request (#57) into smaller reviewable ones, remove what is out of scope, add the migration guide | Medium |
| 3. Create the 16 action repos | In the three groups above, one at a time | Medium per group |
| 4. Trial runs | Move one real repo of each kind and run a genuine release, including deliberate failures to prove nothing bad is left behind | Medium |
| 5. Move everyone | Batches of 10 to 15 repos, watching each batch before the next; update the starter templates for new repos | Large |
| 6. Retire the old files | Delete the old workflows and scripts after two clean weeks | Small |

**Trial repos:** the project template, a public plugin (must publish), a private plugin (must **not** publish), a newer-style plugin, and the Essentials and PepperDashCore repos.

---

## 8. Risks

| Risk | Chance | Impact | What reduces it |
|---|---|---|---|
| A bad release breaks many repos | Medium | High | Trial runs first, controlled `v1`, rollback guide, batches |
| A repo's private package feed stops our tools installing | Low to medium | Medium | Test one such repo, add a fallback |
| 16 repos is a lot to look after | High | Medium | Starter kit, one shared guide, automatic update checks, a script that applies the settings |
| First README tool run changes every README | High | Low | Planned one-time pull request with a note |
| Private code reaches nuget.org by mistake | Low | High | Public and private trial pair; the check refuses by default |

---

## 9. Decisions made (all answered)

| # | Question | Answer |
|---|---|---|
| D1 | What do shared recipe files get called? | `{entry point}-{series}-{framework}-{action}.yml`, 4-Series only. Callers are renamed only during migration. |
| D2 | One repo per step? | Yes, 16 repos, created in groups. |
| D3 | Repo names and visibility? | `action-{description}`, public. |
| D4 | How do repos pick a version? | `v1` for our own steps, exact version for outside ones; old "newest" setup works until migrated. |
| D5 | Remove the schema feature from the proposal? | Yes. |
| D6 | What if the README is out of date? | The build always fails, with a helpful message. |
| D7 | What replaces the old README updater? | essentials-build-tools through VS Code tasks, with an optional cloud step after pushing. `metadata.py` is deleted. |
| D8 | DocFX? | Postponed to a later plan. |
| D9 | Rewrite the README tool's parser? | Only if we find it misreading a real plugin. |
| D10 | Publishing failures? | Run stays green, with a clear error message and summary line. |
| D11 | Approval rules? | One approval everywhere, stale approvals dismissed, no bypass on the publish step, only the release process moves `v1`, no extra environment gate, nuget key stays an organisation secret. |
| D12 | Who does the work? | A separate breakdown of small work items for several people exists. Owners still to be named. |
