#!/usr/bin/env bash
# Shared helpers for the mymusicstaff skill. Source this file; do not run it.
# Credentials are read from $MMS_CREDS and are never echoed.
set -euo pipefail

MMS_CREDS="${MMS_CREDS:-$HOME/.config/mymusicstaff/credentials.env}"
MMS_SESSION="${MMS_SESSION:-mms}"
MMS_BASE="https://app.mymusicstaff.com/Student/v3/en"
MMS_LOGIN_MARKER="#MainContent_contentBody_textboxEmail"
MMS_OTP_MARKER="#MainContent_contentBody_bOtpContinue"

ab() { agent-browser --session "$MMS_SESSION" --session-name "$MMS_SESSION" "$@"; }

die() { echo "ERROR: $*" >&2; exit 1; }

# For "--flag value" parsing: ensure a value follows the flag.
need_value() { [[ $# -ge 2 && -n "${2:-}" ]] || die "Flag $1 requires a value"; }

# Set an input's value WITHOUT putting the secret on agent-browser's argv (visible in ps).
# The value travels through an env var into python, then over stdin into the browser.
mms_fill_secret() {
  local selector="$1"
  MMS_SEL="$selector" MMS_VAL="$2" python3 - <<'PY2' | ab eval --stdin >/dev/null
import os, json
print("(() => { const el = document.querySelector(%s); if (!el) return 'missing'; el.focus(); el.value = %s; el.dispatchEvent(new Event('input', {bubbles:true})); el.dispatchEvent(new Event('change', {bubbles:true})); return 'ok'; })()" % (json.dumps(os.environ['MMS_SEL']), json.dumps(os.environ['MMS_VAL'])))
PY2
}

# Read credentials into this shell only (not exported to every child process).
mms_load_creds() {
  [[ -r "$MMS_CREDS" ]] || die "Credentials file not readable: $MMS_CREDS"
  # shellcheck disable=SC1090
  source "$MMS_CREDS"
  [[ -n "${MMS_USERNAME:-}" && -n "${MMS_PASSWORD:-}" ]] || die "MMS_USERNAME / MMS_PASSWORD missing in $MMS_CREDS"
}

# Unwrap agent-browser eval output (a JSON string literal) into raw text.
mms_eval() { ab eval --stdin | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()))'; }

mms_count() { ab get count "$1" 2>/dev/null | tr -dc '0-9' || echo 0; }

MMS_CONFIG="${MMS_CONFIG:-$HOME/.config/mymusicstaff/config.env}"
# Optional aliases: MMS_STUDENT_<ALIAS>="Exact, Label" in config.env (alias is upper-cased).
# shellcheck disable=SC1090
[[ -r "$MMS_CONFIG" ]] && source "$MMS_CONFIG"

# Resolve --student to a dropdown label and select it, in one open-match-click pass so the
# dropdown is never left open (an open mat-select backdrop swallows later clicks).
# Alias MMS_STUDENT_<QUERY> wins; otherwise case-insensitive substring of the option text.
# Prints the selected label.
mms_select_student() {
  local query="$1" alias_var target=""
  alias_var="MMS_STUDENT_$(echo "$query" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9\n' '_')"
  [[ -n "${!alias_var:-}" ]] && target="${!alias_var}"
  MMS_Q="$query" MMS_T="$target" python3 - <<'PY2' | ab eval --stdin | MMS_Q="$query" python3 -c '
import json, os, sys
r = json.loads(json.loads(sys.stdin.read()))
if r["status"] == "ok": print(r["label"]); sys.exit(0)
if r["status"] == "no-combo": print("ERROR: No student dropdown on this page", file=sys.stderr); sys.exit(1)
msg = "No student matches" if r["status"] == "none" else "Ambiguous student"
print("ERROR: %s %r. Options: %s" % (msg, os.environ["MMS_Q"], ", ".join(r["hits"] or r["options"])), file=sys.stderr); sys.exit(1)'
import os, json
print("""(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const q = %s.toLowerCase(), target = %s;
  const combo = document.querySelector('mat-select');
  if (!combo) return JSON.stringify({status:'no-combo'});
  const trig = combo.querySelector('.mat-mdc-select-trigger') || combo;
  trig.click(); await sleep(700);
  let opts = Array.from(document.querySelectorAll('[role=option]'));
  if (!opts.length) { combo.focus(); combo.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true})); await sleep(700); opts = Array.from(document.querySelectorAll('[role=option]')); }
  const names = opts.map(o => o.textContent.trim());
  const hits = target ? names.filter(n => n === target) : names.filter(n => n.toLowerCase().includes(q));
  const close = async () => { const bd = document.querySelector('.cdk-overlay-backdrop'); if (bd) bd.click(); await sleep(400); };
  if (hits.length !== 1) { await close(); return JSON.stringify({status: hits.length ? 'ambiguous' : 'none', hits, options: names}); }
  opts[names.indexOf(hits[0])].click(); await sleep(2000);
  for (let i = 0; i < 10 && document.querySelector('[role=option]'); i++) { await close(); }
  return JSON.stringify({status:'ok', label: hits[0]});
})()""" % (json.dumps(os.environ["MMS_Q"]), json.dumps(os.environ["MMS_T"])))
PY2
}

# First name from a "Last, First" label (used to filter calendar events).
mms_first_name() { local l="$1"; [[ "$l" == *,* ]] && echo "${l#*, }" || echo "$l"; }

mms_login() {
  mms_load_creds
  echo "Session expired; logging in..." >&2
  mms_fill_secret "$MMS_LOGIN_MARKER" "$MMS_USERNAME"
  mms_fill_secret "#MainContent_contentBody_textboxPassword" "$MMS_PASSWORD"
  if [[ "$(mms_count 'iframe[src*=recaptcha]')" -gt 0 && "$(mms_count '.g-recaptcha, #recaptcha, [data-sitekey]')" -gt 0 ]]; then
    mms_headed_login_required "The login page is showing a reCAPTCHA challenge"
  fi
  # WebForms submit buttons ignore ref/CSS clicks here. Trigger the postback directly.
  cat <<'JS' | ab eval --stdin >/dev/null
(() => { if (typeof window.__doPostBack === 'function') { window.__doPostBack('ctl00$ctl00$MainContent$contentBody$buttonLogin', ''); return 'postback'; }
  document.querySelector('#MainContent_contentBody_buttonLogin').click(); return 'click'; })()
JS
  mms_wait_login_progress
  if ab get text body 2>/dev/null | grep -qi "invalid captcha"; then
    mms_headed_login_required "MyMusicStaff rejected the automated login with 'Invalid captcha'"
  fi
  if [[ "$(mms_count "$MMS_OTP_MARKER")" -gt 0 ]]; then mms_submit_otp; fi
  [[ "$(ab get url)" == *Default.aspx* ]] && die "Login did not complete (still on login page). Run scripts/mms-login.sh to log in interactively."
  mms_persist_state
}

mms_wait_login_progress() {
  local i
  for i in $(seq 1 15); do
    sleep 1
    [[ "$(mms_count "$MMS_OTP_MARKER")" -gt 0 ]] && return 0
    [[ "$(ab get url)" != *Default.aspx* ]] && return 0
    ab get text body 2>/dev/null | grep -qi "invalid captcha" && return 0
  done
  return 0   # timeout is reported by the caller, not here
}

mms_persist_state() {
  local state="$HOME/.config/mymusicstaff/auth-state.json"
  ( umask 077; ab state save "$state" >/dev/null ) || die "Logged in, but saving session state to $state failed"
  chmod 600 "$state" "$HOME/.agent-browser/sessions/${MMS_SESSION}-${MMS_SESSION}.json" 2>/dev/null || true
  echo "Login OK; session persisted for future runs." >&2
}

mms_headed_login_required() {
  echo "LOGIN_NEEDS_HUMAN: $1. Automated login cannot proceed." >&2
  echo "Run: $(dirname "${BASH_SOURCE[0]}")/mms-login.sh   (opens a visible browser; complete captcha + emailed code there)" >&2
  exit 3
}

# The site emails a 6-digit code on new devices. Pass it via MMS_OTP=123456.
mms_submit_otp() {
  if [[ -z "${MMS_OTP:-}" ]]; then
    echo "OTP_REQUIRED: MyMusicStaff emailed a 6-digit verification code to the account's address." >&2
    echo "Re-run the same command with MMS_OTP=<code> in the environment, or run scripts/mms-login.sh." >&2
    exit 2
  fi
  mms_fill_secret "input[type=text]:not([type=hidden])" "$MMS_OTP"
  printf 'document.querySelector("%s").click(); "ok"' "$MMS_OTP_MARKER" | ab eval --stdin >/dev/null
  local i
  for i in $(seq 1 15); do sleep 1; [[ "$(ab get url)" != *Default.aspx* ]] && return 0; done
  die "Verification code was not accepted (still on login page)."
}

# Open a portal URL, logging in first if the session has expired.
mms_open() {
  local url="$1" marker="${2:-}"
  ab open "$url" >/dev/null
  ab wait --load networkidle >/dev/null 2>&1 || true
  if [[ "$(ab get url)" == *Default.aspx* ]]; then
    mms_login
    ab open "$url" >/dev/null
    ab wait --load networkidle >/dev/null 2>&1 || true
  fi
  if [[ -n "$marker" ]]; then ab wait --text "$marker" --timeout 25000 >/dev/null; fi
  ab wait 1500 >/dev/null
}

