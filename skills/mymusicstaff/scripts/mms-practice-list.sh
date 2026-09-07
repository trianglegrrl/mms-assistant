#!/usr/bin/env bash
# Usage: mms-practice-list.sh --student <name> [--limit N] [--all] [--json]
# --all pages through the whole table (default view shows 25 rows) and ignores --limit.
# Lists logged practice sessions (most recent first) and the weekly summary line.
source "$(dirname "$0")/lib.sh"
STUDENT=""; LIMIT=10; JSON=0; ALL=0
while [[ $# -gt 0 ]]; do case "$1" in
  --student) need_value "$@"; STUDENT="$2"; shift 2;; --limit) need_value "$@"; LIMIT="$2"; shift 2;; --json) JSON=1; shift;; --all) ALL=1; shift;;
  *) die "Unknown arg $1";; esac; done
[[ -n "$STUDENT" ]] || die "--student is required"

mms_open "$MMS_BASE/practice-log" "Practice log for"
LABEL="$(mms_select_student "$STUDENT")"
extract_rows() { mms_eval <<'JS'
(() => {
  const summary = (Array.from(document.querySelectorAll('h4')).find(h => /logged/.test(h.innerText))||{}).innerText || '';
  const rows = Array.from(document.querySelectorAll('tr')).filter(r => r.querySelector('a.mat-mdc-menu-trigger'));
  const sessions = rows.map(r => { const td = Array.from(r.querySelectorAll('td')).map(t => t.innerText.trim());
    const notes = (td[4]||'').replace(/\s*Show More\s*$/, ' …');   // portal truncates long notes in the table
    return {date: td[0], day: td[1], duration: td[2], attachments: td[3], notes}; });
  return JSON.stringify({summary, sessions});
})()
JS
}
# Click the pager's "next" control if it is enabled; print "more" or "end".
next_page() { mms_eval <<'JS'
(() => {
  const btn = Array.from(document.querySelectorAll('button')).find(b => /next/i.test(b.getAttribute('aria-label')||'') || /next/i.test(b.title||''));
  if (!btn || btn.disabled || btn.getAttribute('aria-disabled') === 'true') return 'end';
  btn.click(); return 'more';
})()
JS
}
RESULT="$(extract_rows)"
if [[ $ALL -eq 1 ]]; then
  PAGES="$RESULT"
  for _ in $(seq 1 40); do
    [[ "$(next_page)" == "more" ]] || break
    ab wait 1500 >/dev/null
    PAGES="$(printf '%s\n%s' "$PAGES" "$(extract_rows)")"
  done
  RESULT="$(echo "$PAGES" | jq -s '{summary: .[0].summary, sessions: (map(.sessions) | add | unique_by(.date + .duration + .notes) | sort_by(.date) | reverse)}')"
  LIMIT=100000
fi
if [[ $JSON -eq 1 ]]; then echo "$RESULT" | jq ".sessions |= .[:$LIMIT]"; else
  echo "$LABEL: $(echo "$RESULT" | jq -r .summary)"
  echo "$RESULT" | jq -r ".sessions[:$LIMIT][] | \"\(.date) \(.day[0:3])  \(.duration)  \(if .notes == \"-\" then \"\" else (.notes | gsub(\"\\n+\"; \" / \")) end)\""
fi
