---
name: triage-cards
description: Take a list of Trello cards (or a whole list like "Ready To Start"), decide which are ready to build, run `assess-cards` so the not-ready ones get questions posted, then run `ship-cards` on the ready ones (straight away when no card has questions, otherwise after the user confirms). Use when the user asks to "check which cards are ready and work them", "triage", "ship what's ready and assess the rest", or gives a mixed set of cards without saying whether they're ready.
---

# Triage cards: ship what's ready, assess the rest

This skill is a router. It does one readiness pass, then hands each card to
the right skill. It never builds or comments on its own. It needs the
`assess-cards` and `ship-cards` skills installed alongside it.

When no card ends up with questions, invoking this skill is the user's go
ahead to ship every Ready card (step 2). Otherwise `ship-cards` needs the
user's explicit go ahead, given after step 2 below.

Never use em dashes anywhere (Trello text or the chat summary).

## 1. Assess every card once

Run the `assess-cards` skill (via the Skill tool) on the full list. It reads
each card, its comments and mocks, grounds it in the current app and returns
a verdict per card:

- **Ready**: no comment is posted. Keep its list of assumptions.
- **Needs input**: it posts one question comment for the creator.

Two adjustments while it runs:
- **Skip its push notification.** This skill sends a single one at the end.
- **Don't re-ask.** If a card already has an earlier question comment from
  me that nobody has answered yet (no later comment from the creator), don't
  post another. Mark the card **Still waiting** instead. If the creator has
  replied since, treat the reply as settling those questions and assess
  again with the answers.

Respect dependencies: if a Ready card depends on a card that is Needs input
or Still waiting (for example it needs a feature the other card builds),
mark it **Blocked by #N** rather than Ready.

## 2. Confirm, then ship the Ready cards

If no card is Ready, skip to step 3 and say so.

**No questions anywhere: ship without asking.** If every card is Ready (no
card is Needs input, Still waiting or Blocked), don't ask. Show the Ready
cards (one line each, with the main assumptions) and go straight to
`ship-cards` on all of them. The user's `/triage-cards` request is the
invoking request `ship-cards` quotes before pushing.

**Any card has questions: ask first.** Otherwise, show the user the Ready
cards (one line each, with the main assumptions) and ask them to confirm
shipping them. Use `AskUserQuestion` with options like "Ship all of them" /
"Ship some" / "Don't ship". Wait for the answer; don't assume it. The
user's confirmation is their invoking request for `ship-cards`, and that's
the message it quotes before pushing.

Either way, run the `ship-cards` skill on exactly the cards being shipped,
in one run, passing along each card's assumptions from step 1 so it doesn't
redo the analysis.
`ship-cards` still does its own quick triage; if it downgrades a card to
Needs input, accept that and report it.

## 3. Report back

Keep it to one summary covering every card:
- **Shipped**: what `ship-cards` reported (commits, what the user still
  needs to do).
- **Needs input**: the card link, the questions in one line each and who
  was @mentioned.
- **Still waiting** / **Blocked by #N** / **Not shipped**: one line each.
- A suggested order for the remaining cards once answers come in.

Then send exactly one `PushNotification` (load it with ToolSearch first),
e.g. "Triaged 4 cards: shipped #12, questions posted on #14 #19, #21
still waiting".
