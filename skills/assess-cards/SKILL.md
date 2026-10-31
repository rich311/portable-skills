---
name: assess-cards
description: Read one or more Trello cards (by name, number, URL, or a whole list), compare what each asks for with how the app works today, and find the rare product questions that block the build (self-contradictions, major-rework risks, founder-only calls, or things only the creator has; everything else is assumed, not asked). Posts a short first-person comment only when such questions exist; otherwise the card is reported as ready with the assumptions listed. Product decisions only, no technical questions. Use when the user asks to "assess", "review", "scope" or "find the open questions on" a card, or asks what needs answering before a card can start.
---

# Assess cards

Keep it light. The goal is to unblock work, not to interrogate the spec.
Accept some ambiguity. Only stop a card for the reasons in step 3: the
card contradicts itself, any assumption risks major rework, it's a
founder-only call, or it depends on something only the creator has.
Everything else gets a reasonable assumption instead of a question.

Invoking this skill IS the user's request to post one question comment on
each card that has such questions, move that card to the Needs input list
and, when the project names a Needs input owner, make them its only member
(step 4). A card with none gets no comment and stays where it is. It does
not cover any other Trello write: never change members on any other card,
change labels, edit a description, or move a card anywhere else. No code
changes, no commits, no dev server.

Never use em dashes anywhere (Trello text or the chat summary). Trello writes
post as the user, so write them in the first person and never name the user.

## Project settings

Read these from the project's CLAUDE.md if it lists them; otherwise look
them up once (`trelloReadMember` `get_me` for the user,
`trelloReadBoard` for the board and its members):
- The Trello board for this project.
- Its "Ready To Start" list and the **Needs input list** where cards with
  open questions go: the one the settings name (e.g. a prioritized not-ready
  list), otherwise "Not Ready" (or the project's equivalent). If there's
  neither, leave cards where they are.
- Optional **Needs input owner**: the member who should be the only member
  of a card with open questions. If the settings don't name one, leave
  members as they are.
- The user's Trello member id (whose voice the comments are in).

## 1. Read each card in full

1. Resolve the card(s). For a name, use `trelloSearch` with `search_cards`.
   For a URL or number, use `trelloReadCard` `get`. For a whole list, use
   `trelloReadCard` `list_by_list`.
   **Default scope.** If the user names no cards or list, assess the cards
   in Ready To Start where the user is the only member (the card's
   `idMembers` is exactly the user's id). Anything the user writes (card
   names, numbers, URLs, a list or a filter) overrides this default.
   **Manual cards.** Always skip a card with a label named "Manual" (or the
   manual label the project settings name) or a name starting with "Chore",
   even when the user names it or gives its list: it's a task for a person
   to do by hand, not code. Don't comment on it, move it or change its
   members; just list it as skipped (manual) in the report.
2. Read everything: the description, checklists, ALL comments
   (`list_comments`, and page through them) and attachments
   (`list_attachments`; open images or mocks with
   `mcp__trello__download_attachment` when they add detail). Later comments
   often settle or reopen parts of the spec, e.g. a duplicate card archived
   or a proposal nobody answered. Note which parts are settled and which are
   still open.
3. Find who created the card (`list_activity`, the earliest create action).
   They're the one the questions are for.

## 2. Ground it in the current app

Before writing questions, find out how the app handles this area today, so
the questions are specific and you don't ask about things the code already
answers. For anything bigger than a single component, delegate this to an
`Explore` agent (very thorough), asking for concrete facts with file:line
references: entry points, the data model involved (migrations or schema
files), role and routing branching, and anything the card assumes exists but
doesn't. Spot-check two or three of the agent's key claims with `grep`
before relying on them.

Also check for related cards on the board (overlapping scope, duplicates,
cards the spec depends on). Reference them by number in the questions.

## 3. Decide what to ask and what to assume

Scan for:
- Contradictions inside the card (e.g. required fields listed twice and
  differently) or between the card and its comments.
- Undefined terms the build depends on (a plan name, a status, a user
  segment the card names but never defines).
- Missing states: pending, rejected, empty, already-taken, no-match, existing
  users who signed up under the old flow.
- Who does what: who approves, who gets notified, who can see it before
  approval.
- Features the card assumes exist but don't (from step 2). Ask whether
  they're part of this card or a later one.
- Overlap with related cards and how the two flows fit together.
- Missing copy and mockups.

Then filter hard. For each candidate, ask: can I make a reasonable
assumption that the creator would most likely agree with, and that would be
cheap to change later? If yes, it's an **assumption**, not a question.
Typical assumptions: follow the existing pattern in the app, use the
obvious empty/error states, write sensible copy, match the design system
when there's no mock, keep existing users' behaviour unchanged, admins can
see everything.

Only keep it as a **question** when one of these is true:
- **Self-contradiction.** The card contradicts itself (or its comments, or
  its mock) on something that changes what gets built, and nothing settles
  which version wins.
- **Major rework.** Every assumption we could make risks major rework if
  it's wrong, e.g. throwing away most of the build or redoing a data
  migration. Rework that's a small follow-up doesn't count.
- **Founder-only call.** It's a business, pricing, policy, legal or cost
  call that only the owners of the product can make.
- **Depends on the creator.** It depends on something only the creator
  has: a missing mock the card explicitly relies on, an undefined term with
  no sensible reading, or an external account or credential.

Everything else is an assumption, including scope questions ("is X part of
this card?"), unbuilt features the card leans on (build the simplest
version or leave a placeholder), copy with a sensible default, and mocks
that are partial. Pick the lean you'd have suggested and list it as an
assumption so the creator can push back.

Expect zero questions. One or two is fine. Three is OK only if each one
clearly meets a reason above. Four or more is too many: turn the weaker
ones into assumptions.

**Product decisions only.** Leave out anything an engineer decides: schema
and table choices, whether to store a field, matching or search algorithms,
API design, how to split the work into cards. If a technical point hides a
product decision, ask the product decision in plain language and don't name
any tables or code. For example, "should the submitted company go into the
`companies` table?" becomes "before we approve a submitted company, should it
be hidden or show as unverified?".

Number the questions in one sequence. Only group them under bold headings
if there are more than four. List the assumptions too, briefly, one line
each, and only the ones the creator might plausibly disagree with (skip the
obvious ones).

If there are no questions, stop here for that card: don't comment, and
report it as ready to build in step 5.

## 4. Post the comment (only if there are questions)

Write it in the user's voice, in the first person, the way they'd talk to a
teammate:
- If someone other than the user made the card, start with an @mention of
  the creator's Trello username. If the user made it, don't @mention anyone.
- The opening line says these need answering before work can start.
- Then the numbered questions. Keep each question short and plain, and
  where it helps, say which way I'd lean so a one-word answer works.
- Then a short "Assuming unless you say otherwise:" list with the
  assumptions from step 3, if any.
- Use "I" and "we", never refer to the user in the third person.
- No em dashes, and no table or file names.

Post with `mcp__trello__add_comment` (card id from step 1). After posting,
re-read the comment (`trelloReadCard` `list_comments`) and fix any mistakes
with `mcp__trello__update_comment`. Don't post a second comment.

Then move the card to the **Needs input list** with `mcp__trello__move_card`.
If the project names a Needs input owner, make them the card's only member:
add them with `mcp__trello__assign_member_to_card` (skip if already on it),
then remove every other member, the user included, with
`mcp__trello__remove_member_from_card`, and re-read the card to confirm
`idMembers` is exactly the owner's id. Otherwise leave its members as they
are. That keeps it out of the Ready To Start queue (and any scheduled triage
run) while the questions are open; whoever answers moves it back to Ready To
Start, and the next run assesses it again with the answers. Only move or
reassign cards you just posted questions on.

## 5. Report back

For each card, tell the user:
- A link to the card and its verdict: **Ready** (no comment posted) or
  **Needs input** (questions posted as a comment, the card moved to the
  Needs input list and, if set, given to the Needs input owner; the
  description wasn't touched).
- For Needs input: the questions in one line each, and who was @mentioned,
  so they know a notification went out, with an offer to remove the mention.
- The assumptions you're going with, one line each.
- Anything in the card's comments that was already settled, plus related
  cards it overlaps with.

After the report, send exactly one mobile notification with
`PushNotification` (load it with ToolSearch first): a one-line summary like
"Assessed 3 cards: 2 ready, 3 questions posted on #14". Never send one per
card or per step.
