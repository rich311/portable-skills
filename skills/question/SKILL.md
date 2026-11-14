---
name: question
description: Answer a question about how the project's app works (what a page, button, role, plan, email, AI feature, setting or rule does, who can see what, why something behaves a certain way, whether something is live yet) authoritatively from the repo's code, not from memory or docs alone. Reports what's live (the trunk branch) and, when different, what's on staging, in plain language with file references. Read-only. Use when the user types /question or asks "how does X work", "what happens when", "can a customer see", "why does the site", "is X live yet" or any other question about app behavior.
---

# Question

Answer the user's question about app behavior from the code. The repo is
the source of truth: docs, cards, memory and help content can be out of
date, so use them only as pointers to the right code, and say so when they
disagree with the code.

Read-only: no file edits, commits, Trello writes, database writes or dev
server. Never use em dashes.

## Project settings

From the project's CLAUDE.md: the trunk branch (default `main`), the
optional staging branch, the app's roles, and any docs that map the app
(a site guide, design or architecture docs).

## 1. Pin down the question

Work out which role it's about and which environment (live by default, or
staging). If the question is ambiguous in a way that changes the answer
(e.g. "can they see it" with no role), answer for each role that matters
instead of asking. Ask only when no reasonable reading is possible.

## 2. Read the code that actually runs

1. `git fetch -q origin <trunk> <staging>`. Read from `origin/<trunk>`
   with `git grep <term> origin/<trunk> -- <paths>` and
   `git show origin/<trunk>:<path>`, never only the local checkout (it may
   be stale, on another branch, or mid-edit by another session).
2. Find the entry point (a site guide or route map if the project has
   one), then the routes and pages, components, business logic, API
   routes, middleware (redirects and role routing), database migrations
   and access policies (who can read or write what), AI prompts, email
   code, and scheduled jobs.
3. Trace the path end to end: the UI that shows it, the condition that
   gates it (role, plan, feature flag, env var, data), and the server code
   or policy that enforces it. A UI check alone isn't the answer when a
   server route or access policy decides it. For a broad question, hand
   the search to an `Explore` agent (very thorough, asking for file:line
   facts) and spot-check its key claims before answering.
4. When the project has staging: `git diff --stat origin/<trunk> origin/<staging> -- <paths>`
   on the files involved. If staging differs, read that version too.

Some behavior isn't settled by code alone: data in the database, env vars
and hosting settings, third-party configuration (payments, email, auth
provider). Say exactly which setting or data decides it and what the code
does for each value. Don't guess at the current value.

## 3. Answer

Lead with the direct answer in one or two plain sentences a non-developer
can act on, using the app's own button and page names. Then, only as
needed:
- the conditions and exceptions (per role or plan) as short bullets
- `On staging (not live yet):` and the difference, when staging differs
- what code doesn't decide (step 2's settings or data), when relevant
- `Where in the code:` two to five `path:line` references (line numbers
  from the trunk version)

If the code contradicts a doc, card or help content, add one line saying
which one is out of date. If the behavior looks like a bug, say so in one
line and offer to log it with `add-card`; don't create the card unless the
user says yes.
