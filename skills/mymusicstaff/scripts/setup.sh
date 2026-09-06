#!/usr/bin/env bash
# One-time setup: checks dependencies and writes ~/.config/mymusicstaff/credentials.env
# without ever echoing the password. Safe to re-run.
set -euo pipefail
CFG_DIR="$HOME/.config/mymusicstaff"; CREDS="$CFG_DIR/credentials.env"
missing=0
for dep in agent-browser jq python3; do
  command -v "$dep" >/dev/null || { echo "Missing dependency: $dep" >&2; missing=1; }
done
[[ $missing -eq 0 ]] || { echo "Install the missing tools (agent-browser: npm i -g agent-browser && agent-browser install)" >&2; exit 1; }
mkdir -p "$CFG_DIR"; chmod 700 "$CFG_DIR"
if [[ -f "$CREDS" ]]; then
  echo "Credentials file already exists at $CREDS; leaving it alone."
else
  read -r -p "MyMusicStaff login email: " user
  read -r -s -p "MyMusicStaff password: " pass; echo
  ( umask 077; printf 'MMS_USERNAME=%q\nMMS_PASSWORD=%q\n' "$user" "$pass" > "$CREDS" )
  echo "Wrote $CREDS (mode 600)."
fi
if [[ ! -f "$CFG_DIR/config.env" ]]; then
  ( umask 077; printf '%s\n' '# Optional --student aliases. Alias is upper-cased; value is the exact dropdown label.' '# MMS_STUDENT_ME="Last, First"' > "$CFG_DIR/config.env" )
  echo "Wrote $CFG_DIR/config.env (edit to add student aliases)."
fi
echo "Setup complete. First run will log in and may need the emailed verification code."
