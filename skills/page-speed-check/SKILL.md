---
name: page-speed-check
description: Run a full speed audit of a web app on its non-production site. Scripts kept in tests/perf/ load every page for every role 3 to 5 times on desktop and mobile; up to 12 Sonnet sub-agents time every button, search, filter, save and AI action in their product area; scripts aggregate, compare with the previous run and re-measure anything outside normal performance; an Opus analyst reads the code behind the confirmed problems and writes the "what is slow, and why" verdicts; the result is a report page plus a bug card for every confirmed problem not already on the board. The first run in a project generates the scripts; every later run reuses and repairs them. Use when the user asks to "check page speed", "run a speed audit", "time the site", "find what is slow" or types /page-speed-check. Optional args, any order: area names (only those areas), runs=3..5 (default 5), "pages only" (no function testers), "no cards" (report only).
---

# Page speed check

Scripts do the measuring, aggregating, re-measuring, rendering and card text.
Agents only (a) write and repair those scripts and (b) explain the results.
That split is the point: a number an agent timed by hand cannot be compared
with the next run, a number a saved script produced can.

Everything lives in `tests/perf/` in the project (`test/perf/` when the
project's test folder is `test/`). When the folder exists, reuse it. When it
does not, section 2 generates it.

**Models.** Run the main session and the analyst on Opus (the strongest model
available): they design scripts, judge results and read code for causes. The
area testers run on Sonnet: they run saved scripts, patch selectors and add
missing timings.

Never use em dashes in anything this skill writes.

## Project settings

Read these from the project's CLAUDE.md (ask once for anything missing, then
suggest adding it there):

- The non-production site to test and how to tell it from production (host
  names, database or API project ids). **Never target production.**
- Test accounts for each role and the env var holding their password; how to
  create and delete a throwaway account.
- How pages are discovered (a routes folder, a router file, a sitemap).
- Lint command, trunk branch, whether pushing has standing approval, and any
  rule about worktrees.
- Optional, for cards: the board, its open lists and done lists, the bug
  label, a bug template card, and who new cards are assigned to.

## 1. Set up (main session)

1. Follow the project's rules for isolated work (a worktree when it asks for
   one). This skill commits only `tests/perf/`, never app code.
2. `tests/perf/` missing or incomplete: do section 2 first.
3. Run the prepare step (`node tests/perf/run.mjs prepare`). It must: confirm
   the site answers; confirm it is the non-production site (stop if the
   bundle or config references production); sign in every test account; record
   the deployed commit; look up the ids this run needs; create the run folder
   and print its path. Pass that path to every later command.
4. Print the page plan and read it. A page skipped for a missing id is either
   fixed now or named in the final report.

## 2. First run: generate the scripts

Write these into `tests/perf/`, small and dependency-light (the project's
browser automation library, usually Playwright; plain Node otherwise). Read
the project's existing end-to-end helpers first and reuse their login and
account helpers.

| file | job |
|---|---|
| `perf-lib` | Shared helpers: refuse production targets; launch, context, login per role (including two-step sign-in where a role needs it); `timedGoto` (status, TTFB, FCP, LCP, load, total to network idle, request count, transfer size, final URL); `timedAction(label, fn)` (click to visible result); `timedFetch` (API call from inside the signed-in page); `repeat(area, name, n, fn, meta)`; `recordTiming` appending rows to `<run folder>/<area>.json`; `RUNS` clamped to 3..5 |
| `routes` | Build the page plan from the project's own routes, so a new page is measured without edits: pages per role, dynamic routes filled from looked-up ids, an explicit skip list with reasons, and each role's read-only API list |
| `ids` | Look up the ids dynamic routes need, fresh on every run (never hard-code one) |
| `pages` | Baseline: every page for every role, `RUNS` times, desktop and mobile, plus the API list; shardable so 3 processes can run side by side; a role whose login changes account state (re-enrolling a second factor) stays in one shard |
| `aggregate` | Rate every row, flag outliers, compare with the previous run, write `report.json`, `meta.json`, `anomalies.json` |
| `retest` | Re-measure every anomalous baseline row on its own and mark each anomaly confirmed or transient |
| `render` | `report.json` + `verdicts.json` to one self-contained HTML report |
| `cards` | `verdicts.json` to card names and descriptions; record a card link on a verdict |
| `run` | One entry point: `prepare`, `baseline <shards>`, `area <name>`, `analyze`, `render` |
| `tools/` | `waterfall` (request waterfall for a role and path), `bundle` (script sizes), `dbtimes` (raw query timings) for the analyst |
| `areas/<area>/` | One folder per product area with its function-timing scripts and an `ORDER` file; cleanup scripts for the data they create |
| `PERF-BRIEF.md` | The tester brief (section 4's rules, the helper list, the accounts, the report format). Every tester reads it. |

Then write the areas table into this project's copy of the skill (or
`tests/perf/AREAS.md`): one row per product area with its accounts and what it
covers. Split by who uses it and what it changes, 12 areas at most, each
small enough for one agent: sign-in, each role's onboarding, each role's main
screens, each AI feature, admin, public pages. An area that permanently
changes account state uses throwaway accounts it creates and deletes.

Rules the scripts must follow, each learned from a wrong number:

- **Rows are appended, the latest wins.** A rerun after a fix leaves the old
  row in the file, so `aggregate` keeps the newest row per area, kind, name,
  role and viewport.
- **Compare by name, not id.** The key used to match the previous run replaces
  ids in URLs, so a database reset does not break the comparison.
- **Check where a page landed.** Record the final URL and status; a page that
  redirected to a login or verification screen is a failed measurement, not a
  fast one.
- **Wait for what the user sees.** Count only visible loading placeholders, and
  wait on the element or response the action produces, never a fixed sleep.
- **Rate limits and one-time actions.** Use a different account or value per
  run where the app limits repeats (password reset, invites, unlocks).
- **First run is the cold one.** Keep it in the row; rate pages on the median
  of the warm runs.
- **One process per area file.** Parallel writers to one file lose rows.

Normal performance, set in `aggregate` and stated in the report: page warm
median under 3 s and TTFB under 1.5 s; action under 3 s; AI action under 30 s;
no server errors. Outlier: max over 3 times the median and at least 2 s above
it. Regressed: up 30% and 0.5 s on the previous run. Change these to the
project's own targets when it has them.

## 3. Page baseline (scripts only, alone on the site)

Run the baseline in the background (`run.mjs baseline 3`) and wait for it to
finish before starting anything else. Nothing else touches the site meanwhile,
so these are the authoritative page numbers. Then read a few rows per role and
check the final URL is the page asked for; a role that landed on a sign-in
screen is fixed in `perf-lib` and re-measured before going on.

## 4. Function testers (up to 12 Sonnet agents in parallel)

Skip for "pages only". Otherwise spawn one agent per area, all in one message,
on Sonnet, 12 at most; when the user named areas, only those. Prompt:

> You are the `<area>` speed tester for a /page-speed-check run. Read
> `<repo>/tests/perf/PERF-BRIEF.md` in full first. Work from `<repo>`, with the
> run folder `<run folder>` and `<runs>` runs set on every command. Your area:
> `<area>` (`<covers>`). Accounts: `<accounts>`. Start with
> `node tests/perf/run.mjs area <area>`, fix whatever fails, add any function
> in your area the scripts do not cover yet, and leave
> `tests/perf/areas/<area>/` running clean end to end. Do not change app code,
> commit, push or write to any external system. Finish with the short report
> the brief describes.

On a first run the area folders are empty, so the same agents write them: say
so in the prompt ("no scripts exist yet; write them").

The brief tells each tester to: time what the user feels (click to visible
result), 3 to 5 runs each and never fewer than 3 (AI actions 3, with long
timeouts); use desktop, plus mobile only where mobile runs different code;
be gentle (one browser, one action at a time); find uncovered functions by
listing the API calls its pages and components make; clean up its test data;
and reply in under 50 lines with a table of function, role, runs, median,
rating, API route and likely cause, then scripts fixed or added, functions it
could not measure and why, and test data left behind.

Collect the reports. A function a tester could not measure goes into the
final report, not into a card. Two things to check before aggregating: no
tester process is still running, and nothing a tester changed (a login that
now needs a second factor, a new id) also applies to the baseline scripts.

## 5. Aggregate and confirm (scripts)

`run.mjs analyze` runs `aggregate` then `retest`. Baseline rows outside normal
are re-measured alone, `RUNS` more times, and confirmed only when the retest
is still slow, still regressed or still erroring. Area rows are confirmed from
their own runs: at least 3 runs with at least 2 over the threshold, and never
on an outlier alone. Only confirmed anomalies become verdicts or cards.

Read the failed rows too. Expected 4xx responses (a logged-out call, a wrong
method, a deliberate not-found page) are script noise to tidy, not findings.

## 6. Analysis (one Opus agent)

When nothing was confirmed, write `[]` to `verdicts.json` and skip this.
Otherwise spawn one agent on Opus:

> You are the analyst for a /page-speed-check run. Run folder: `<run folder>`;
> repo: `<repo>`. Read `anomalies.json` (only entries with `confirmed: true`
> count), `report.json`, `meta.json` and, when `meta.json` names a previous
> run, that run's `verdicts.json`. Group the confirmed anomalies by cause (one
> page and the API behind it are one verdict). For each group read the page,
> component and handler code and find the cause: sequential awaits, unbounded
> or paged scans, N+1 fetches, payload size, client fetch waterfalls,
> non-streaming AI calls, fixed timers, redirects. Measure what you need with
> the scripts in `tests/perf/tools/`. Write `<run folder>/verdicts.json`: an
> array, most severe first, each `{ title, number, where, cause, fix, ai,
> severity: "high"|"medium"|"low", needsCard, cardName, url, account, steps,
> expected, actual, keys }`. `number` is the headline measurement; `actual`
> gives the runs and medians; `keys` lists the anomaly keys it covers;
> `needsCard: false` for transient results, expected ones (a fixed product
> timer, an expected 4xx) and AI results within the limit; `cardName` names
> the broken behavior plainly. Carry over the previous run's `card` for a
> verdict that is the same problem. Verify any hint in this prompt rather than
> assuming it. No em dashes. Do not change app code, commit or write to any
> external system. Reply with one line per verdict.

Give the analyst what the run showed, as observations to check, not
conclusions: which role or view was slow while another was fine, and what a
tester already suspected.

## 7. Report page and cards (main session)

1. `run.mjs render` writes the report: summary counts, "what is slow, and
   why" (the verdicts), changes since the last run, every measurement in a
   filterable table, method and caveats. Publish it the way the project shares
   pages (an artifact when the session has that tool; otherwise give the file
   path) and save the link in `meta.json`.
2. Skip the rest for "no cards", or when the project names no board.
3. Dedupe against the board's open lists. A verdict whose problem already has
   an open card gets that card recorded as existing, plus a one-line comment
   with this run's numbers only when they moved by more than 30%. A carried
   card that is now done or archived means the problem is still there: log a
   new card that links the old one.
4. `cards` builds the name and description for each verdict that still needs a
   card: severity and where it was found, reproduction steps, expected and
   actual with the runs, the cause from the code, the suggested fix, the URL
   and the account. Create each card the way the project's card rules say
   (template, list, label, assignee), attach the report file as well as its
   link when the link needs a login, and record the card on the verdict.
5. Render and publish again so the verdicts link their cards.

## 8. Commit the scripts and clean up

1. When `tests/perf/` changed: lint, commit ("Page speed check <date>: update
   timing scripts"), then follow the project's push rules. Test scripts only.
2. Delete test accounts and rows the testers left behind, and check with a
   query rather than trusting the reports. Say what could not be restored (a
   spent credit, a reset second factor).
3. Leave the run folder where it is (outside version control); the next run
   compares against it.
4. Make sure no browser, baseline or dev server process from this run is still
   going.

## 9. Final report

Short: the report link; rows, runs and the fast, ok, slow and failed counts;
what got slower and faster since the last run (top 5 each, and say when a
change is a script fix rather than an app change); confirmed problems with
their cards, marked new or already on the board; what could not be measured
and why; side effects and test data left behind; then "Left for you to do"
(numbered, or "Nothing needed from you.").
