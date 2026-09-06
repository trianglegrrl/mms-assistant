#!/usr/bin/env bash
# Usage: mms-practice-add.sh --student <name> --minutes N [--date YYYY-MM-DD] [--notes "text"]
# Adds a manual practice session (Add Time -> Add Manually) and verifies the new row.
source "$(dirname "$0")/lib.sh"
STUDENT=""; MINUTES=""; DATE="$(date +%F)"; NOTES=""
while [[ $# -gt 0 ]]; do case "$1" in
  --student) need_value "$@"; STUDENT="$2"; shift 2;; --minutes) need_value "$@"; MINUTES="$2"; shift 2;; --date) need_value "$@"; DATE="$2"; shift 2;; --notes) need_value "$@"; NOTES="$2"; shift 2;;
  *) die "Unknown arg $1";; esac; done
[[ -n "$STUDENT" ]] || die "--student is required (maya or alaina)"
[[ "$MINUTES" =~ ^[0-9]+$ ]] || die "--minutes must be a positive integer"
MINUTES=$((10#$MINUTES)); [[ $MINUTES -gt 0 ]] || die "--minutes must be a positive integer"
[[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "--date must be YYYY-MM-DD"
EXPECT_DUR=$(printf '%d:%02d' $((MINUTES/60)) $((MINUTES%60)))

mms_open "$MMS_BASE/practice-log" "Practice log for"
LABEL="$(mms_select_student "$STUDENT")"
ab find role button click --name "Add Time" >/dev/null
ab wait 600 >/dev/null
ab find role menuitem click --name "Add Manually" >/dev/null
ab wait --text "Practice Session Details" --timeout 10000 >/dev/null
ab find first ".cdk-overlay-pane input" fill "$DATE" >/dev/null   # first input in the modal is the Date field
# Filling the date re-renders the modal; the Duration input can briefly disappear.
ab wait 800 >/dev/null
for attempt in 1 2 3; do
  if ab fill ".cdk-overlay-pane input.mat-mdc-input-element" "$MINUTES" >/dev/null 2>&1; then break; fi
  [[ $attempt -lt 3 ]] || die "Could not find the Duration field in the practice modal"
  ab wait 1000 >/dev/null
done
[[ -n "$NOTES" ]] && ab fill ".cdk-overlay-pane textarea" "$NOTES" >/dev/null
ab find role button click --name "Save" >/dev/null
ab wait 2500 >/dev/null

FOUND=$(MMS_DATE="$DATE" MMS_DUR="$EXPECT_DUR" python3 -c 'import os,json;print(json.dumps([os.environ["MMS_DATE"],os.environ["MMS_DUR"]]))' | {
  read -r pair; printf '(() => { const [d,dur] = %s; return String(Array.from(document.querySelectorAll("tr")).some(r => { const td = Array.from(r.querySelectorAll("td")).map(t => t.innerText.trim()); return td[0]===d && td[2]===dur; })); })()' "$pair" | mms_eval; })
[[ "$FOUND" == "True" || "$FOUND" == "true" ]] || die "Saved, but could not find a row for $DATE / $EXPECT_DUR in the table. Check the page."
echo "Added practice for $LABEL: $DATE, $MINUTES min${NOTES:+, notes: \"$NOTES\"}"
