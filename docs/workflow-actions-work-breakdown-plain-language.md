# Who does what: the work breakdown in plain language

> **Superseded 2026-11-05 by [ci-cd-plan.md](ci-cd-plan.md).** Kept for reference; where this disagrees with that page, that page wins.

Status: **draft for assignment** · 2026-10-27 · Plain-language companion to `docs/workflow-actions-work-breakdown.md`. The technical version is the reference. Read `docs/workflow-actions-migration-plan-plain-language.md` first for the background and a glossary of terms.

## How to use this

- Each row is **one job for one person**, usually one pull request (a change someone else reviews) or one settings change.
- Pick a job whose "needs first" jobs are done. Put your name in the **Owner** column of the technical document, and open a tracking issue named with the job's ID, for example `C3`.
- **Sizes:** S is a day or less, M is two to four days, L is one to two weeks.
- Not included: the 3-Series projects, the DocFX website tool, and rewriting the README parser (only if a problem is found).

Quick reminders: a **repo** is a project on GitHub; an **action** is one reusable build step; a **workflow** is a recipe that runs actions; **`v1`** is a label meaning "the current version 1".

---

## 1. The seven streams of work

| Stream | In plain words | Can start |
|---|---|---|
| **A. Tools** | Publish our README and schema tools to nuget.org and prove they work | Now |
| **B. Rules and starter kit** | Write the version rules, build the starter-kit repo and the script that applies repo settings | Now |
| **C. Split the big proposal** | Break pull request #57 into small, reviewable pieces and remove what is out of scope | Now (some jobs wait on B) |
| **D. The 16 step repos** | Create one repo per reusable step | After the starter kit exists and C is partly merged |
| **E. Developer helpers** | VS Code buttons, a save-time hook, clear failure messages | After tools are published |
| **F. Safety fixes** | Clear publish-failure messages, warnings on old files, locking outside steps to exact versions | Now (independent jobs) |
| **G. Trials, move-over, clean-up** | Prove it on real repos, move ~115 repos, delete the old files | After the gates in section 4 |

A and B run in parallel from day one.

---

## 2. The jobs

### A. Tools

| ID | Job | Size | Needs first | Done when |
|---|---|---|---|---|
| A1 | Answer the open questions for the tools repo (who approves, who owns the nuget key, the package name prefix, and the final repo name) | S | none | Answers written down |
| A2 | Finish the tools repo's protection rules and set up the publish key | S | A1 | A direct push to the main code is refused (we test it) |
| A3 | Publish both tools to nuget.org | S | A2 | Both appear on nuget.org and install on a clean computer |
| A4 | Check they install and run on the GitHub build computer, including with a private package feed | S | A3 | Result written down |
| A5 | Try the README tool on one older-style and one newer-style real plugin | M | A3 | Both build green; the README changes it makes are recorded |

### B. Rules and starter kit

| ID | Job | Size | Needs first | Done when |
|---|---|---|---|---|
| B1 | Open the tracking issue and one issue per job; record the naming decision on issue #49 and close it | S | none | Tracking issue lists every job |
| B2 | Write the versioning policy document (labels, locking, rollback, release rules) | S | none | Reviewed and merged |
| B3 | Build the **starter-kit repo** every action repo is copied from: tests, checks, release process, update checker, owners, how-to guide | M | B2 | A trial repo made from it passes checks and releases a test version |
| B4 | Write the **settings script**: one approval, dismiss out-of-date approvals, only the release process moves `v1`, repo public, no bypass on the publish step | M | B3 | Running it twice changes nothing the second time |
| B5 | Label today's code `v0.9.0` as a safe point to return to | S | none | Label exists |

### C. Split the big proposal (pull request #57)

| ID | Job | Size | Needs first | Done when |
|---|---|---|---|---|
| C1 | Remove what is out of scope: the schema feature, all 3-Series material, and their tests | M | none | Automatic checks pass; nothing mentioning them remains, including in the testing guide |
| C2 | Piece A: the version-finding step, locking outside steps to exact versions | S | C1 | Checks pass |
| C3 | Piece B: the first group of actions, with tests, and a cleaner way of running scripts | M | C1 | Tests pass |
| C4 | Piece C: the build recipes that use those actions | M | C3 | The local full-run test passes |
| C5 | The migration guide: old file names to new, plus the prompt for an AI helper that converts callers | S | C4 | Reviewed by someone who did not write the recipes |
| C6 | Delete one unused old file, after checking nothing refers to it | S | none | Merged on its own |

### D. The 16 action repos

**D0 (do first, M):** change the local test runner so it finds each action by version label instead of by folder, so tests keep working once actions move out. Needs B3, B4 and C3.

| Group | Jobs | Needs first |
|---|---|---|
| **1** | D1 publish to nuget.org (medium: it holds the "public only" safety check, and the tests for it must always pass), D2 publish to GitHub, D3 version prefix, D4 upload release, D5 clean up failed release, D6 embed the devtools web app | D0 |
| **2** | D7 dotnet build, D8 copy build output, D9 create package description, D10 pack package, D11 add files to package, D12 check package name | Group 1 merged and C4 merged |
| **3** | D13 find solution info, D14 find project info, D15 find plugin info, D16 update assembly info | Group 2 merged |

People in the same group can work at the same time. Every one of the 16 follows the same checklist (section 3).

### E. Developer helpers

| ID | Job | Size | Needs first | Done when |
|---|---|---|---|---|
| E1 | Add VS Code buttons for: update badges, update tables, check, generate schema | S | A3 | Each works on a fresh copy of the project |
| E2 | Make a failed README check say exactly what is out of date and how to fix it | M | A3 | A new developer can fix a deliberately stale README unaided |
| E3 | Add a hook that refreshes the README when saving a change | S | A3 | A saved change includes the README update |
| E4 | Add the optional cloud step that opens a pull request with README fixes after a push, then delete the old README updater and `metadata.py` | M | E1, E2, G1 | A stale README on main produces a fix pull request; old files gone |
| E5 | Check the automatic update checker covers our tools; if not, set up a reminder | S | A3 | Result written down |
| E6 | Prepare the one-time "adopt the new README tool" pull request template | S | A5 | Template ready for the move-over |

### F. Safety fixes

| ID | Job | Size | Needs first | Done when |
|---|---|---|---|---|
| F1 | Make a failed publish visible: red message and summary line naming the package and the step, while the run stays green | M | C3 | A forced failure shows both |
| F2 | Add a "please migrate" warning to every remaining old workflow, with no change in behaviour, and a matching banner on three old guides | S | C5 | Warning shows on an old run; banner on the guides |
| F3 | Lock the documentation-checker download to an exact version | S | none | No unlocked download remains |
| F4 | Confirm the "public only" check behaves correctly on a real public repo and a real private repo | S | C4 | Opposite results recorded |

### G. Trials, move-over, clean-up

| ID | Job | Size | Needs first | Done when |
|---|---|---|---|---|
| G1 | Trial run 1: the project template | M | C4, E1 to E3, group 2 | A real release gives the expected package and README |
| G2 | Trial runs 2 to 4: a public plugin (must publish), a private plugin (must not), a newer-style plugin; include a deliberate failing build | M | G1, F4 | Public publishes, private does not, failed build leaves nothing behind |
| G3 | Trial runs 5 and 6: Essentials and PepperDashCore | M | G1 | Expected release files |
| G4 | Update the starter templates for new repos so they begin on the new workflows | S | G2, G3 | A new repo starts on the new setup |
| G5 | Write the migration script: list the callers, prepare one pull request per repo | M | G2, G3 | A dry run lists every repo without opening anything |
| G6 | Move repos in batches of 10 to 15, watching each batch first | L | G5, group 3, F2 | Every repo ticked off in the tracking issue |
| G8 | Rewrite the guides (overview, details, getting started, index) for the new workflows and update the testing guide | M | G3 | Guides describe only things that exist; a new reader can set up a repo from them |
| G7 | Delete the old workflows, scripts and docs | S | G6, G8 plus two clean weeks | Nothing refers to them; docs match reality |

---

## 3. The checklist for each of the 16 action repos

1. Create the repo from the starter kit and run the settings script.
2. Move the action's files and tests over; copy in the shared helper file.
3. Write a short README with inputs, outputs and a usage example.
4. Make sure the repo's own automatic checks pass.
5. Release version `v1.0.0` and confirm `v1` points at it.
6. In `workflow-templates`, switch to the new `v1` reference, delete the old copy, in **one** pull request so a revert is a single step.
7. Run the full local test and attach the result.
8. Add the repo to the tracking issue.

---

## 4. Gates (do not pass until the condition is true)

| Gate | Condition | Unlocks |
|---|---|---|
| Tools ready | A3 done: both tools on nuget.org | A4, A5, E1 to E3, E5 |
| Proposal landed | C1 to C4 merged, checks green, two reviewers | Group 2 of the action repos |
| First group proven | Group 1 released and in use via `v1` | Group 2 |
| Trials pass | G1 to G3 give the expected results | G4 to G6 |
| Quiet period | Two weeks with no repos using the old workflows | G7 |

**If something goes wrong:** point the affected action's `v1` back to the last good version.

---

## 5. Suggested split between people

| Person | Jobs | Why |
|---|---|---|
| 1. Tools owner | A1 to A5, E2, E5 | Works in the tools repo |
| 2. Rules and starter-kit owner | B1 to B5, D0, F3 | Owns the starter kit, settings script and version lookup |
| 3. Recipe owner | C1 to C6, F4 | Knows the existing proposal |
| 4. Template owner | E1, E3, E4, E6, G1 | Owns the project template |
| 5 and 6. Action repo builders | Groups 1 to 3 (D1 to D16) | Same checklist, separate repos |
| 7. Reliability owner | F1, F2 | Failure messages and warnings |
| Rotating | G2 to G7 | One person per trial type, then a migration lead |

Rules to avoid clashes: one action per pull request; do not change another action's repo as part of your job; any later change to the starter kit is its own announced pull request.

---

## 6. Still open

- Owner names for every job.
- The scope and expiry of the nuget.org publishing key have not been checked. Job A1 should record them.
- Someone must confirm the organisation allows GitHub to open pull requests automatically, which job E4 needs.
