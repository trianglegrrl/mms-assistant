#!/usr/bin/env bash
# Usage: mms-practice-delete.sh --student <name> --date YYYY-MM-DD [--notes-match "text"]
# Deletes ONE practice row matching the date (and optional notes substring). Refuses if several match.
source "$(dirname "$0")/lib.sh"
STUDENT=""; DATE=""; MATCH=""
while [[ $# -gt 0 ]]; do case "$1" in
  --student) need_value "$@"; STUDENT="$2"; shift 2;; --date) need_value "$@"; DATE="$2"; shift 2;; --notes-match) need_value "$@"; MATCH="$2"; shift 2;;
  *) die "Unknown arg $1";; esac; done
[[ -n "$STUDENT" && -n "$DATE" ]] || die "--student and --date are required"

mms_open "$MMS_BASE/practice-log" "Practice log for"
LABEL="$(mms_student_label "$STUDENT")"
mms_select_student "$LABEL"
STATUS=$(MMS_DATE="$DATE" MMS_MATCH="$MATCH" python3 - <<'PY' | mms_eval
import os, json
print("""
(() => {
  const [d, m] = %s;
  const rows = Array.from(document.querySelectorAll('tr')).filter(r => { const td = Array.from(r.querySelectorAll('td')).map(t => t.innerText.trim()); return td[0] === d && (!m || (td[4]||'').includes(m)); });
  if (rows.length !== 1) return 'match-count:' + rows.length;
  const b = rows[0].querySelector('button.mat-mdc-menu-trigger'); rows[0].scrollIntoView({block:'center'}); b.click();
  return 'menu-open';
})()
""" % json.dumps([os.environ["MMS_DATE"], os.environ["MMS_MATCH"]]))
PY
)
[[ "$STATUS" == "menu-open" ]] || die "Expected exactly one matching row, got: $STATUS"
ab wait 600 >/dev/null
ab find role menuitem click --name "Delete" >/dev/null
ab wait 700 >/dev/null
ab find role button click --name "Delete" >/dev/null   # confirmation dialog
ab wait 2000 >/dev/null
REMAINING=$(MMS_DATE="$DATE" MMS_MATCH="$MATCH" python3 - <<'PY' | mms_eval
import os, json
print("(() => { const [d, m] = %s; return String(Array.from(document.querySelectorAll('tr')).filter(r => { const td = Array.from(r.querySelectorAll('td')).map(t => t.innerText.trim()); return td[0] === d && (!m || (td[4]||'').includes(m)); }).length); })()" % json.dumps([os.environ["MMS_DATE"], os.environ["MMS_MATCH"]]))
PY
)
[[ "$REMAINING" == "0" ]] || die "Delete was submitted but a matching row is still present. Check the page."
echo "Deleted practice row for $LABEL on $DATE${MATCH:+ (notes containing \"$MATCH\")}"
