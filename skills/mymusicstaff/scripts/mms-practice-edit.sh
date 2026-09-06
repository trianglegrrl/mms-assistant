#!/usr/bin/env bash
# Usage: mms-practice-edit.sh --student <name> --date YYYY-MM-DD [--notes-match TEXT] [--minutes N] [--notes TEXT | --prepend-notes TEXT | --append-notes TEXT]
# Edits ONE existing practice row (refuses if several match). Only the fields you pass are changed.
source "$(dirname "$0")/lib.sh"
STUDENT=""; DATE=""; MATCH=""; MINUTES=""; NOTES=""; PRE=""; APP=""
while [[ $# -gt 0 ]]; do case "$1" in
  --student) need_value "$@"; STUDENT="$2"; shift 2;; --date) need_value "$@"; DATE="$2"; shift 2;; --notes-match) need_value "$@"; MATCH="$2"; shift 2;;
  --minutes) need_value "$@"; MINUTES="$2"; shift 2;; --notes) need_value "$@"; NOTES="$2"; shift 2;; --prepend-notes) need_value "$@"; PRE="$2"; shift 2;; --append-notes) need_value "$@"; APP="$2"; shift 2;;
  *) die "Unknown arg $1";; esac; done
[[ -n "$STUDENT" && -n "$DATE" ]] || die "--student and --date are required"
[[ -n "$MINUTES$NOTES$PRE$APP" ]] || die "Nothing to change: pass --minutes and/or a notes option"
[[ -z "$MINUTES" || "$MINUTES" =~ ^[0-9]+$ ]] || die "--minutes must be an integer"

mms_open "$MMS_BASE/practice-log" "Practice log for"
LABEL="$(mms_select_student "$STUDENT")"
N="$(mms_find_row_paged "$DATE" "" "$MATCH")"
[[ "$N" == "1" ]] || die "Expected exactly one matching row, found $N (date $DATE${MATCH:+, notes containing \"$MATCH\"})"
OLD_NOTES="$(MMS_DATE="$DATE" MMS_MATCH="$MATCH" python3 - <<'PY' | mms_eval
import os, json
print("""(() => { const [d, m] = %s;
  const row = Array.from(document.querySelectorAll('tr')).find(r => { const td = Array.from(r.querySelectorAll('td')).map(t => t.innerText.trim()); return td[0] === d && (!m || (td[4]||'').includes(m)); });
  row.scrollIntoView({block:'center'}); Array.from(row.querySelectorAll('td')).pop().querySelector('button').click(); return (row.querySelectorAll('td')[4]||{}).innerText || ''; })()""" % json.dumps([os.environ["MMS_DATE"], os.environ["MMS_MATCH"]]))
PY
)"
ab wait 600 >/dev/null
ab find role menuitem click --name "Edit" >/dev/null
ab wait --text "Practice Session Details" --timeout 10000 >/dev/null
ab wait 800 >/dev/null
# Read the full current notes from the form (the table cell may be truncated with "Show More").
CUR_NOTES="$(mms_eval <<'JS'
(() => { const t = document.querySelector('.cdk-overlay-pane textarea'); return t ? t.value : ''; })()
JS
)"
if [[ -n "$MINUTES" ]]; then
  ok=0; for attempt in 1 2 3; do ab fill ".cdk-overlay-pane input.mat-mdc-input-element" "$MINUTES" >/dev/null 2>&1 && { ok=1; break; }; ab wait 1000 >/dev/null; done
  [[ $ok -eq 1 ]] || { ab find role button click --name "Cancel" >/dev/null 2>&1; die "Could not find the Duration field"; }
fi
NEW_NOTES="$CUR_NOTES"
[[ -n "$NOTES" ]] && NEW_NOTES="$NOTES"
[[ -n "$PRE" ]] && NEW_NOTES="$PRE"$'\n\n'"$NEW_NOTES"
[[ -n "$APP" ]] && NEW_NOTES="$NEW_NOTES"$'\n\n'"$APP"
if [[ "$NEW_NOTES" != "$CUR_NOTES" ]]; then mms_fill_secret ".cdk-overlay-pane textarea" "$NEW_NOTES"; fi
ab find role button click --name "Save" >/dev/null
ab wait 2000 >/dev/null
[[ "$(mms_count "'.cdk-overlay-pane textarea'")" == "0" ]] || die "The edit dialog did not close; the save may have failed"
echo "Edited $LABEL on $DATE${MINUTES:+: duration -> $MINUTES min}${NOTES:+: notes replaced}${PRE:+: notes prepended}${APP:+: notes appended}"
