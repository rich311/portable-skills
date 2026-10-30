#!/bin/bash
# Scheduled, unattended /triage-cards run that emails its report.
# Started by launchd (see triage-hourly.plist) or cron. Each run:
#   1. skips outside the allowed hours, or if a previous run is still going;
#   2. asks a cheap Haiku session whether any Ready To Start card has the user as its only member;
#   3. if so, runs "/triage-cards unattended" and emails the report that follows its last SUBJECT: line.
#
# Settings come from an env file (default ~/.config/triage-cards/<name>.env, see triage.env.example):
#   PROJECT_DIR          the repo's main checkout (required)
#   TRELLO_READY_LIST    Ready To Start list id (required)
#   TRELLO_MEMBER_ID     the user's Trello member id (required)
#   REPORT_TO            where the report goes (required to email)
#   SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASSWORD SMTP_FROM   mail server login
#   START_HOUR END_HOUR  run only from START_HOUR to before END_HOUR (default 6 and 22)
#   TRELLO_GATE_TOOL     MCP tool that lists a list's cards (default mcp__trello__get_cards_by_list_id)
#
# Usage: triage-hourly.sh [env file]

ENV_FILE="${1:-$HOME/.config/triage-cards/default.env}"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$SELF_DIR/$(basename "$0")"

# Everything runs inside main(), so bash reads the whole file before running any of it. If this
# script lives in the project, the pull below can rewrite it mid-run; without main(), bash would keep
# reading the new file at the old byte offset and run a mix of old and new code.
main() {
set -a
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
set +a
: "${START_HOUR:=6}" "${END_HOUR:=22}" "${TRELLO_GATE_TOOL:=mcp__trello__get_cards_by_list_id}"

NAME="$(basename "$ENV_FILE" .env)"
LOG_DIR="$HOME/Library/Logs/triage-cards-$NAME"
[ -d "$HOME/Library" ] || LOG_DIR="$HOME/.local/state/triage-cards-$NAME"
LOCK="$LOG_DIR/run.lock"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y-%m-%d_%H%M)"
LOG="$LOG_DIR/$STAMP.log"
exec >>"$LOG" 2>&1
echo "== $(date) triage-hourly start ($ENV_FILE)${TRIAGE_RESTARTED:+, restarted on the updated script}"

for v in PROJECT_DIR TRELLO_READY_LIST TRELLO_MEMBER_ID; do
  [ -n "${!v}" ] || { echo "$v is not set in $ENV_FILE"; exit 1; }
done

HOUR=$((10#$(date +%H)))
if [ "$HOUR" -lt "$START_HOUR" ] || [ "$HOUR" -ge "$END_HOUR" ]; then
  echo "outside $START_HOUR:00 to $END_HOUR:00, skipping"
  exit 0
fi

cd "$PROJECT_DIR" || exit 1

# Keep the checkout's skills current, but only fast-forward a clean trunk. If that changed this
# script, start again on the new version (once), before taking the lock.
if [ -z "$TRIAGE_RESTARTED" ]; then
  BEFORE="$(shasum "$SELF" 2>/dev/null)"
  TRUNK="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
  TRUNK="${TRUNK:-main}"
  if [ "$(git branch --show-current)" = "$TRUNK" ] && [ -z "$(git status --porcelain --untracked-files=no)" ]; then
    git pull --ff-only -q origin "$TRUNK" || echo "git pull failed, using the checkout as is"
  else
    echo "checkout not clean or not on $TRUNK, not pulling"
  fi
  if [ "$(shasum "$SELF" 2>/dev/null)" != "$BEFORE" ]; then
    echo "the pull updated this script, restarting on the new version"
    exec env TRIAGE_RESTARTED=1 /bin/bash "$SELF" "$ENV_FILE"
  fi
fi

if ! mkdir "$LOCK" 2>/dev/null; then
  OLD_PID="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "previous run (pid $OLD_PID) still going, skipping"
    exit 0
  fi
  echo "removing stale lock"
  rm -rf "$LOCK" && mkdir "$LOCK" || exit 1
fi
echo $$ >"$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

GATE_PROMPT="Use $TRELLO_GATE_TOOL with listId $TRELLO_READY_LIST. Count the open cards whose idMembers is exactly [\"$TRELLO_MEMBER_ID\"] (that member and nobody else). Reply with one line only: COUNT=<number>. If the Trello call fails, reply COUNT=ERROR."
GATE="$(claude -p "$GATE_PROMPT" --model haiku --permission-mode dontAsk \
  --allowedTools "$TRELLO_GATE_TOOL" --output-format text 2>&1)"
echo "gate: $GATE"
COUNT="$(printf '%s' "$GATE" | grep -oE 'COUNT=[0-9A-Z]+' | tail -1 | cut -d= -f2)"

if [ "$COUNT" = "0" ]; then
  echo "no cards, done"
  exit 0
fi
if [ -z "$COUNT" ] || [ "$COUNT" = "ERROR" ]; then
  echo "gate could not count cards; running triage anyway so the skill reports the problem"
fi

REPORT="$LOG_DIR/$STAMP-report.txt"
claude -p "/triage-cards unattended" --permission-mode auto --output-format text >"$REPORT" 2>&1
STATUS=$?
echo "triage-cards exit $STATUS"
cat "$REPORT"

# Headless runs also print progress messages from earlier turns, so email only what follows the
# last SUBJECT: line, and use that line as the subject.
EMAIL_BODY="$LOG_DIR/$STAMP-email.txt"
SUBJECT_LINE="$(grep -n '^SUBJECT: ' "$REPORT" | tail -1)"
if [ -n "$SUBJECT_LINE" ]; then
  SUBJECT="${SUBJECT_LINE#*:SUBJECT: }"
  tail -n +$((${SUBJECT_LINE%%:*} + 1)) "$REPORT" | sed '/./,$!d' >"$EMAIL_BODY"
else
  SUBJECT="Triage cards: ❌ the run ended without a report"
  { echo "❌ The run ended without its report. Full output below, and the log is in $LOG"; echo; cat "$REPORT"; } >"$EMAIL_BODY"
fi
[ "$STATUS" -ne 0 ] && SUBJECT="$SUBJECT (run failed, exit $STATUS)"
if [ -n "$REPORT_TO" ]; then
  python3 "$SELF_DIR/send-report.py" "$SUBJECT" "$EMAIL_BODY" || echo "email failed"
else
  echo "REPORT_TO is not set, not emailing"
fi

# Keep two weeks of logs.
find "$LOG_DIR" -type f \( -name '*.log' -o -name '*-report.txt' -o -name '*-email.txt' \) -mtime +14 -delete
echo "== $(date) done"
}

main "$@"
exit $?
