#!/usr/bin/env bash
# Shared helpers for the mymusicstaff skill. Source this file; do not run it.
# Credentials are read from $MMS_CREDS and are never echoed.
set -euo pipefail

MMS_CREDS="${MMS_CREDS:-$HOME/.config/mymusicstaff/credentials.env}"
MMS_SESSION="${MMS_SESSION:-mms}"
MMS_BASE="https://app.mymusicstaff.com/Student/v3/en"
MMS_LOGIN_MARKER="#MainContent_contentBody_textboxEmail"
MMS_OTP_MARKER="#MainContent_contentBody_bOtpContinue"

# Newer agent-browser versions log "[agent-browser] restore: loaded" on every call; drop that noise.
# stderr goes through a temp file, not a process substitution: the browser daemon is spawned by
# the first call and inherits its fds, and a daemon holding a pipe open hangs the caller forever.
ab() {
  local err rc; err="$(mktemp)"
  agent-browser --session "$MMS_SESSION" --session-name "$MMS_SESSION" "$@" 2>"$err"; rc=$?
  grep -v '^\[agent-browser\] ' "$err" >&2 || true; rm -f "$err"; return $rc
}
# Make sure the daemon exists before any call whose output we capture, so it inherits only /dev/null.
mms_daemon_up() { ab get url >/dev/null 2>&1 </dev/null || true; }

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

# One browser session means one operation at a time. mkdir is atomic on every
# filesystem, so a lock directory is the portable lock (macOS ships no flock).
MMS_LOCK_DIR="${MMS_LOCK_DIR:-$HOME/.config/mymusicstaff/session.lock}"
MMS_LOCK_WAIT="${MMS_LOCK_WAIT:-600}"   # seconds to wait for another operation to finish
mms_lock() {
  local waited=0 owner
  while ! mkdir "$MMS_LOCK_DIR" 2>/dev/null; do
    owner="$(cat "$MMS_LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
      echo "Removing stale MMS lock left by pid $owner" >&2; rm -rf "$MMS_LOCK_DIR"; continue
    fi
    [[ $waited -eq 0 ]] && echo "Another MyMusicStaff operation (pid ${owner:-?}) is running; waiting..." >&2
    (( waited >= MMS_LOCK_WAIT )) && die "Gave up waiting ${MMS_LOCK_WAIT}s for the MMS session lock ($MMS_LOCK_DIR)"
    sleep 2; waited=$((waited+2))
  done
  echo $$ > "$MMS_LOCK_DIR/pid"
  trap 'rm -rf "$MMS_LOCK_DIR"' EXIT
}

# Open a portal URL, logging in first if the session has expired. Takes the session lock.
mms_open() {
  mms_lock
  mms_daemon_up
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


# Practice/attendance tables show 25 rows per page. These helpers search across pages.
# mms_table_next_page prints "more" after clicking the pager's next button, or "end".
mms_table_next_page() { mms_eval <<'JS'
(() => {
  const btn = Array.from(document.querySelectorAll('button')).find(b => /next/i.test(b.getAttribute('aria-label')||'') || /next/i.test(b.title||''));
  if (!btn || btn.disabled || btn.getAttribute('aria-disabled') === 'true') return 'end';
  btn.click(); return 'more';
})()
JS
}
# mms_table_first_page returns to page 1: a "first" button if the pager has one, otherwise
# "previous" until it is disabled. No-op when there is no pager.
mms_table_first_page() {
  local i r
  for i in $(seq 1 60); do
    r="$(mms_eval <<'JS'
(() => {
  const find = re => Array.from(document.querySelectorAll('button')).find(b => re.test(b.getAttribute('aria-label')||'') || re.test(b.title||''));
  const first = find(/first/i); if (first) { if (first.disabled || first.getAttribute('aria-disabled') === 'true') return 'at-first'; first.click(); return 'clicked-first'; }
  const prev = find(/prev/i); if (!prev || prev.disabled || prev.getAttribute('aria-disabled') === 'true') return 'at-first'; prev.click(); return 'clicked-prev';
})()
JS
)"
    [[ "$r" == "at-first" ]] && return 0
    ab wait 900 >/dev/null
    [[ "$r" == "clicked-first" ]] && return 0
  done
}
# Print the Date field's current value in the open practice modal (YYYY-MM-DD). The portal silently
# swaps a date before the student's start date for today, so read this back before clicking Save.
mms_modal_date_value() { mms_eval <<'JS'
(() => { const i = document.querySelector('.cdk-overlay-pane input'); return i ? i.value : ''; })()
JS
}
# Count practice rows matching date [+ duration H:MM] [+ notes substring] on the current page.
mms_count_rows_here() {
  MMS_D="$1" MMS_DUR="${2:-}" MMS_M="${3:-}" python3 - <<'PY2' | mms_eval
import os, json
print("(() => { const [d,dur,m] = %s; return String(Array.from(document.querySelectorAll('tr')).filter(r => { const td = Array.from(r.querySelectorAll('td')).map(t => t.innerText.trim()); return td[0]===d && (!dur || td[2]===dur) && (!m || (td[4]||'').includes(m)); }).length); })()" % json.dumps([os.environ["MMS_D"], os.environ["MMS_DUR"], os.environ["MMS_M"]]))
PY2
}
# Page forward until a matching row is on screen. Prints the count found on that page (0 if none).
# Leaves the table on the page where the row was found (callers that continue must not assume page 1).
mms_find_row_paged() {
  local n i
  mms_table_first_page
  n="$(mms_count_rows_here "$@")"
  for i in $(seq 1 40); do
    [[ "$n" != "0" ]] && break
    [[ "$(mms_table_next_page)" == "more" ]] || break
    ab wait 1200 >/dev/null
    n="$(mms_count_rows_here "$@")"
  done
  echo "$n"
}
