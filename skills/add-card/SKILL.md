---
name: add-card
description: Turn one request into a new Trello card in Ready To Start, always assigned to the project's card assignee (default: the user) as its only member. Classifies it as a bug (Bug template, bug label), a feature (Feature template plus an Acceptance Criteria checklist) or, when it's work a person has to do by hand and Claude can't, a chore (name "Chore: ...", manual label), then fills in every template section the request and the app can answer. Use when the user asks to "add a card", "log a bug", "make a card for", "put this on the board" or "create a chore".
---

# Add card

Invoking this skill IS the user's request to create the card. It covers
exactly one new card (plus its checklist, labels, member and any
attachments the user gave). No other Trello writes, no code changes, no
commits.

Never use em dashes anywhere (Trello text or the chat reply). Trello writes
post as the user, so write them in the first person and never name the
user. Every `#N` card reference in Trello text is a markdown link to that
card.

## Project settings

Read these from the project's CLAUDE.md if it lists them; otherwise look
them up once with the project's Trello tools (board, lists, labels,
members) and use the names below:
- The Trello board, its **Ready To Start** list (every new card goes
  here) and its open lists (everything except the done, archive and
  canceled lists), used for the duplicate check.
- The **bug label** and the **manual label** (for chores). If the board
  has no manual label, ask the user once whether to create one.
- Optional **Bug template** and **Feature template** cards. When the
  project names them, read them and mirror their headings exactly; never
  edit them. Otherwise use the default templates in step 3.
- The **card assignee**: the member every new card is assigned to, as its
  only member, whoever runs the skill and whoever the request names as
  doing the work (that person can go in the description, never in the
  members). Defaults to the user. Everything else that means "the user"
  (whose voice the card is in) uses get_me at run time: the Trello
  connector's `trelloReadMember` `get_me`, or `automation/trello-me.mjs`
  when the Trello MCP has no get_me tool.
- The app's base URL, for bug reproduction steps.
- Any services a person must handle by hand (vendor dashboards Claude has
  no access to), to help spot chores.

## 1. Classify the request

Pick exactly one:

- **Chore**: something Claude can't do from this repo and its tools, so a
  person has to do it by hand. Examples: settings in a vendor dashboard
  Claude has no access to, DNS changes, buying or signing up for
  something, emailing or calling a person, legal or financial decisions,
  recording a video. Also anything the user calls a chore. If the request
  mixes code work with a manual step, make the card for the code work and
  put the manual step under "Deeper explanation" (or make a separate chore
  card too when the user asked for both).
- **Bug**: the app does something wrong compared with what it should do
  or used to do (an error, broken layout, wrong data, a flow that dead
  ends). The user saying "bug" settles it.
- **Feature**: anything else Claude can build: new behavior, a change to
  existing behavior, copy or design changes, admin tools, scripts, data
  work.

## 2. Check it's not already on the board

Search each open list for cards whose names share one or two key words
with the request. If an open card already covers the same thing, don't
create a new one: tell the user `Already on the board: [#N](url) <name>`
and ask whether to add a new card anyway. A loosely related card is not a
duplicate; mention it in the new card's "Deeper explanation" as a link.

## 3. Fill in the template

Use what the request says, plus a light look at the app so the card is
concrete (a `grep` or two for the page, route, component or button label
the request mentions; an `Explore` agent only if the area is unclear).
Never invent facts: a section the request and code can't answer gets "Not
provided", except where a sensible default is given below. Keep it short.
When the project has its own templates, use their headings in place of
these.

**Bug** (name `Bug: <short broken behavior>`, the bug label):

```
**Reproduction steps**

1. Log in to <app URL>/<path> as <account type>
2. <step>
3. <step>

**Expected Behavior**: <what should happen>

**Actual Behavior**: <what happens instead, including any error text>

**URL Where Error Occurred**: <full app URL, or Not provided>

**Account Logged in with**: <the account or role, or Not provided>

**Screenshots/Video**: <"Attached" if the user gave one, otherwise Not provided>
```

When the user gave only a symptom, write the most likely reproduction
steps from the code and say so ("Steps inferred from the app, not
confirmed"). Note severity in the first line if it's obvious (blocks
sign-up, payments or data loss).

**Feature** (name: 3 to 6 words in title case, no prefix, plus any
obvious area label the board has):

```
**User Story**: As a <persona>, I want to <action>, so that I can <value/benefit>.

**Deeper explanation of feature**: <context, constraints, related cards as links, where it lives in the app today>

**UX Flow for feature**:

1. <step>
2. <step>

**Copy Needed for Feature**: "<exact text the user gave>", or "Claude to write" when none was given

**Mockup of Feature**: <"Attached" if the user gave one, otherwise Not provided>
```

Then an **Acceptance Criteria** checklist: 2 to 6 items, each a testable
outcome starting "User is able to ..." or "<Thing> shows/does ...".

**Chore** (name `Chore: <action>`, the manual label):

```
**Why**: <what this is for, with a link to the related card if any>

**Where**: <direct link to the exact settings page when known>

**Steps**:

1. <step with exact button labels, field names and values>
2. <step>

**Done when**: <how to confirm it worked>
```

## 4. Create the card

1. Create the card in Ready To Start with the name, description and
   labels.
2. Feature only: add an `Acceptance Criteria` checklist with its items.
3. Attach any screenshot, video or mockup the user gave (as a file, never
   inline base64).
4. Always add the card assignee as a member, then re-read the card and
   confirm they are its only member (remove anyone else).

## 5. Report

One line: `✅ Added [#N](<card url>) <name> (<Bug|Feature|Chore>)`. Add one
short line per section left as "Not provided" only when filling it would
clearly help the build (e.g. "Copy left for Claude to write"). Nothing else.
