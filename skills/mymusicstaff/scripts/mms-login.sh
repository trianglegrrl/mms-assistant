#!/usr/bin/env bash
# Usage: mms-login.sh [--timeout-seconds N]
# Interactive login: opens a VISIBLE browser with email/password prefilled from the credentials file.
# The human clicks Log In, solves any captcha, and enters the emailed 6-digit code.
# The script waits, then persists the session so all other scripts run unattended afterwards.
source "$(dirname "$0")/lib.sh"
TIMEOUT=300
while [[ $# -gt 0 ]]; do case "$1" in --timeout-seconds) need_value "$@"; TIMEOUT="$2"; shift 2;; *) die "Unknown arg $1";; esac; done
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "--timeout-seconds must be an integer"
mms_load_creds

ab close >/dev/null 2>&1 || true
ab --headed open "$MMS_BASE/practice-log" >/dev/null
ab wait --load networkidle >/dev/null 2>&1 || true
if [[ "$(ab get url)" != *Default.aspx* ]]; then
  echo "Already logged in; nothing to do." >&2; mms_persist_state; exit 0
fi
mms_fill_secret "$MMS_LOGIN_MARKER" "$MMS_USERNAME"
mms_fill_secret "#MainContent_contentBody_textboxPassword" "$MMS_PASSWORD"
echo "A browser window is open with your email and password prefilled." >&2
echo "Please click 'Log In', complete any captcha, and enter the 6-digit code from your email." >&2
echo "Waiting up to ${TIMEOUT}s..." >&2
for _ in $(seq 1 "$((TIMEOUT / 3))"); do
  sleep 3
  if [[ "$(ab get url 2>/dev/null)" != *Default.aspx* ]]; then mms_persist_state; echo "Interactive login complete." ; exit 0; fi
done
die "Timed out waiting for interactive login."
