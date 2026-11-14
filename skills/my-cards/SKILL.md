---
name: my-cards
description: List the user's open Trello cards on the project board (every card they are a member of that isn't in a done, archive or canceled list, or archived) as a numbered list, each line the bold linked card number and bold title, then one plain sentence on what needs to be done. Read-only. Use when the user asks "what are my cards", "my-cards", "what's on my plate", or "what's assigned to me".
---

# My cards

Read-only: never move, comment on, label or change members on any card.
Never use em dashes in the reply.

## Project settings

Read these from the project's CLAUDE.md if it lists them; otherwise look
them up once with the project's Trello tools:
- The Trello board for this project.
- Its open lists, in the order to show them (default: Doing, Blocked,
  Ready To Start, then the not-ready and backlog lists in board order).
  Lists whose names say done, archive or canceled are closed and never
  shown.
- **The user (get_me)**: always looked up at run time, never stored in
  the settings: the Trello member the MCP calls are made as, from `get_me`
  (the Trello connector's `trelloReadMember` `get_me`), or
  `node automation/trello-me.mjs` (copied into the project) when the
  project's Trello MCP has no get_me tool. Settings may list old accounts
  of theirs whose cards also count.

If the user names someone else ("Sam's cards"), use that person's member
id from the board's members instead.

## Steps

1. Read the board's lists once to confirm the open lists (pick up any new
   open list by name, skipping closed ones).
2. For each open list, fetch its cards with name, number (`idShort`),
   short URL, members, description (a preview of about 800 characters is
   enough) and closed flag, in parallel. Keep cards that aren't closed and
   whose members include one of the user's ids. Keep the list order above,
   and Trello's order within each list.
3. For each card, write one short plain sentence (about 15 words or
   fewer) on what needs to be done, from the description: the user story's
   action for a feature, the broken behavior to fix for a bug, the action
   for a chore. If the description is empty, base it on the title. For a
   card that is blocked or waiting on someone (a Blocked list, or a
   not-ready list with open questions), say what it's waiting on instead.

## Output

A numbered list and nothing else (no headings, no intro line):

```
1. **[#912](https://trello.com/c/AbCd1234): Bug: Saved items vanish on refresh**: Make saved items persist after the page reloads.
2. **[#915](https://trello.com/c/EfGh5678): Team Invites**: Let account owners invite teammates by email.
```

The card number (linked to the card's short URL) and title are bold; the
sentence after the colon is not. If there are no open cards, reply with the
single line `No open cards.`
