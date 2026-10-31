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
- Anything that would normally wait for the user (a permission block, a
  merge conflict on a synced branch, another session's commits on the trunk,
  a failed check that can't be fixed) stops only the affected card or step.
  Record it as a failure and carry on with the rest.
- Don't narrate progress ("the agent is running", "waiting on the review").
  Only the final message matters, and it must be exactly the report below,
  starting with the `SUBJECT:` line. The scheduled job emails everything
  after the last `SUBJECT:` line and uses that line as the email subject.
  Plain text, no tables, no other text before or after.

  ```
  SUBJECT: Triage cards: <counts, e.g. 1 feature shipped / 3 bugs shipped, 1 feature shipped, 2 not ready, 1 failure>

  ✅ Nothing to do

  Shipped to Prod (<n>)
  ✅ #<n> <title> (<card url>): <one line on what changed>

  Shipped to Preview (<n>)
  ✅ #<n> <title> (<card url>): <one line on what changed>

  Cards Not Ready (<n>)
  ✅ #<n> <title> (<card url>): <q> questions to answer

  ✅ Repo state clean
  ```

  Rules:
  - First line after the subject: `✅ Nothing to do` when nothing needs the
    user. Otherwise one `❌` line per failure: what failed, the card link if
    there is one, and what the user needs to do to fix it.
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

## 1. Assess every card once

**Default scope.** If the user names no cards or list, triage the cards in
Ready To Start where the user is the only member (the card's `idMembers` is
exactly the user's id; a card that also has anyone else is skipped).
Anything the user writes (card names, numbers, URLs, a list or a filter)
overrides this default. Pass the resolved card list to `assess-cards` and
`ship-cards` explicitly.

Run the `assess-cards` skill (via the Skill tool) on the full list. It reads
each card, its comments and mocks, grounds it in the current app and returns
a verdict per card:

- **Ready**: no comment is posted. Keep its list of assumptions.
- **Needs input**: it posts one question comment for the creator and moves
  the card to Not Ready.

Two adjustments while it runs:
- **Skip its push notification.** This skill sends a single one at the end.
- **Don't re-ask.** If a card already has an earlier question comment from
  me that nobody has answered yet (no later comment from the creator), don't
  post another. Mark the card **Still waiting** and move it to Not Ready if
  it's still in Ready To Start. If the creator has replied since, treat the
  reply as settling those questions and assess again with the answers.

Respect dependencies: if a Ready card depends on a card that is Needs input
or Still waiting (for example it needs a feature the other card builds),
mark it **Blocked by #N** rather than Ready, move it to Not Ready and post a
one-line comment: "Waiting on [#N](<card url>) before I can start this."
(only if the card doesn't already have that comment).

Needs input, Still waiting and Blocked cards all end up in Not Ready, so
they leave the Ready To Start queue and a scheduled run doesn't pick them up
again every time. Whoever answers or unblocks a card moves it back to Ready
To Start. Never change their members. If the board has no Not Ready list,
leave them where they are.

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
