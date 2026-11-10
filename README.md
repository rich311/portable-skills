# Portable Skills

Claude Code skills for a Trello-driven workflow, with no project-specific settings baked in.

| Skill | What it does |
| --- | --- |
| `repo-state` | Read-only check for uncommitted changes, unpushed commits, extra branches and worktrees |
| `assess-cards` | Reads Trello cards, posts questions only when a card can't be built safely, and moves those cards to Not Ready (or a Needs input list and owner the project names) |
| `triage-cards` | Runs `assess-cards`, then `ship-cards` on the cards that are ready; `unattended` mode for scheduled runs |
| `ship-cards` | Builds cards with sub-agents in worktrees, verifies, pushes (optionally bugs to production, features to staging), updates Trello and cleans up; a card that stops after it's built keeps its worktree, and the next run resumes it instead of rebuilding |

With no cards named, `assess-cards`, `triage-cards` and `ship-cards` work on the Ready To Start cards where you are the only member.

## Install

Copy the folders you want into a project's `.claude/skills/` (or `~/.claude/skills/` for every project):

```
cp -R skills/* /path/to/project/.claude/skills/
```

`triage-cards` needs `assess-cards` and `ship-cards`; `ship-cards` needs `repo-state`.

## Project settings

The skills read project details from the project's CLAUDE.md. Add a section covering:

- Trello board, its Not Ready / Ready To Start / Doing / Done lists, and a fallback reviewer for cards you create
- Optional: a separate Needs input list for cards with open questions (defaults to Not Ready) and a Needs input owner who becomes the only member of those cards
- GitHub `<owner>/<repo>`, trunk branch, and any long-lived branch to keep in sync (e.g. `preview`)
- Install, lint, typecheck, unit test, build and dev server commands, plus the ports agents may use
- Design system doc, if any
- Non-production test accounts and the env var holding their password
- Production and non-production database ids, and how migrations and data scripts do a dry run
- Whether pushing and production changes have standing approval (otherwise `ship-cards` asks first)
- Optional cloud sessions: whether Claude Code on the web may run these skills, the non-production env keys its environment holds, and a marker that identifies production values (see `automation/cloud-setup.sh`)
- Optional staged releases: a staging branch, the bug label, a "Done in staging" list, and the workflow that promotes staging to production

`repo-state/check.sh` takes `MAIN_BRANCH`, `KEEP_BRANCHES` (e.g. `"main preview"`) and `EXTRA_IGNORE` as env vars.

## Staged releases (optional)

When the project settings name a staging branch, a bug label and a "Done in staging" list, `ship-cards` ships bug cards to the trunk (production) and syncs staging, and ships every other card to staging only, moving it to the Done in staging list. Feature migrations go to the staging database only. A separate promote step (for example a manually run GitHub Actions workflow) ships all of staging to production at once, applies the batch's migrations, and moves the Done in staging cards to Done. Feature migrations must be safe to apply before their code.

When the project settings name a Dependabot label, `triage-cards` starts every run by logging a bug card (bug and Dependabot labels) for each `origin/dependabot/*` branch that has no card yet, so dependency security updates ship through `ship-cards` like any other bug. The card says to reproduce the version changes with the package manager rather than merging Dependabot's commit; Dependabot then closes its own pull request.

## Cloud sessions (optional)

`automation/cloud-setup.sh` prepares a Claude Code on the web session: it writes the local env file from an allowlist of the cloud environment's variables (non-production only, refusing any value that matches the production marker) and installs dependencies. Set the cloud environment's setup script to `bash automation/cloud-setup.sh --cloud` (or copy it into the project's `scripts/`). Settings come from `.claude/cloud-setup.conf` in the project. `ship-cards` then runs in cloud mode, which never changes production.

## Scheduled triage (optional)

`automation/` runs `/triage-cards unattended` on a schedule and emails the report:

- `triage-hourly.sh`: skips outside the allowed hours or while a previous run is going, asks a cheap Haiku session whether any of your cards are waiting, runs triage only if so, then emails the report (only the text after its final `SUBJECT:` line, which becomes the subject).
- `send-report.py`: sends the email over SMTP (no dependencies beyond Python 3).
- `report_html.py`: turns the plain-text report into a styled HTML email (a header with the counts, a panel per section, a linked row per card). The plain text goes along as the fallback part. Change the colors at the top to match your brand.
- `triage.env.example`: the settings; copy to `~/.config/triage-cards/<name>.env`. It holds a password, so keep it out of the repo.
- `triage-hourly.plist`: a macOS launchd job that starts the script on the hour (cron works too: `0 * * * * /path/to/triage-hourly.sh /path/to/name.env`).

Unattended runs push without anyone watching, so only turn this on with standing approval in the project's CLAUDE.md, saying where cards may be pushed. The report looks like:

```
SUBJECT: Triage: 1 bug, 1 feature shipped, 1 not ready (#12, #14, #15)

✅ Nothing to do

Shipped to Prod (1)
✅ #12 Login button (https://trello.com/c/...): fixed the double submit

Shipped to Preview (1)
✅ #14 Saved searches (https://trello.com/c/...): save and rerun a job search

Cards Not Ready (1)
✅ #15 Pricing page (https://trello.com/c/...): 2 questions to answer

✅ Repo state clean
```
