---
name: add-multiple-cards
description: Read a block of text (call transcript, meeting notes, feedback email, chat thread, a pasted doc or a file or doc link), pull out the bugs and features that belong on the project's Trello board, add the obvious bugs and agreed features straight away with the add-card skill's templates, and ask the user about the rest (whether a maybe-item should be added, or what an under-specified one means) before adding them. Use when the user pastes a transcript or notes and asks to "add the cards from this", "log everything from the call", "pull the bugs and features out" or "turn this into cards".
---

# Add multiple cards

Invoking this skill IS the user's request to create the cards it decides on
(and the ones the user approves in step 3). No other Trello writes, no code
changes, no commits.

Never use em dashes anywhere (Trello text or the chat reply). Trello writes
post as the user, in the first person, never naming the user.

**Read the `add-card` skill first** (it must be installed alongside this
one). Every card made here follows its project settings and steps 1 to 4
exactly (classification, duplicate check, template, creation, the card
assignee as the only member). This skill only decides *which* cards to make.

Every card it creates goes to add-card's **card assignee** as its only
member, even when the source says someone else will do it ("Sam will look
into that"). Put who took it on in the "From the ... call" line, never in
the card's members.

## 1. Read the source

The source is whatever the user gave: pasted text, a local file (read
it), or a document link (read it with the matching connector). Read all
of it. Note the date and who was speaking when the source shows it.

## 2. Pull out candidates

Go through the source in order and list every bug or feature for this
project's app that someone raised. Merge mentions of the same thing into
one candidate. For each, note the quote(s) it came from, and sort it into
one bucket:

- **Add**: an obvious bug (someone describes the app doing something
  wrong, clearly enough to reproduce or locate) or an agreed feature
  (someone proposed it and the others agreed, it was assigned, or the
  person who decides said "let's do it").
- **Ask whether to add** (medium or high ambiguity): brainstorming,
  "maybe", "someday", "what if", a disagreement nobody settled, an idea
  only one person floated with no response, or something that might be
  for another product rather than this app.
- **Ask what it means** (under-specified): it's clearly wanted but the
  card couldn't say what to build or what's broken (e.g. "the profile page
  feels off", "fix the thing Sam mentioned").
- **Skip**: personal to-dos and action items that aren't board work
  ("I'll email the client", "send me the deck"), things already done in
  the call, and chit-chat. A manual product task that was agreed (e.g.
  "we need to set up the company page") is a chore card per add-card
  step 1 and goes in **Add**.

Then run add-card step 2 (duplicate check) on every candidate. A candidate
already on the board moves to the report as `Already on the board`; it is
not asked about or added.

## 3. Ask about the unclear ones

**Consult the repo first.** Before asking about any candidate, settle what
the repo can answer (add-card step 3, "Consult the repo before asking"):
what the app does today, whether a reported bug is actually intended
behavior, whether a proposed feature already exists (live on the trunk, or
on staging when the project has it). A candidate the code already answers
isn't a question: an existing feature is reported as
`➖ Already in the app: <item> (<where>)`, intended behavior as
`➖ Works as designed: <item> (<why>)`. Only ask what the repo can't
settle, and put what the code shows into the question so the user can
answer in one tap.

If any candidates are in the two Ask buckets, ask with `AskUserQuestion`
before creating anything from those buckets (the **Add** cards can be
created first). Up to 4 questions per call; repeat until all are answered.

- Ask whether to add: question `Add "<proposed card name>"? <one line on
  what was said and by whom>`, options `Add as feature` / `Add as bug`
  (only when it could be a bug) / `Skip`. Put the likelier choice first.
- Ask what it means: question `"<quote>": what should this card do?`,
  with 2 or 3 concrete readings as options (the user can pick Other to
  type their own), plus `Skip`.

Each question must stand alone (the user may only see the dialog), so name
the item and quote enough of the source in the question itself. Never ask
about the **Add** bucket.

## 4. Create the cards

For each card to add, follow add-card steps 3 and 4. In the description,
add one line saying where it came from, e.g. `From the 2026-11-12 call
with Sam: "<short quote>"` (under "Deeper explanation" for features,
before the reproduction steps for bugs, under "Why" for chores). Create
cards in the order they came up in the source.

## 5. Report

One line per item, no headings, in this order:
- `✅ Added [#N](<url>) <name> (<Bug|Feature|Chore>)` for each new card
- `➖ Already on the board: [#N](<url>) <name>`
- `➖ Already in the app` / `➖ Works as designed` lines from step 3
- `⏭️ Skipped: <item>` for items the user declined or answered Skip
- If personal action items were skipped, one final line listing them in a
  few words each, so nothing from the call is lost: `Not added (personal
  to-dos): <a>, <b>`.
