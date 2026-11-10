#!/usr/bin/env bash
# Prepare a Claude Code on the web session for the card skills. Does nothing locally unless run with
# --cloud (it otherwise needs CLAUDE_CODE_REMOTE=true). Never prints a secret value.
#
# Reads .claude/cloud-setup.conf from the project root, a bash file setting:
#   KEYS=(NAME ...)          env vars copied into the env file (non-production only)
#   PROD_ONLY=(NAME ...)     vars that must never be in a cloud environment (warned about, never written)
#   DB_URL_VAR=NAME          var holding the database URL
#   NONPROD_MARKER=text      the DB URL must contain this (e.g. the staging project id)
#   PROD_MARKER=text         refuse to write anything if the DB URL contains this
#   ENV_FILE=.env.local      file to write (default .env.local)
#   INSTALL_CMD="npm ci"     run when node_modules is missing (optional)
#   EXTRA_SETUP="..."        any other setup command, e.g. installing CLIs (optional)
set -uo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || [ "${1:-}" = "--cloud" ] || exit 0

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 0
say() { echo "[cloud-setup] $*"; }
CONF=".claude/cloud-setup.conf"
[ -f "$CONF" ] || { say "❌ $CONF not found"; exit 0; }
KEYS=(); PROD_ONLY=(); DB_URL_VAR=""; NONPROD_MARKER=""; PROD_MARKER=""; ENV_FILE=".env.local"; INSTALL_CMD=""; EXTRA_SETUP=""
# shellcheck disable=SC1090
. "$CONF"

for k in "${PROD_ONLY[@]}"; do
  [ -n "${!k:-}" ] && say "⚠️ $k is set in the cloud environment. It is production only; remove it there."
done

url="${!DB_URL_VAR:-}"
if [ -z "$url" ]; then
  say "⚠️ $DB_URL_VAR is not set, so $ENV_FILE was not written. Add the non-production keys to the cloud environment."
elif [ -n "$PROD_MARKER" ] && [[ "$url" == *"$PROD_MARKER"* ]]; then
  say "❌ $DB_URL_VAR points at production. Refusing to write $ENV_FILE."
elif [ -n "$NONPROD_MARKER" ] && [[ "$url" != *"$NONPROD_MARKER"* ]]; then
  say "❌ $DB_URL_VAR is not the non-production database. Refusing to write $ENV_FILE."
else
  tmp="$(mktemp)"
  echo "# Written by cloud-setup.sh from the cloud environment. Non-production only. Do not commit." > "$tmp"
  missing=()
  for k in "${KEYS[@]}"; do
    v="${!k:-}"
    [ -n "$v" ] || { missing+=("$k"); continue; }
    if [[ "$v" == *"'"* || "$v" == *$'\n'* ]]; then say "⚠️ $k has a quote or newline and was skipped"; continue; fi
    v="${v//\$/\\\$}"   # dotenv-expand expands $NAME even in single quotes; \$ keeps it literal
    printf "%s='%s'\n" "$k" "$v" >> "$tmp"
  done
  mv "$tmp" "$ENV_FILE" && chmod 600 "$ENV_FILE"
  say "✅ $ENV_FILE written. Not set: ${missing[*]:-none}"
fi

if [ -n "$INSTALL_CMD" ] && [ ! -d node_modules ]; then
  bash -c "$INSTALL_CMD" >/tmp/cloud-setup-install.log 2>&1 && say "✅ dependencies installed" || say "❌ install failed, see /tmp/cloud-setup-install.log"
fi
[ -n "$EXTRA_SETUP" ] && { bash -c "$EXTRA_SETUP" >/tmp/cloud-setup-extra.log 2>&1 && say "✅ extra setup done" || say "⚠️ extra setup failed, see /tmp/cloud-setup-extra.log"; }
exit 0
