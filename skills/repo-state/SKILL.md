---
name: repo-state
description: Check this repo for leftover work, read-only. Reports uncommitted changes (main checkout and every worktree), unpushed commits, local branches besides the long-lived ones, and worktrees besides the main checkout, with a ✅ or ⚠️ line for each. Use when the user asks for the "repo state", whether everything is pushed or cleaned up, or what's left in the repo; ship-cards calls it as its final check.
---

# Repo state

A read-only check. It never commits, pushes, stashes, deletes or cleans
anything. Never use em dashes in the report.

## 1. Run the check

From the main checkout or any worktree:

```
bash "$(git rev-parse --path-format=absolute --git-common-dir | sed 's#/\.git$##')/.claude/skills/repo-state/check.sh"
```

If the project has long-lived branches besides `main` (e.g. `preview` or
`staging`, see CLAUDE.md), pass them so they aren't flagged:
`KEEP_BRANCHES="main preview" bash .../check.sh`. A different trunk name goes
in `MAIN_BRANCH`, extra build-artifact paths to ignore in `EXTRA_IGNORE`.

It fetches origin and prints one line per check (exit 0 when everything is
clean):
1. Uncommitted changes in the main checkout and every worktree (ignoring
   `node_modules`, `.env.local` and the verification artifacts ship-cards
   leaves: `.next-verify`, `.next-agent`, `.verify-tmp.mjs`, `.qa-tmp-*.mjs`).
2. Unpushed commits: any local branch with commits not on `origin/main`
   (long-lived branches compare against their own origin branch), and
   detached worktree HEADs.
3. Local branches besides the long-lived ones.
4. Worktrees besides the main checkout.
5. The main checkout is on `main` and not behind `origin/main`.

## 2. Look before reporting

For each ⚠️ item, work out whose it is before saying anything about it:
- A worktree or branch the current session created is this session's. When
  the caller (e.g. ship-cards) says to clean up, it does that itself, then
  re-runs the check.
- A worktree marked "(kept for resume by ship-cards)" was left on purpose
  by a stopped ship-cards run (its `.ship-cards-resume` file says which card
  and why). Report it as `⚠️ Kept for resume: #<n> on <branch>` and never
  remove it; the next ship-cards run on that card picks it up.
- Anything else may be another Claude session's work in progress (several
  can run in one repo at once). Never remove, reset, push or check it out.
  Use `git -C <worktree> log --oneline origin/main..HEAD -3` and the branch
  name (e.g. `card-123-...`) to say what it is in a few words.

## 3. Report

One line per item, no headings or tables.
- All clean: the single line `✅ Repo state`.
- Otherwise one `⚠️` line per problem, with what it is and whose it seems to
  be, e.g. `⚠️ Worktree card-123-login-fix (another session, 2 unpushed
  commits for #123)`. Then the ✅ lines for the checks that passed can be
  folded into one: `✅ Everything else clean`.
- Don't offer to delete other sessions' work; just list it so the user can
  decide.
