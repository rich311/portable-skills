# Portable Skills

Claude Code skills for a Trello-driven workflow, with no project-specific settings baked in.

| Skill | What it does |
| --- | --- |
| `repo-state` | Read-only check for uncommitted changes, unpushed commits, extra branches and worktrees |
| `assess-cards` | Reads Trello cards, posts questions only when a card can't be built safely, and moves those cards to Not Ready (or a Needs input list and owner the project names) |
| `triage-cards` | Runs `assess-cards`, then `ship-cards` on the cards that are ready; `unattended` mode for scheduled runs |
| `ship-cards` | Builds cards with sub-agents in worktrees, verifies, pushes (optionally bugs to production, features to staging), updates Trello and cleans up; a card that stops after it's built keeps its worktree, and the next run resumes it instead of rebuilding |
| `add-card` | Turns one request into a Bug, Feature (with Acceptance Criteria) or manual Chore card in Ready To Start, filled in from the templates and always assigned to the card assignee (default: you) |
| `add-multiple-cards` | Pulls bugs and features out of a transcript or notes, adds the clear ones with `add-card`, and asks about the ambiguous or vague ones |
| `my-cards` | Read-only numbered list of your open cards: linked number, title, and one sentence on what's left |

With no cards named, `assess-cards`, `triage-cards` and `ship-cards` work on the Ready To Start cards where you are the only member.

## Install

Copy the folders you want into a project's `.claude/skills/` (or `~/.claude/skills/` for every project):

```
cp -R skills/* /path/to/project/.claude/skills/
```

`triage-cards` needs `assess-cards` and `ship-cards`; `ship-cards` needs `repo-state`; `add-multiple-cards` needs `add-card`.

## Project settings

The skills read project details from the project's CLAUDE.md. Add a section covering:

- Trello board, its Not Ready / Ready To Start / Doing / Done lists, and a fallback reviewer for cards you create
- For `add-card`: the bug and manual labels, optional Bug and Feature template cards, the app's base URL, and optionally a card assignee who gets every new card (defaults to you)
- Optional: a separate Needs input list for cards with open questions (defaults to Not Ready) and a Needs input owner who becomes the only member of those cards
- GitHub `<owner>/<repo>`, trunk branch, and any long-lived branch to keep in sync (e.g. `preview`)
- Install, lint, typecheck, unit test, build and dev server commands, plus the ports agents may use
- Design system doc, if any
- Non-production test accounts and the env var holding their password
- Production and non-production database ids, and how migrations and data scripts do a dry run
- Whether pushing and production changes have standing approval (otherwise `ship-cards` asks first)
- Optional cloud sessions: whether Claude Code on the web may run these skills, the non-production env keys its environment holds, and a marker that identifies production values (see `automation/cloud-setup.sh`)
- Optional staged releases: a staging branch, the bug label, a "Done in staging" list, and the workflow that promotes staging to production

"You" in every skill is whoever the Trello MCP is logged in as, looked up at run time with `get_me` (or `automation/trello-me.mjs` when the Trello MCP has no get_me tool), so the skills work for anyone on the team without editing settings.

`repo-state/check.sh` takes `MAIN_BRANCH`, `KEEP_BRANCHES` (e.g. `"main preview"`) and `EXTRA_IGNORE` as env vars.

## Staged releases (optional)

When the project settings name a staging branch, a bug label and a "Done in staging" list, `ship-cards` ships bug cards to the trunk (production) and syncs staging, and ships every other card to staging only, moving it to the Done in staging list. Feature migrations go to the staging database only. A separate promote step (for example a manually run GitHub Actions workflow) ships all of staging to production at once, applies the batch's migrations, and moves the Done in staging cards to Done. Feature migrations must be safe to apply before their code.

When the project settings name a Dependabot label, `triage-cards` starts every run by logging a bug card (bug and Dependabot labels) for each `origin/dependabot/*` branch that has no card yet, so dependency security updates ship through `ship-cards` like any other bug. The card says to reproduce the version changes with the package manager rather than merging Dependabot's commit; Dependabot then closes its own pull request.

## Cloud sessions (optional)

The skills can run in Claude Code on the web, including as a scheduled cloud routine that replaces the local hourly job. The cloud session holds non-production keys only; anything that needs a production secret goes through GitHub Actions.

Files in `automation/` for this:

| File | Copy to | What it does |
| --- | --- | --- |
| `cloud-setup.sh` | `scripts/cloud-setup.sh` | Writes the env file from an allowlist of the cloud environment's variables (refusing anything that matches the production marker) and installs dependencies. Does nothing on a Mac unless `--cloud` is passed. Settings come from `.claude/cloud-setup.conf` (see the script's header). |
| `settings.json.example` | merge into `.claude/settings.json` | Runs `cloud-setup.sh` from a `SessionStart` hook (the environment's setup-script field doesn't run inside the clone) and allows the Trello tools, denying archive and delete. |
| `mcp.json.example` | `.mcp.json` | Gives cloud sessions the Trello MCP server, reading its keys from the cloud environment's variables. |
| `trello-me.mjs` | `scripts/` or keep in `automation/` | Prints the logged-in Trello member (`id`, `username`, `fullName`) for Trello MCP servers with no get_me tool. Keys from `TRELLO_API_KEY` / `TRELLO_TOKEN`, or the env of the MCP server named `TRELLO_MCP_SERVER` (default `trello`) in `~/.claude.json`; never prints them. |
| `gh-workflow.mjs` | `scripts/gh-workflow.mjs` | Starts a workflow, waits, and prints its `RESULT:` line. Repo from `GH_REPO` or the git remote, token from `GITHUB_PAT`. |
| `workflows/email-report.yml` | `.github/workflows/` | Emails the report with `send-report.py` (cloud networks may block SMTP). Needs `send-report.py` and `report_html.py` in the repo (default `.claude/automation/`). |
| `workflows/apply-prod-migrations.yml` | `.github/workflows/` | Production migrations: exact-match dry run, re-check, apply, confirm nothing pending. Written for the Supabase CLI. |

### Setting it up

1. **Copy the files** above into the project and commit them. Fill in `.claude/cloud-setup.conf`, the Trello board id in `.mcp.json`, and `AUTOMATION_DIR` / `MIGRATIONS_DIR` in the workflows if yours differ.
2. **GitHub**: add the repo secrets `SMTP_PASSWORD` and `PROD_DB_URL`, and the repo variables `REPORT_TO`, `SMTP_HOST`, `SMTP_USER`, `SMTP_FROM` (plus `SMTP_PORT`, `PREVIEW_URL`, `SHIP_URL` if wanted). Create a fine-grained token for this repo with Actions read/write and Checks read (without Checks the script can't read the result annotation and falls back to the run's conclusion).
3. **Cloud environment** (claude.ai > Code > Environments): add the non-production keys `cloud-setup.sh` copies, `TRELLO_API_KEY`, `TRELLO_TOKEN` and `GITHUB_PAT`. Never production keys.
4. **Network access** on the same environment: allow the non-production database and API hosts and the staging site. Leave production hosts blocked, so a mistake can't reach them. Check with a one-off routine that `curl`s each host (expect an auth error such as 401 from an API, not a 403 from the proxy).
5. **CLAUDE.md**: say cloud sessions are allowed, which keys they hold, where unattended runs may push, and the user's time zone.
6. **Routine** (claude.ai > Code > Routines, or `/schedule`): prompt `/triage-cards unattended cloud`, this repo, the environment above, no extra connectors. Cron is UTC and covers the allowed hours in your zone, for example `55 0-5,13-23 * * *` for 6:55am to 9:55pm Mountain. Start it once by hand and read the transcript before trusting the schedule.
7. **Turn the local job off** (`launchctl unload` the plist or remove the cron line). Never run both.

### Lessons from setting it up

- **Gate before setup.** Most hours have no cards. The skill checks the hour and asks Trello for cards before installing anything, so an empty run takes about 20 seconds and 4 turns instead of over a minute.
- **Scheduled times drift.** Runs start a few minutes after the cron time and that delay can't be set, so choose minute 55 rather than 0 if you want a run before the hour.
- **Check the hour in the user's zone**, not UTC, and put it in the email subject.
- **SessionStart hooks may not run in routine sessions**, so the skill runs the setup script itself when the env file is missing.
- **Cloud networks block more than you expect**: SMTP, hosting APIs and GitHub's job log downloads. Workflows report through `::notice title=RESULT::` annotations and only succeed when the result is good, so the caller can act on the conclusion alone.
- **Cloud-only test failures** happen when a test depends on a local env value (a site URL, say). Set it in the cloud environment or the test, not by skipping the test.
- **Dev servers may write files** (Next.js writes `AGENTS.md`). Add them to `.gitignore` so they don't end up in commits.

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
