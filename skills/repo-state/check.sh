#!/usr/bin/env bash
# Read-only repo state check. Prints one ✅ or ⚠️ line per check, with
# details indented below each ⚠️. Exit code 0 when everything is clean, 1
# otherwise. Never changes anything.
#
# Settings (env vars, all optional):
#   MAIN_BRANCH    the trunk branch (default: main)
#   KEEP_BRANCHES  space-separated long-lived local branches that are allowed
#                  to exist, each compared against origin/<same name>
#                  (default: just MAIN_BRANCH, e.g. "main preview")
#   EXTRA_IGNORE   extra regex alternatives for untracked/changed paths that
#                  aren't real work, e.g. 'dist/?|\.cache/?'
set -u

MAIN_BRANCH=${MAIN_BRANCH:-main}
KEEP_BRANCHES=${KEEP_BRANCHES:-$MAIN_BRANCH}

ROOT=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')
[ -n "$ROOT" ] || { echo "❌ Not inside a git repo"; exit 2; }
cd "$ROOT" || exit 2

# shellcheck disable=SC2086
git fetch -q origin $KEEP_BRANCHES 2>/dev/null || echo "⚠️ Could not fetch origin, results may be stale"

# Local files and build artifacts the dev tooling leaves behind; not real work.
IGNORE_PATHS='node_modules|\.env\.local|\.next-verify/?|\.next-agent/?|\.verify-tmp\.mjs|\.qa-tmp-.*\.mjs'
[ -n "${EXTRA_IGNORE:-}" ] && IGNORE_PATHS="$IGNORE_PATHS|$EXTRA_IGNORE"
IGNORE="^.. ($IGNORE_PATHS)$"
KEEP_RE="^($(echo "$KEEP_BRANCHES" | tr ' ' '|'))$"
dirty=0

is_keep() { echo "$1" | grep -Eq "$KEEP_RE"; }

# Worktrees (the first entry is always the main checkout).
worktrees=$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')
extra_wt=$(echo "$worktrees" | tail -n +2)

# 1. Uncommitted changes, in the main checkout and every worktree.
out=""
while IFS= read -r wt; do
  [ -d "$wt" ] || continue
  changes=$(git -C "$wt" status --porcelain 2>/dev/null | grep -Ev "$IGNORE")
  [ -n "$changes" ] && out+="   $wt"$'\n'"$(echo "$changes" | head -10 | sed 's/^/     /')"$'\n'
done <<< "$worktrees"
if [ -n "$out" ]; then echo "⚠️ Uncommitted changes:"; printf "%s" "$out"; dirty=1
else echo "✅ No uncommitted changes"; fi

# 2. Unpushed commits: on any local branch or detached worktree HEAD, not on origin.
# Long-lived branches compare against their own origin branch, the rest
# against origin/MAIN_BRANCH.
out=""
for b in $(git for-each-ref --format='%(refname:short)' refs/heads); do
  base=origin/$MAIN_BRANCH
  is_keep "$b" && base=origin/$b
  n=$(git rev-list --count "$base..$b" 2>/dev/null || echo "?")
  [ "$n" != 0 ] && out+="   $b: $n commit(s) not on $base"$'\n'
done
while IFS= read -r wt; do
  [ -d "$wt" ] || continue
  if ! git -C "$wt" symbolic-ref -q HEAD >/dev/null; then
    n=$(git -C "$wt" rev-list --count "origin/$MAIN_BRANCH..HEAD" 2>/dev/null || echo "?")
    [ "$n" != 0 ] && out+="   $wt (detached): $n commit(s) not on origin/$MAIN_BRANCH"$'\n'
  fi
done <<< "$worktrees"
if [ -n "$out" ]; then echo "⚠️ Unpushed commits:"; printf "%s" "$out"; dirty=1
else echo "✅ No unpushed commits"; fi

# 3. Local branches besides the long-lived ones.
extra_br=$(git for-each-ref --format='%(refname:short)' refs/heads | grep -Ev "$KEEP_RE")
if [ -n "$extra_br" ]; then echo "⚠️ Extra local branches:"; echo "$extra_br" | sed 's/^/   /'; dirty=1
else echo "✅ No local branches besides $KEEP_BRANCHES"; fi

# 4. Worktrees besides the main checkout.
if [ -n "$extra_wt" ]; then
  echo "⚠️ Extra worktrees:"
  git worktree list | tail -n +2 | sed 's/^/   /'
  dirty=1
else echo "✅ No worktrees besides the main checkout"; fi

# 5. Main checkout on the trunk and level with origin.
cur=$(git branch --show-current)
behind=$(git rev-list --count "HEAD..origin/$MAIN_BRANCH" 2>/dev/null || echo "?")
if [ "$cur" != "$MAIN_BRANCH" ]; then echo "⚠️ Main checkout is on '$cur', not $MAIN_BRANCH"; dirty=1
elif [ "$behind" != 0 ]; then echo "⚠️ Main checkout is $behind commit(s) behind origin/$MAIN_BRANCH (git merge --ff-only origin/$MAIN_BRANCH)"; dirty=1
else echo "✅ Main checkout on $MAIN_BRANCH, up to date"; fi

exit $dirty
