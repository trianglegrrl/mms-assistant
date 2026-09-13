#!/usr/bin/env bash
# Usage: mms-practice-delete.sh --student <name> --date YYYY-MM-DD [--minutes N] [--notes-match "text"] [--identical]
# Deletes ONE practice row matching the date (and optional duration and notes substring). Refuses if several
# match, unless --identical is given: then the rows are treated as interchangeable duplicates and one is removed.
source "$(dirname "$0")/lib.sh"
STUDENT=""; DATE=""; MATCH=""; DUR=""; IDENTICAL=0
while [[ $# -gt 0 ]]; do case "$1" in
  --student) need_value "$@"; STUDENT="$2"; shift 2;; --date) need_value "$@"; DATE="$2"; shift 2;; --notes-match) need_value "$@"; MATCH="$2"; shift 2;;
  --minutes) need_value "$@"; [[ "$2" =~ ^[0-9]+$ ]] || die "--minutes must be a positive integer"; m=$((10#$2)); DUR=$(printf '%d:%02d' $((m/60)) $((m%60))); shift 2;;
  --identical) IDENTICAL=1; shift;;
  *) die "Unknown arg $1";; esac; done
[[ -n "$STUDENT" && -n "$DATE" ]] || die "--student and --date are required"
DESC="date $DATE${DUR:+, duration $DUR}${MATCH:+, notes containing \"$MATCH\"}"

mms_open "$MMS_BASE/practice-log" "Practice log for"
LABEL="$(mms_select_student "$STUDENT")"
N="$(mms_find_row_paged "$DATE" "$DUR" "$MATCH")"
[[ "$N" != "0" ]] || die "No matching row ($DESC)"
if [[ $IDENTICAL -eq 0 ]]; then [[ "$N" == "1" ]] || die "Expected exactly one matching row, found $N ($DESC). Narrow it, or pass --identical if they are duplicates."; fi
MMS_DATE="$DATE" MMS_DUR="$DUR" MMS_MATCH="$MATCH" python3 - <<'PY' | mms_eval >/dev/null
import os, json
print("""
(() => {
  const [d, dur, m] = %s;
  const row = Array.from(document.querySelectorAll('tr')).find(r => { const td = Array.from(r.querySelectorAll('td')).map(t => t.innerText.trim()); return td[0] === d && (!dur || td[2] === dur) && (!m || (td[4]||'').includes(m)); });
  row.scrollIntoView({block:'center'}); Array.from(row.querySelectorAll('td')).pop().querySelector('button').click(); return 'menu-open';
})()
""" % json.dumps([os.environ["MMS_DATE"], os.environ["MMS_DUR"], os.environ["MMS_MATCH"]]))
PY
ab wait 600 >/dev/null
ab find role menuitem click --name "Delete" >/dev/null
ab wait 700 >/dev/null
ab find role button click --name "Delete" >/dev/null   # confirmation dialog
ab wait 2000 >/dev/null
REMAINING="$(mms_count_rows_here "$DATE" "$DUR" "$MATCH")"
[[ "$REMAINING" == "$((N-1))" ]] || die "Delete was submitted but $REMAINING matching rows remain (expected $((N-1))). Check the page."
echo "Deleted practice row for $LABEL ($DESC); $REMAINING matching left"
