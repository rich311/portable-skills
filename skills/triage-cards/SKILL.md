---
name: triage-cards
description: Take a list of Trello cards (or a whole list like "Ready To Start"; with none given, the Ready To Start cards where the user is the only member), decide which are ready to build, run `assess-cards` so the not-ready ones get questions posted and move to Not Ready, then run `ship-cards` on the ready ones (straight away when no card has questions, otherwise after the user confirms). Has an `unattended` mode for scheduled runs that never asks and ends with a short emailable report. Use when the user asks to "check which cards are ready and work them", "triage", "ship what's ready and assess the rest", or gives a mixed set of cards without saying whether they're ready.
---

# Triage cards: ship what's ready, assess the rest

This skill is a router. It does one readiness pass, then hands each card to
the right skill. It never builds on its own. It needs the `assess-cards`
and `ship-cards` skills installed alongside it.

When no card ends up with questions, invoking this skill is the user's go
ahead to ship every Ready card (step 2). Otherwise `ship-cards` needs the
user's explicit go ahead, given after step 2 below (except in unattended
mode).

Never use em dashes anywhere (Trello text or the chat summary).

**Cloud sessions.** In a Claude Code on the web session, follow "Cloud mode"
in `ship-cards`: non-production keys only, nothing touches production, and
cards that need a production change go back to Ready To Start for a local
run.

## Cloud unattended mode

When the arguments include `unattended cloud`, a scheduled cloud routine
started it (cloud schedules run in UTC). It does everything in Unattended
mode below, with these steps around it. Most runs find no cards, so steps 1
and 2 come first and stay cheap: one Bash call and one Trello call, no other
reading (not this skill's later sections, not `ship-cards`, no repo files)
and no environment setup until a card is in scope.
1. **Hours.** In one Bash call, the hour in the user's time zone from the
   project settings (`TZ=<zone> date +%H`), plus, when the project logs
   Dependabot cards (step 0), `git fetch -q --prune origin` and a listing
   of `refs/remotes/origin/dependabot/`. Outside the allowed hours (default
   6 to before 22): end at once with the single line `Outside hours`. No
   email.
2. **Gate.** One Trello call listing Ready To Start. Count the open cards
   in the default scope of step 1 (the user is the only member, leaving out
   manual and chore cards). Zero cards and no Dependabot branches: end with
   the single line `No cards`. No email. The Trello server should read its
   keys from the cloud environment's variables so this needs no setup. A
   failed Trello call: retry twice, then carry on so the report shows the
   problem.
3. **Setup.** Only now prepare the environment as "Cloud mode" in
   `ship-cards` says (for example `automation/cloud-setup.sh`). If it can't
   be fixed, the report is that one failure line (step 5 still emails it).
4. **Triage** as Unattended mode says, ending with the report.
5. **Email** the report the way the project's report sender does (in the
   cloud, usually `node scripts/gh-workflow.mjs email-report.yml
   subject="<subject>" body=@<file>`, since cloud networks may block SMTP),
   with the day and hour in the user's time zone in the subject. Send
   nothing when the report only says there was nothing to do.

## Unattended mode

When the arguments include `unattended`, nobody is watching: a scheduled job
(for example `automation/triage-hourly.sh` from the same repo as this skill)
started it with `claude -p`, and its final message is emailed to the user.
Only use this mode if the project's CLAUDE.md (or the user) has approved
unattended runs, including where cards may be pushed (for example bugs to
production and features to staging, see "Staged releases" in `ship-cards`);
quote that approval before pushing. In this mode:
- Never call `AskUserQuestion`. In step 2, ship every Ready card even when
  other cards have questions; those get their question comments as usual.
- Skip the push notification in step 3 (the email replaces it).
- Anything that would normally wait for the user (a permission block,
  another session's commits on the trunk, a failed check that can't be
  fixed) stops only the affected card or step. Record it as a failure and
  carry on with the rest. A merge conflict on a synced branch is not a
  failure: resolve it, verify and push as ship-cards step 6.3 says, and
  report the conflicted files as a warning (a failure only in the hand-off
  cases listed there).
- Don't narrate progress ("the agent is running", "waiting on the review").
  Only the final message matters, and it must be exactly the report below,
  starting with the `SUBJECT:` line. The scheduled job emails everything
  after the last `SUBJECT:` line and uses that line as the email subject.
  Plain text, no tables, no other text before or after.

  ```
  SUBJECT: Triage: <counts> (<cards>)

  ✅ Nothing to do

  Shipped to Prod (<n>)
  ✅ #<n> <title> (<card url>): <one line on what changed>

  Shipped to Preview (<n>)
  ✅ #<n> <title> (<card url>): <one line on what changed>

  Cards Not Ready (<n>)
  ✅ #<n> <title> (<card url>): <q> questions to answer

  Customer replies (<n>)
  To: <reporter email>
  Subject: <short subject>
  <draft email body>

  ✅ Repo state clean
  ```

  Rules:
  - Subject: `<counts>` is short, e.g. `1 feature shipped`, `8 bugs, 2
    features shipped, 1 not ready`, `1 failure`. `<cards>` is every card the
    report lists, by number, most important first (failures, then shipped,
    then not ready): up to three, then `+N` for the rest, e.g.
    `(#12, #14, #15 +8)`. The hourly job adds the day and hour after
    "Triage" (e.g. `Triage Sat 4pm:`) so Gmail never threads two reports
    together; don't add a date yourself.
  - First line after the subject: `✅ Nothing to do` when nothing needs the
    user. (The hourly runner sends no email for a report that is only
    `✅ Nothing to do` and `✅ Repo state clean`.) Otherwise one `❌` line per failure: what failed, the card link if
    there is one, and what the user needs to do to fix it.
  - Customer replies: one draft email per person for every shipped card a
    user (not the team) reported, for example a card made by an in-app bug
    reporter that records the reporter's email. Group all of one person's
    shipped cards into one email; `<n>` counts emails, not cards. Write each
    draft as the board owner, in plain words a user understands (no file
    names, settings, migrations or internal numbers): thank them for
    reporting it, then one or two sentences per card on what was wrong and what changed.
    Keep the whole email short (about 100 words for two cards): no preamble,
    no restating their report, a one-line thanks and sign-off. Only
    call something live if it is in production; say a preview-only change
    is coming soon. If part of a fix only shows up over time or isn't
    confirmed yet, say so honestly. Greet them by first name when known,
    otherwise `Hi there,`. Separate drafts with a blank line and `---`.
    Cards Not Ready get no draft. Leave the section out when there are none.
  - Shipped to Prod holds cards pushed to production, Shipped to Preview
    cards pushed to the staging branch only (use the project's name for it),
    Cards Not Ready the Needs input, Still waiting and Blocked cards (for
    Blocked, say which card it waits on instead of a question count). Leave
    out any section with nothing in it, heading included.
  - Each card line is `✅` unless there's a HIGH priority warning the user
    must know about; then it's `⚠️` with the problem and how to fix it, in a
    few words. Minor judgment calls, assumptions, test-data numbers and
    routine notes (checks passed, who the member is, other sessions' pushes
    that were handled) are left out entirely.
  - A card that stopped with its work kept for resume (see "Kept for
    resume" in `ship-cards`) says so at the end of its `❌` line, with the
    branch, so the user knows moving it back to Ready To Start lets the next
    run finish it.
  - Last line: `✅ Repo state clean`, or `⚠️ Repo state needs cleaning:
    <what>`. Worktrees kept for resume don't count as needing cleaning; list
    them as `⚠️ Kept for resume: #<n> on <branch>`.

## 0. Log a card for each new Dependabot update

Only when the project settings name a Dependabot label. Every Dependabot
pull request becomes a normal bug card, so it shows on the board and ships
through `ship-cards` like any other bug. Do this before step 1 in every run
(unattended included), whatever cards the user named.

1. `git fetch -q --prune origin`, then
   `git for-each-ref --format='%(refname:short)' refs/remotes/origin/dependabot/`.
   Each branch is one open Dependabot pull request. None: skip this step.
2. For each branch, read its commit message (`git log -1 --format=%B
   <branch>`). The subject is the card title. The `updated-dependencies:`
   trailer lists each `dependency-name`, `dependency-version` and
   `dependency-type`; the old versions are in the "from X to Y" lines.
3. **Skip a branch that already has a card:** any card on the board's open
   lists (done lists included) with the Dependabot label whose description
   contains the branch name. A done card whose branch still exists just
   means Dependabot hasn't closed the pull request yet.
4. Otherwise create the card in Ready To Start with the bug and Dependabot
   labels, the user as its only member, the name
   `Bug: Dependabot: <commit subject>`, and the project's bug template
   filled in: reproduction steps naming the branch, a link to its pull
   request (`https://github.com/<owner>/<repo>/pulls?q=is%3Apr+head%3A<branch>`)
   and one line per package (old to new version, dependency type); expected
   "we run the fixed versions"; actual "we run versions with a known
   vulnerability"; and a **How to apply** section: on a branch from the
   default branch, make the same version changes with the package manager
   (install the new version of a direct dependency keeping the manifest's
   range style, update an indirect one) and check the lockfile resolves
   exactly those versions. Never check out or cherry-pick the Dependabot
   branch's files or commit: the commit must be ours, and the lockfile may
   have moved on. Fix any code a breaking change needs. Once it lands,
   Dependabot closes its pull request and deletes the branch by itself.
5. Add the new cards to this run's card list so they are assessed and
   shipped in this same run. A version-only update needs no new regression
   test (lint, type checks, unit tests, the build and the dev server check
   are the test); a framework or runtime package (the web framework, UI
   library, auth client, compiler) gets a dev server check of login and one
   page per role at both sizes.

## 1. Assess every card once

**Default scope.** If the user names no cards or list, triage the cards in
Ready To Start where the user is the only member (the card's `idMembers` is
exactly the user's id; a card that also has anyone else is skipped). The user is whoever get_me returns at run time (see
`ship-cards` project settings), not a stored id.
Anything the user writes (card names, numbers, URLs, a list or a filter)
overrides this default. Pass the resolved card list to `assess-cards` and
`ship-cards` explicitly.

**Interrupted builds.** Also run `git worktree list` and look for an
interrupted build as `ship-cards` step 1.6 defines it (an `agent-*`
worktree with `Card #<n>` commits, no process in it, nothing changed in it for 90 minutes, its cards in the
in-progress list with only the default member). Its cards are already
assessed: add them to the list for `ship-cards` as Ready, even when the
ready list is empty, so the run resumes them instead of stranding them.

**Manual cards.** Always skip a card with a label named "Manual" (or the
manual label the project settings name) or a name starting with "Chore",
even when the user names it or gives its list: it's a task for a person
to do by hand, not code. Don't comment on it, move it or change its
members; leave it out of the report.

**Sync cards.** A card whose name starts with "Sync:" (a branch sync an
earlier run couldn't finish) is always Ready: don't send it to
`assess-cards`, pass it straight to `ship-cards` (step 1, "Sync cards").

Run the `assess-cards` skill (via the Skill tool) on the full list. It reads
each card, its comments and mocks, grounds it in the current app and returns
a verdict per card:

- **Ready**: no comment is posted. Keep its list of assumptions.
- **Needs input**: it posts one question comment for the creator and moves
  the card to the Needs input list (and to the Needs input owner, if set).

Two adjustments while it runs:
- **Skip its push notification.** This skill sends a single one at the end.
- **Don't re-ask.** If a card already has an earlier question comment from
  me that nobody has answered yet (no later comment from the creator), don't
  post another. Mark the card **Still waiting** and, if it's still in Ready
  To Start, handle it like a Needs input card in `assess-cards` step 4
  (Needs input list, and the Needs input owner if set). If the creator has
  replied since, treat the reply as settling those questions and assess
  again with the answers.

Respect dependencies: if a Ready card depends on a card that is Needs input
or Still waiting (for example it needs a feature the other card builds),
mark it **Blocked by #N** rather than Ready, move it to Not Ready and post a
one-line comment: "Waiting on [#N](<card url>) before I can start this."
(only if the card doesn't already have that comment). Leave a Blocked
card's members as they are.

Needs input and Still waiting cards end up in the Needs input list, and
Blocked cards in Not Ready, so they leave the Ready To Start queue and a
scheduled run doesn't pick them up again every time. Whoever answers or
unblocks a card moves it back to Ready To Start. If the board has no such
list, leave them where they are.

## 2. Confirm, then ship the Ready cards

If no card is Ready, skip to step 3 and say so.

**No questions anywhere: ship without asking.** If every card is Ready (no
card is Needs input, Still waiting or Blocked), don't ask. Show the Ready
cards (one line each, with the main assumptions) and go straight to
`ship-cards` on all of them. The user's `/triage-cards` request is the
invoking request `ship-cards` quotes before pushing.

**Any card has questions: ask first** (unless unattended). Otherwise, show
the user the Ready cards (one line each, with the main assumptions) and ask
them to confirm shipping them. Use `AskUserQuestion` with options like "Ship
all of them" / "Ship some" / "Don't ship". Wait for the answer; don't assume
it. The user's confirmation is their invoking request for `ship-cards`, and
that's the message it quotes before pushing.

Either way, run the `ship-cards` skill on exactly the cards being shipped,
in one run, passing along each card's assumptions from step 1 so it doesn't
redo the analysis.
`ship-cards` still does its own quick triage; if it downgrades a card to
Needs input, accept that and report it.

## 3. Report back

In unattended mode, the report is the fixed format above. Otherwise keep it
to one summary covering every card:
- **Shipped**: what `ship-cards` reported (commits, what the user still
  needs to do).
- **Needs input**: the card link, the questions in one line each and who
  was @mentioned.
- **Still waiting** / **Blocked by #N** / **Not shipped**: one line each.
  Say that Needs input, Still waiting and Blocked cards were moved to Not
  Ready.
- A suggested order for the remaining cards once answers come in.

Then send exactly one `PushNotification` (load it with ToolSearch first),
e.g. "Triaged 4 cards: shipped #12, questions posted on #14 #19, #21
still waiting".
