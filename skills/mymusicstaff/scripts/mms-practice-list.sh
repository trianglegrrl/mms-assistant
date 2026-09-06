#!/usr/bin/env bash
# Usage: mms-practice-list.sh --student <name> [--limit N] [--json]
# Lists logged practice sessions (most recent first) and the weekly summary line.
source "$(dirname "$0")/lib.sh"
STUDENT=""; LIMIT=10; JSON=0
while [[ $# -gt 0 ]]; do case "$1" in
  --student) need_value "$@"; STUDENT="$2"; shift 2;; --limit) need_value "$@"; LIMIT="$2"; shift 2;; --json) JSON=1; shift;;
  *) die "Unknown arg $1";; esac; done
[[ -n "$STUDENT" ]] || die "--student is required"

mms_open "$MMS_BASE/practice-log" "Practice log for"
LABEL="$(mms_select_student "$STUDENT")"
RESULT=$(mms_eval <<'JS'
(() => {
  const summary = (Array.from(document.querySelectorAll('h4')).find(h => /logged/.test(h.innerText))||{}).innerText || '';
  const rows = Array.from(document.querySelectorAll('tr')).filter(r => r.querySelector('a.mat-mdc-menu-trigger'));
  const sessions = rows.map(r => { const td = Array.from(r.querySelectorAll('td')).map(t => t.innerText.trim());
    return {date: td[0], day: td[1], duration: td[2], attachments: td[3], notes: td[4]}; });
  return JSON.stringify({summary, sessions});
})()
JS
)
if [[ $JSON -eq 1 ]]; then echo "$RESULT" | jq ".sessions |= .[:$LIMIT]"; else
  echo "$LABEL: $(echo "$RESULT" | jq -r .summary)"
  echo "$RESULT" | jq -r ".sessions[:$LIMIT][] | \"\(.date) \(.day[0:3])  \(.duration)  \(if .notes == \"-\" then \"\" else .notes end)\""
fi
