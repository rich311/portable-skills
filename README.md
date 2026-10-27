# Portable Skills

Claude Code skills for a Trello-driven workflow, with no project-specific settings baked in.

| Skill | What it does |
| --- | --- |
| `repo-state` | Read-only check for uncommitted changes, unpushed commits, extra branches and worktrees |
| `assess-cards` | Reads Trello cards and posts questions only when a card can't be built safely |
| `triage-cards` | Runs `assess-cards`, then `ship-cards` on the cards that are ready |
| `ship-cards` | Builds cards with sub-agents in worktrees, verifies, pushes, updates Trello and cleans up |

## Install

Copy the folders you want into a project's `.claude/skills/` (or `~/.claude/skills/` for every project):

```
cp -R skills/* /path/to/project/.claude/skills/
```

`triage-cards` needs `assess-cards` and `ship-cards`; `ship-cards` needs `repo-state`.

## Project settings

The skills read project details from the project's CLAUDE.md. Add a section covering:

- Trello board, its Ready To Start / Doing / Done lists, and a fallback reviewer for cards you create
- GitHub `<owner>/<repo>`, trunk branch, and any long-lived branch to keep in sync (e.g. `preview`)
- Install, lint, typecheck, unit test, build and dev server commands, plus the ports agents may use
- Design system doc, if any
- Non-production test accounts and the env var holding their password
- Production and non-production database ids, and how migrations and data scripts do a dry run
- Whether pushing and production changes have standing approval (otherwise `ship-cards` asks first)

`repo-state/check.sh` takes `MAIN_BRANCH`, `KEEP_BRANCHES` (e.g. `"main preview"`) and `EXTRA_IGNORE` as env vars.
