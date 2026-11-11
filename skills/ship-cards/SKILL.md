---
name: ship-cards
description: Take a list of Trello cards (or "everything in Ready To Start"), check each is ready to build, have Sonnet sub-agents implement them in worktrees, verify with lint/typecheck/tests/build, a Playwright run against the dev server with screenshots and pre-push review agents (adversarial code review, security, requirements recheck, plus QA only for complex UI-heavy changes), apply any production migrations or scripts after dry runs and repeated checks, then push (optionally bugs to the trunk and features to a staging branch only), post a short comment on each card with screenshots and test steps, make the card's reviewer its only member and move it to Done (or a separate "Done in staging" list), report what changed, then confirm everything is pushed and all worktrees and branches are deleted and list what the user still needs to do. Use when the user asks to "ship", "work", "implement" or "knock out" a set of cards end to end.
---

# Ship cards end to end

Never use em dashes anywhere (code, commits, Trello text, summaries). Trello
writes post as the user, so write them in the first person and never name
the user.

## Cloud mode (optional)

Only when the project settings allow cloud sessions (Claude Code on the web).
A session is in cloud mode when `CLAUDE_CODE_REMOTE` is `true`. The cloud
environment should hold non-production keys only; a setup script (see
`automation/cloud-setup.sh`) writes the local env file from them and refuses
production values. In cloud mode:
- First check the env file exists and points at the non-production database.
  If it's missing, run the setup script once; still missing: stop the whole
  run with one `❌` line saying the cloud environment needs its keys.
- **The session itself never touches production.** It holds no production
  key. Cards with no production change ship as usual (pushing code to the
  trunk is fine when the host deploys it).
- **Production migrations through GitHub Actions (optional).** When the
  project has `automation/workflows/apply-prod-migrations.yml` (holding the
  production password as a repo secret) and a `GITHUB_PAT` in the cloud
  environment, a card's production migrations go through it with
  `automation/gh-workflow.mjs`, which waits and prints the run's `RESULT:`
  line. This replaces the local dry run and apply, in this order:
  1. The migration must be safe to apply before its code. Apply it to the
     non-production database as usual.
  2. From a fresh trunk worktree, commit only the card's migration files as
     `Card #<n>: migration <file>` and push them to the trunk. The file
     alone changes nothing in the app.
  3. Dry run: `node scripts/gh-workflow.mjs apply-prod-migrations.yml
     expected="<file> ..." apply=false card=<n>`. It must exit 0 and print
     `RESULT: dry-run-ok` naming exactly this card's files.
  4. Apply: the same with `apply=true` (it re-checks first). It must exit 0
     and print `RESULT: applied`.
  5. Merge the new trunk into the card's worktree and push the code as usual.
  The workflow only succeeds when the dry run matched exactly or the apply
  left nothing pending, so `RESULT: detail unreadable from here, run
  succeeded` with exit 0 still counts; say so in the card's report line. If
  step 3 or 4 exits non-zero, stop: don't push the code, `git revert` the
  migration commit and push the revert (unless step 4 got as far as
  applying; then leave it and say so), and report the `RESULT:` line as the
  card's `❌`.
- **Every other production change needs a local run**: data scripts, SQL
  writes, hosting or database production settings, and migrations when
  there's no workflow or token. A card that needs one is not pushed: give it
  a `❌` line ("needs a production change, run it locally"), make the
  default assignee its only member and move it back to Ready To Start so the
  next local run ships it. Other cards ship as usual.
- **Bug cards still go live.** Cloud mode changes how production is reached,
  not where cards go: a bug card ships to the trunk and moves to the Done
  (production) list, never the "Done in staging" list.
- A cloud session's files vanish when it ends, so nothing is kept for resume
  (step 9): finish a card or drop its work and report it.
- If the cloud git proxy refuses a push to the trunk or staging branch, don't
  work around it (no other branch, no API push): stop that push and report
  `❌`.
- Playwright uses the browser the setup script installed (no
  `executablePath`). `lsof` may be missing: check ports with `ss -ltn`. Use
  `cp -R` where macOS steps say `cp -c -R`.
- Scheduled unattended runs can be a cloud routine (see "Cloud unattended
  mode" in `triage-cards`) or the local job in `automation/`; never both.

## Project settings

Everything project specific comes from the project's CLAUDE.md (and the docs
it points to). Before starting, find each of these there; look up what's
missing (Trello via `trelloReadBoard` / `trelloReadMember` `get_me`, commands
via `package.json`) and only ask the user for what you can't find:
- **Trello:** the board, its "Ready To Start", "Doing" and "Done" lists (or
  the project's equivalents), the user's member id, and the **fallback
  reviewer** who gets a card when the user created it (if none is named,
  leave the user as the member).
- **Repo:** the GitHub `<owner>/<repo>` for commit links, the trunk branch
  (default `main`), and any long-lived branch that must be kept in sync with
  it after a push (e.g. `preview` or `staging`; skip the sync if there is
  none).
- **Commands:** install, lint, typecheck, unit tests, build, dev server
  (and which ports agents may use; never the user's own dev port), and the
  folder unit tests go in.
- **Deploy check (optional):** a command that confirms the hosting provider
  built each pushed branch and starts the build when a push event was missed
  (see step 6.5).
- **Design:** the design system or style guide doc, if any.
- **Test accounts:** non-production logins for each role, where the
  password comes from (an env var, never printed), and how to reset the test
  database if there is one.
- **Database:** production and non-production project ids, how migrations
  are applied (with a dry run), and how data scripts mark a production run
  (e.g. `--prod` for a dry run, `--prod --apply` to write).
- **Staged releases (optional):** a staging branch (e.g. `preview`), the
  Trello label that marks a bug card, a "Done in staging" list (e.g. "Done in
  Preview"), the staging database, and the workflow or button that promotes
  staging to production. See "Staged releases" below. Without these, every
  card ships to the trunk and goes to Done.

**Push and production approval.** Only push, or apply production migrations
or scripts, without asking if the project's CLAUDE.md (or the user, in this
session) grants standing approval for it; quote that approval before the
push. Otherwise ask once before step 6 and once before step 5.5. Approval
never covers force-pushes, rewriting history, or pushing commits that
aren't from this run. If the permission system blocks an action, do not
route around it (not via a sub-agent either): give the user the exact
command to run with `!` and continue once they have.

**Production dry run rule (every production change).** Approval or not, any
change to production gets a dry run first. It covers everything that
changes production, not just step 5:
- production database migrations and production data scripts
- any SQL write on the production database
- hosting, database or auth provider production settings (env vars,
  domains, auth, storage, secrets)

How it works:
1. **Dry run first:** the migration tool's dry run, the script's production
   dry-run mode (it prints every change it would make and writes nothing),
   or, for any other write, a read-only query or read of exactly the rows or
   settings the write would change.
2. **Check it item by item** against what the card expects: which
   migrations, which rows or settings, how many, and the before and after
   values.
3. **Only then the real run,** after one more re-check right before applying
   (another session may have changed production in between), then a
   read-only check afterwards that exactly the expected change landed.
4. **If anything looks off, or the change has no way to dry run, it doesn't
   run.** That card stops (pull it from the push if its code depends on the
   change), it gets a `❌` line in the final report saying why, and any
   unattended run's email carries the same line.
5. New production scripts must be written with that split: the production
   flag alone (e.g. `--prod`) is the dry run, and a separate write flag
   (e.g. `--prod --apply`) does the real write. A script without a dry run
   mode doesn't run against production.

## Staged releases (optional)

Only when the project settings define a staging branch, a bug label and a
"Done in staging" list. Each card then ships one of two ways.

**Which cards are bugs.** A card is a bug when any of these is true: it has
the bug label, its name starts with "Bug" (for example "Bug: ..." or
"Bug - ..."), or its description follows the bug template (it has the
"Reproduction steps", "Expected Behavior" and "Actual Behavior" headings,
or whatever headings the project's bug template uses). Decide this in
step 1, before building. When a card counts as a bug but has no bug label,
add the label right away (keep its existing labels) and note "labelled
Bug" on its report line, so a missing label never sends a bug to staging
only.

- **Bug card**: built from `origin/<trunk>`, pushed
  to the trunk (production) and synced to staging, with any production
  migrations or scripts per step 5. The card goes to **Done**.
- **Feature card** (every other card): pushed to the staging branch only.
  Its migrations go to the staging database only. The card goes to the
  **Done in staging** list. It reaches production when someone runs the
  project's promote workflow, which ships all of staging at once, applies
  the batch's migrations to production and moves the Done in staging cards
  to Done. So a feature's migration must be safe to apply to production
  before its code, on its own, possibly days later and next to other
  features' changes. Never run production write scripts for a feature card;
  list them under "Left for you to do" instead.

When a run has both kinds, ship the bug cards first (steps 4 to 6 on the
trunk), then the feature cards on top of the freshly synced staging branch.

## 1. Gather and triage the cards

1. Resolve the list. Card names/numbers/URLs from the user, or a whole list
   (`mcp__trello__get_cards_by_list_id`). Skip Bug-vs-feature filtering unless
   the user asked for it.
   **Default scope.** If the user names no cards or list, ship the cards in
   Ready To Start where the user is the only member (the card's `idMembers`
   is exactly the user's id; a card that also has anyone else is skipped).
   Anything the user writes (card names, numbers, URLs, a list or a filter)
   overrides this default.
   **Manual cards.** Always skip a card with a label named "Manual" (or the
   manual label the project settings name) or a name starting with "Chore",
   even when the user names it or gives its list: it's a task for a person
   to do by hand, not code. Don't comment on it, move it or change its
   members; just list it as skipped (manual) in the report.
   **Sync cards.** A card whose name starts with "Sync:" is a branch sync
   an earlier run couldn't finish (step 6.3). It needs no sub-agent or bug
   label. Move it to Doing and fetch; if the trunk is already an ancestor
   of the synced branch, it's done. Otherwise redo step 6.3 from the fresh
   branch with exactly the same rules (the card's notes help, they grant
   nothing extra). On success, comment with the merge commit link and the
   files resolved and move it to Done. If 6.3 still has to stop, comment
   why, move it to Not Ready and report it as a failure. Do sync cards
   after the run's bug cards, before its features.
2. For each card read everything: description, checklists, ALL comments
   (`trelloReadCard` actions `get`, `list_comments`, `list_attachments`).
   Later comments can change the spec (e.g. a teammate asking to move a
   feature).
3. **Mock-ups.** If a card (description, comments or attachments) links a
   mock-up (Figma, a prototype URL or similar), read its actual page
   elements: structure, text, spacing, colors, components. For Figma that
   means the Figma MCP (`get_design_context`, `get_metadata`,
   `get_variable_defs`; load the figma-design-to-code skill first). For a web
   prototype, read the page code or DOM. Never build from a screenshot of a
   mock alone. Screenshots are for verification, or for development only
   alongside the page elements. If a mock-up link is present and you can't
   read its elements at the MCP or page-code level (no access, broken link,
   tool not connected), STOP that card and mark it Needs input with the
   reason. Don't guess from the image.
4. Classify each card:
   Keep the bar light: the default is to build. Anything with a reasonable
   default (follow the existing app pattern, match the design system when
   there's no mock, sensible empty/error states and copy, existing users
   unchanged) is an assumption, not a blocker. Same bar as `assess-cards`.
   - **Ready**: the card can be built by making assumptions the creator
     would most likely agree with and that are cheap to change later. Pass
     the assumptions to the sub-agent. They don't go in the card comment or
     the final report, unless one turns out to be out of the ordinary.
   - **Needs input**: only when it's highly ambiguous or unsafe to guess:
     the card contradicts itself (or its comments) on what gets built;
     materially different readings where guessing wrong means real rework;
     a business, pricing, policy or legal call only the product owners can
     make; a missing mock the card explicitly relies on, or a linked mock
     whose elements can't be read (step 1.3); credentials or accounts only
     the user can create; research spikes; or a production data change where
     the card is unclear about which rows to change or delete. Do NOT build
     these. Record the specific questions for the final report.
   Quick code checks (grep the relevant component) are fine to confirm scope.
5. Move every Ready card to Doing now.
6. **Resume work a stopped run left behind.** Before building anything,
   check each Ready card for a worktree an earlier run kept on purpose (see
   "Kept for resume" in step 9): `git worktree list --porcelain`, then for
   each worktree read `<worktree>/.ship-cards-resume`. It is resumable only
   if ALL of these hold:
   - the marker names this card (match the card id first, the number
     second: a card moved between boards comes back with a new number);
   - no process is working in it
     (`lsof -d cwd -Fn 2>/dev/null | grep -F "<worktree>"` prints nothing);
   - `git -C <worktree> status --porcelain` shows nothing besides the
     marker, dependencies, the local env file and build artifacts;
   - every commit in `git -C <worktree> log --oneline <base>..HEAD` is for
     this card (`<base>` is `origin/main`, or `origin/<staging>` for a
     feature card with staged releases).
   For a resumable card, skip the build in step 2 and take over that
   worktree and branch as if this run's agent had made them (they are this
   run's from now on, cleanup included). Delete the marker. If the card's
   description, checklists or comments changed after the marker's date, or
   the marker's reason says the code itself was the problem, give a Sonnet
   agent the existing worktree (`Agent`, `model: "sonnet"`, no `isolation`,
   told to work only in `<worktree>`) with the card spec and that change to
   make; otherwise go straight to step 3 and review its diff like any
   agent's work.
   **Interrupted build (no marker).** A headless run can be cut off while
   its build agent is still working, leaving no marker. Treat a
   `.claude/worktrees/agent-*` worktree as this run's to resume when no
   process is in it (the `lsof` check), no file in it (outside
   node_modules and build output) changed in the last 90 minutes
   (`find <worktree> \( -name node_modules -o -name '.next*' \) -prune -o
   -type f -mmin -90 -print` prints nothing; an interactive session's short
   commands don't show up in `lsof`), every commit in
   `<base>..HEAD` is named `Card #<n>: ...`, and each of those cards (plus
   any card its uncommitted files plainly belong to) is in the in-progress
   list with only the default member. Take those cards into this run even
   if they weren't in its list, `git -C <worktree> merge origin/<base>`,
   and give a Sonnet agent the existing worktree (no `isolation`, told to
   work only in `<worktree>`, keep the existing commits and finish the
   cards that aren't committed yet, one commit per card). Then carry on
   from step 3 for all of them. A worktree that fails these checks is
   still another session's (below).
   A worktree or branch with commits for this card but NO
   marker, or one that fails any check above, belongs to another session:
   never touch it, build fresh, and report it under "Out of the ordinary".
   The check is one `git worktree list` per run, so it costs next to nothing
   when there is nothing to resume.

## 2. Implement with Sonnet sub-agents

- Group cards that touch the same files into one agent (separate commits per
  card) to reduce merge conflicts; otherwise one agent per card. Launch them
  in parallel with `Agent` using `model: "sonnet"`, `isolation: "worktree"`,
  `run_in_background: true`.
- Every agent prompt must include: the card number, id and full spec
  (including relevant comments); "read CLAUDE.md and the design system doc
  first"; "read the card's attachments with mcp__trello__download_attachment
  if useful; do NOT write to Trello"; worktree setup from the main checkout
  (e.g. symlink `node_modules` and the local env file, never committed); run
  the typecheck, lint (must exit 0, no new warnings in touched files) and
  unit test commands; no dev server, no build; commit as `Card #<n>: ...`
  with the session's attribution trailer lines; DO NOT push; report root
  cause, files, SHAs, worktree path/branch, judgment calls, the tests added
  (file and test names, or why none), and exact Playwright verification
  steps (URLs, viewport, selectors, test data ids from read-only queries).
- Every agent prompt must also include the **testing rules**:
  - **Dependabot cards** (logged by `triage-cards` step 0) are the one
    exception to the next rule: a version-only update needs no new test,
    since lint, type checks, unit tests, the build and the dev server check
    are the test. Follow the card's "How to apply" section. Code changes
    made for a breaking change still get tests.
  - **Bug cards: at least one regression unit test, always.** It must fail
    on the old code and pass with the fix (check by running it before the
    fix, or by temporarily reverting the fix). If the buggy logic is buried
    in a component or route, pull it out into a small pure function so it
    can be unit tested; don't skip the test because the code is hard to reach.
  - **Feature cards: unit tests where appropriate**, i.e. for new or changed
    logic: parsing, validation, formatting, filtering and sorting, pricing,
    credits and permissions checks, state transitions, data mapping. Skip
    them for pure copy, styling or layout changes.
  - Unit tests go in the project's unit test folder, named
    `<topic>-<card number>`, following the existing files there. Keep them
    fast and offline: no dev server, no network, no database; mock or pass
    in data.
  - **Integration, API or end-to-end tests only when really necessary**:
    for high-risk areas where a unit test can't catch the failure, such as
    auth and role checks, row-level security and cross-user access, payments
    and webhooks, account deletion, or outbound emails. Use the project's
    existing suites, never production. Say in the report why it was needed.
- If the card has a mock-up, pass the link and the rule from step 1.3: the
  agent builds from the mock's page elements (Figma MCP or page code), uses
  screenshots only to check its work, and stops and reports if it can't read
  the elements.
- Tell agents to never write to the production database and never trigger
  real outbound emails, payments or invites to real people during testing.
  Agents may apply migrations to the non-production database and run
  scripts' read-only production dry runs. Production migrations and
  production writes are done by the main session in step 5, never by an
  agent. Any new production script must have a production dry-run mode that
  prints every change it would make and writes nothing, and write only with
  a separate flag (see the production dry run rule at the top).
- New migrations: check the highest migration number on `origin/main` and in
  other open worktrees, so two runs don't create the same number.

## 3. Review each agent's work

When each report arrives:
1. Read the actual diff (`git -C <worktree> diff origin/main..HEAD`), not just
   the report. Check it does what the card asks, follows the design system
   (and the mock's elements, when there is one), has no behavior regressions,
   and doesn't silently drop features (e.g. a removed page that held a
   banner).
   Check the tests too: every bug card (except a version-only Dependabot
   card) has a regression unit test that
   targets the actual root cause (not just a happy path near it), feature
   logic has unit tests, and any integration or end-to-end test is justified
   by real risk. Send missing or weak tests back to the agent.
2. Run `/code-review` (the `code-review` skill) at a moderate level on the
   combined change, or review by hand for small diffs. Send concrete fixes
   back to the same agent with `SendMessage` (it keeps context) instead of
   fixing them yourself.
3. Check data assumptions with read-only queries where it matters (e.g. real
   values containing commas, nulls).

## 4. Integrate and verify

1. Create one local integration worktree from fresh `origin/main`
   (`git worktree add -b <batch-branch> .claude/worktrees/<batch> origin/main`)
   and `git merge --no-ff` each agent branch with a message like
   `Card #<n>: <summary> (merge <branch>)` plus the attribution trailers.
   With staged releases, feature cards get their own integration worktree
   from fresh `origin/<staging>` instead, one merge commit per card; diff
   against `origin/<staging>` there wherever this skill says `origin/main`.
2. Set it up so it builds like the main checkout: dependencies (a real copy
   or fresh install if the bundler rejects a symlinked `node_modules`), the
   local env file, and any untracked local folders lint depends on.
3. Run lint (0 errors), typecheck, unit tests and the production build
   (into a separate output dir if the framework allows, e.g.
   `NEXT_DIST_DIR=.next-verify` for Next.js, so it doesn't clash with a
   running dev server). Afterwards restore any tracked files the build or
   dev server rewrites (`git checkout -- <file>`).
4. Start the dev server in the background on a free port in the agent port
   range from the project settings (check it's free with `lsof -i :<port>`
   first). If another session's server holds a port, don't kill it, pick
   another one. Never use the user's own dev port. Use the chosen port
   everywhere below.
5. Playwright (headless, from the integration worktree so `playwright`
   resolves; put the script in the worktree root as `.verify-tmp.mjs`, run
   it with the local env file loaded, e.g. `node --env-file=.env.local`,
   delete it after):
   - If the bundled browser isn't downloaded, point `chromium.launch` at an
     installed one with `executablePath`.
   - The dev server must use the non-production database. Log in with the
     project's test accounts, reading the password from its env var. Never
     print the password. If the accounts are missing, run the project's test
     database reset first.
   - Mobile: `{ viewport: { width: 375, height: 812 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 }`;
     desktop: `1440x900`.
   - **Always screenshot every changed screen at BOTH sizes** (mobile and
     desktop), even when the card only mentions one. Name them
     `<n>-mobile-<screen>.png` and `<n>-desktop-<screen>.png`. A run without
     both sets isn't verified.
   - Remove dev-only overlays (e.g. the framework's dev badge) before
     clicking or screenshotting near them.
   - Use real clicks (not `.check()` through hidden elements) so clipped or
     covered UI fails the test. Count only visible elements (responsive
     layouts often keep both desktop and mobile markup in the DOM).
   - Capture console errors and note which ones are expected dev-only noise.
   - Save screenshots to the session scratchpad and LOOK at each one before
     using it (a screenshot can show a loading skeleton, a mid-transition tab,
     or the wrong state). Use realistic test images, not flat colors that look
     like placeholders.
   - Pick the test account whose role or plan shows the changed UI. For
     states no account covers, adjust the non-production database freely,
     but never edit production data here.
6. If anything fails, send it back to the owning agent, re-merge, re-verify.
7. **Pre-push review agents.** With the dev server still running, launch the
   adversarial code review, security review and requirements recheck below,
   plus the QA agent only when its condition is met, as Sonnet sub-agents in
   parallel (`Agent`, `model: "sonnet"`, `run_in_background: true`, no
   worktree isolation). Each works read-only against the integration
   worktree: no commits, no pushes, no Trello writes, no production writes.
   Give each the card numbers, the full card specs and comments, any mock-up
   links, the integration worktree path and the diff command
   (`git -C <worktree> diff origin/main...HEAD`). Each returns a findings
   list (severity, file:line or screen, the concrete failure, a suggested
   fix):
   - **Adversarial code review:** try to break the change. Edge cases, nulls
     and empty states, race conditions, stale state after saves, error paths,
     regressions in callers of changed functions, features silently dropped.
   - **Security review:**
     It runs in two parts and reports them separately:
     1. First the built-in `/security-review` (Skill tool, skill
        `security-review`), so it also runs on Sonnet. It reviews the
        pending changes of the repo it runs in, so tell the agent to work
        from the integration worktree and run any git commands the skill
        asks for there, never in the main checkout, and to confirm the
        commit range it reviewed. Tell it to follow every step of the
        skill, including the separate false-positive check per finding,
        even when a finding already looks certain.
     2. Then its own checklist:
     auth and role checks on every new or changed route,
     row-level security and privileged-client use, IDOR (ids scoped to the
     right user or account), input validation, SSRF in server-side fetches,
     XSS and unsafe URLs, secrets in client code or logs, upload type and
     size limits.
   - **QA of the feature (only when needed, the exception not the rule):**
     run it only when a card is UI intensive AND complex enough that the
     step 4.5 screenshots can't cover it, e.g. a new multi-step flow, a form
     with validation and several states, or interactions that span screens
     or roles. Skip it for copy changes, small or isolated UI tweaks, counts
     or labels, and backend or query changes, and say in the final report
     that QA was skipped only if a reviewer would expect it. When it runs:
     use it on `http://localhost:<port>` (the run's dev server) with
     Playwright (same setup as step 4.5, its own `.qa-tmp-<n>.mjs` file,
     deleted after) the way a real user would: happy path, 375px mobile and
     desktop, bad input, empty states, back and refresh, other roles. Report
     what broke, with screenshots in the scratchpad.
   - **Requirements recheck:** go through each card line by line
     (description, checklists, comments, attachments) and compare with the
     built product and this run's screenshots: every requirement met, exact
     copy, and the layout matching the design system. For a mock-up, compare
     against its page elements read through the Figma MCP or page code (step
     1.3), not only its image; if it can't read them, report that as a
     blocker. List anything missing or different.
   Read every finding and drop false positives (note why). Send real ones to
   the owning implementation agent with `SendMessage`, then re-merge and
   re-run steps 4.3 to 4.5 for the affected cards. Re-run a reviewer if its
   area changed materially.
8. Kill the dev server as soon as verification and the review agents are done
   (`kill $(lsof -t -i :<port>)`, only this run's port), and confirm it's
   stopped.

## 5. Production migrations and scripts

Only when the run includes a migration or a production data script (with
staged releases, only for bug cards; a feature card's migrations go to the
staging database only, after a dry run there). This is where the
production dry run rule at the top applies most often. The same steps cover
any other production change a card needs (a SQL write, a hosting or
database setting): verify it 2 to 3 times before it runs, and if it has no
dry run, don't make it:
1. **Order:** if new code reads a new column or table, apply the production
   migration BEFORE pushing the code, or live pages break in between.
2. **Before:** read-only queries on production to confirm the starting state
   (the column doesn't exist yet, the row counts and target rows the script
   expects).
3. **Dry run:** migrations with the project's dry-run command against
   production (e.g. `supabase db push --dry-run` after linking the
   production project); it must list exactly this run's migrations. Make
   sure the migration tool gets the production database credentials, not
   the local env file's (which usually point at a dev or staging database):
   pass the production password through the environment for every
   production push, dry run and real run alike, read from wherever the
   project keeps it and never printed. Scripts
   in their production dry-run mode; the output must match what you expect
   (counts and every proposed change). If anything is unexpected, stop and
   fix it first.
4. **Re-check:** run the dry run again right before applying and confirm
   nothing changed (another session may have written in between). For
   deletes or bulk updates, also spot-check a few target rows with read-only
   queries.
5. **Apply:** the migration command, or the script in its production write
   mode (with approval, see the top).
6. **After:** verify with read-only queries: the column or constraint exists,
   the migration history table has the new versions, and counts changed by
   exactly the expected amount and nothing else. If anything is off, report
   it under "Out of the ordinary" in the final report.

## 6. Push

1. `git fetch origin main`; `git log --oneline HEAD..origin/main` (if origin
   moved, merge it in and re-run lint, typecheck, unit tests and the build);
   `git log --oneline origin/main..HEAD` must show only this run's commits.
   If unpushed commits from another session appear, stop and tell the user.
2. Push it yourself from the integration worktree: `git push origin HEAD:main`
   (no force), quoting the approval (see the top). Don't hand the push to a
   sub-agent: relaying approval to a sub-agent gets flagged as a bypass.
3. If the project has a long-lived branch to keep in sync (e.g. `preview`):
   fast-forward it with `git push origin origin/main:refs/heads/<branch>`
   when `origin/<branch>` is an ancestor of `origin/main`, otherwise merge
   `main` into it in a worktree and push that. Never force-push it.
   Resolve merge conflicts yourself: resolve each hunk so both main's fix
   and the branch's feature survive, run lint, type check, unit tests and
   the build, and push when they pass. Report the conflicted files and a
   one-line resolution each as a warning.
   **Dependency manifest and lockfile too.** In the manifest (e.g.
   `package.json`) keep every dependency either side added, removed or
   changed; when both changed the same package, take the higher version and
   keep the range style. Never hand-merge the lockfile: take the trunk's
   (`git checkout --theirs <lockfile>`, so the trunk's direct and indirect
   versions are kept exactly), run the package manager's install so the
   branch's added packages are filled in, and check its list command (e.g.
   `npm ls <packages>`) shows the trunk's versions and nothing invalid or
   missing. Then verify as usual.
   **Sync cards.** Stop only when a conflicted file is a migration, an env
   file or a CI workflow, or verification still fails after the resolution.
   Then don't log a manual chore: remove the sync worktree and branch and
   log (or reuse an open one) a card named `Sync: Merge main into <branch>
   (<why>)` in Ready To Start, the user as its only member, no manual
   label, saying which files conflicted, what each side changed and what
   failed. The next run picks it up (step 1, "Sync cards").
4. **Feature cards (staged releases)** skip steps 6.1 to 6.3: from the
   feature integration worktree, `git fetch origin <staging>`, merge it in if
   it moved (and re-run lint, typecheck, unit tests and the build), check
   `git log --oneline origin/<staging>..HEAD` shows only this run's commits,
   then `git push origin HEAD:refs/heads/<staging>` (no force). Never push a
   feature card's commits to the trunk.
5. **Confirm the host built every branch you pushed** (only when the project
   settings name a deploy check command): run it in the background for each
   pushed branch. Git hosts occasionally drop push events, and then the
   hosting provider never builds and production silently stays on the old
   code. The command should wait a few minutes for a build of the branch's
   head commit, start the build itself through the provider's API when none
   appears, and wait for it to finish. A self-started build that succeeds is
   a warning line in the report; a failed or unstartable build is a failure
   line with the deploy URL, and production scripts that depend on the new
   code wait until it is live. Only hand the user a manual "redeploy" step
   when the command itself could not start the build.

## 7. Trello updates (after the push)

For each shipped card:
1. **Attach screenshots** with `mcp__trello__attach_file_to_card`,
   `fileUrl: "file:///<absolute path>"`, `cardId` = the short objectId (not
   the ARI), a descriptive `name`, `mimeType: "image/png"`. Do not read
   Trello credentials or inline base64.
2. **Post a short comment** (`trelloWriteCard` `add_comment`, first person),
   in this order:
   - A one-sentence summary of what was fixed or built.
   - All the screenshots, in this same comment: a `**Mobile**` heading with
     the mobile screenshots, then a `**Desktop**` heading with the desktop
     ones. Embed each as
     `![name.png](<attachment url from the upload result>)`, each in its
     own paragraph with a blank line between them. Images on consecutive
     lines render as broken "Unsupported image" links in Trello.
   - Numbered click-path test steps a reviewer can follow in the live app
     (where to go, what to click, what they should see). With staged
     releases, a feature card's steps point at the staging site, followed
     by one line saying it goes live when staging is promoted.
   - Commit links `[sha](https://github.com/<owner>/<repo>/commit/<sha>)`
     for the card's commits and the merge commit.
   - Last, and only if necessary, an **Important:** note for the card's
     reviewers (e.g. something that could not be verified). Leave it out
     otherwise. No root-cause write-ups or judgment-call lists.
   - **Never put tasks for the user in a card comment.** Comments are only
     for the card's reviewers. Anything the user has to do (add an env var,
     run a command, make a decision, check something after a deploy) goes in
     the step 10 to-do list in the Claude session, not on the card. Also
     don't write "I will check X later" promises in comments.
3. **Make the card's reviewer its only member and move it to Done** (one
   step; do both together for each card):
   - The reviewer is the card's original creator:
     `mcp__trello__get_card_history` with filter
     `createCard,copyCard,convertToCardFromCheckItem,emailCard`, take
     `idMemberCreator`. If that's the user, use the fallback reviewer from
     the project settings (or keep the user if there is none). Add the
     reviewer with `mcp__trello__assign_member_to_card` first (skip if
     already a member), then remove every other member (including the user,
     unless they're the reviewer) with `mcp__trello__remove_member_from_card`,
     and confirm the returned member list is exactly the reviewer.
   - In the same step, move the card to Done with `mcp__trello__move_card`
     (with staged releases, a feature card goes to the Done in staging list
     instead, and only after its code is on staging). Only for cards this
     run shipped; cards that weren't built, were pulled
     from the push or aborted stay where they are.

## 8. Clean up

- Remove the integration and agent worktrees (`git worktree remove --force`,
  after checking `git status --porcelain` only shows dependencies, the local
  env file and build artifacts), `git branch -d` the merged branches,
  fast-forward the main checkout (`git merge --ff-only origin/main`). Only
  remove what this run created (worktrees resumed in step 1.6 count as this
  run's), never a worktree kept for resume in step 9. Step 10 confirms it
  all.

## 9. Final report to the user

Keep the terminal report VERY short, scannable in a few seconds. The details
(what changed, test steps, screenshots, commits, prod changes, the push) are
already in the card comments, so don't repeat them here. Exactly these
parts, in this order, one line per item:

1. **Cards:** one line per card, with a link and a one-phrase summary:
   - `✅ [#<n> <title>](<card url>): <short summary>` for a shipped card
     (with staged releases, ending in `(live)` or `(staging)`).
   - `⚠️ [#<n> <title>](<card url>): needs input, <question>` for a card
     that wasn't built.
   - `❌ [#<n> <title>](<card url>): <what stopped it, current state>` for
     a card pulled from the push or aborted.

   **Kept for resume:** when a card stops after its commits exist and the
   work itself is sound (a production migration or script that couldn't
   run, a permission block, a rejected push, a check that needs the user),
   keep its worktree and branch, and write `<worktree>/.ship-cards-resume`
   with: the card id, card number, branch, the newest commit SHA, the date
   and time, and the reason in one line. End its `❌` line with "work kept
   on `<branch>`, the next run resumes it once the card is back in Ready To
   Start". If the work itself is wrong, remove it instead and say so.
2. **Out of the ordinary:** only things the user needs to know that aren't
   routine, each as one `⚠️` line (or `❌` if it stopped the work): partial
   or skipped verification, a production problem, a serious security issue,
   a surprise like another session's push landing mid-run that changed what
   shipped. Usually there are none; then skip this part entirely. Never list
   routine items here (a normal migration, the push range, branch sync, a
   reviewer finding that was fixed).
3. **Repo state:** the single line from step 10.3.
4. **Left for you to do:** the line(s) from step 10.3.

No headings, tables, root-cause write-ups, judgment-call lists or
paragraphs. Example:

```
✅ [#48 Onboarding flow](https://trello.com/c/...): signup, review queue, team invites
✅ [#69 Search filters](https://trello.com/c/...): location and salary filters
⚠️ [#61 Pricing page](https://trello.com/c/...): needs input, annual discount 15% or 20%?
✅ Repo state
⚠️ Run the backfill: npx tsx scripts/backfill-links.mts --prod --apply
```

## 10. Final check (always the last step)

Do this every run, even if earlier steps failed or the run stopped early. Run
the checks, fix what's this run's to fix, then end the session's last message
with the two sections below.

1. **Run the `repo-state` skill** (Skill tool, `repo-state`), passing any
   long-lived branches from the project settings. It checks for uncommitted
   changes, unpushed commits, extra local branches, worktrees besides the
   main checkout, and whether the main checkout is on an up-to-date `main`.
   For every ⚠️ that is this run's (its worktrees, branches, commits): push
   approved work, remove merged worktrees (`git worktree remove --force`) and
   branches (`git branch -d`, never `-D` on unmerged work),
   `git merge --ff-only origin/main` in the main checkout, then run
   `repo-state` again until only other sessions' items are left. Other
   sessions' worktrees, branches and commits are NEVER removed or pushed;
   list them for the user. Worktrees kept for resume (step 9) stay too:
   report each as `⚠️ Kept for resume: #<n> on <branch>`, not as leftover
   work.
2. **Extra checks repo-state doesn't cover:** any long-lived branch is
   synced (`git merge-base --is-ancestor origin/main origin/<branch>`),
   `git ls-remote --heads origin` shows no branch this run created.
   **Stray origin branch** (any other branch besides the long-lived ones and
   bot branches such as Dependabot's): after `git fetch origin --prune`, if
   `git rev-list --count origin/main..origin/<branch>` is `0` it's fully
   merged and can't hold lost work, so delete it yourself
   (`git push origin --delete <branch>`, no approval needed, whoever made
   it), confirm with `git ls-remote --heads origin` and report
   `✅ Deleted merged stray branch <branch>`. Only a branch with commits
   not on `main` becomes a `⚠️` line and a manual chore (name the branch, its
   unmerged commit count and latest commit subject); never delete that one.
   Also check the run's dev server port is free, and no `.verify-tmp.mjs`, `.qa-tmp-*.mjs` or
   separate build output dir is left behind.
3. End the step 9 report with:
   - **Repo state:** a single line `✅ Repo state` when repo-state is
     clean (other than other sessions' items) and the step 10.2 checks pass.
     If one fails, `⚠️ Repo state: <what's left and why>` (or `❌` if the
     run aborted and left things half done).
   - **Left for you to do:** a single line `✅ Nothing for you to do` when
     there is nothing. Otherwise one `⚠️ <action>` line for each action the
     run could not complete without the user's intervention: env vars or
     settings to add in hosting or third-party dashboards, production
     commands the permission system blocked, Needs input questions or
     product decisions that block work, and other sessions' leftover
     worktrees/branches/unpushed commits to decide on. NOT test steps or
     "verify after deploy" checks (those are already in the card comments
     for reviewers), and not optional judgment calls. Often this is just the
     check mark. These go here, never in Trello comments.
4. Then send exactly one mobile notification with `PushNotification` (load it
   with ToolSearch first): a one-line summary like
   "Shipped 4 cards, 1 needs input, 2 to-dos for you". Never send one per card
   or per step.
