#!/usr/bin/env bash
# Usage: mms-practice-bulk.sh --student <name> < plan.tsv
# Each stdin line: YYYY-MM-DD<TAB>minutes<TAB>notes (notes optional). Blank lines and # comments ignored.
# Opens the practice log once, then adds every row, verifying each one. Dates that already have
# a row in the visible table are skipped and reported. Exit code is non-zero if any row failed.
source "$(dirname "$0")/lib.sh"
STUDENT=""
while [[ $# -gt 0 ]]; do case "$1" in --student) need_value "$@"; STUDENT="$2"; shift 2;; *) die "Unknown arg $1";; esac; done
[[ -n "$STUDENT" ]] || die "--student is required"

PLAN=$(grep -v '^\s*#' | grep -v '^\s*$' || true)
[[ -n "$PLAN" ]] || die "No plan rows on stdin"
while IFS=$'\t' read -r d m _; do
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "Bad date in plan: '$d'"
  [[ "$m" =~ ^[0-9]+$ && $((10#$m)) -gt 0 ]] || die "Bad minutes in plan for $d: '$m'"
done <<< "$PLAN"

mms_open "$MMS_BASE/practice-log" "Practice log for"
LABEL="$(mms_select_student "$STUDENT")"
echo "Bulk add for $LABEL: $(echo "$PLAN" | wc -l | tr -d ' ') rows" >&2

existing_dates() { mms_eval <<'JS'
(() => JSON.stringify(Array.from(document.querySelectorAll('tr')).filter(r => r.querySelector('a.mat-mdc-menu-trigger')).map(r => r.querySelector('td').innerText.trim())))()
JS
}
row_exists() {  # date minutes-as-H:MM
  MMS_D="$1" MMS_DUR="$2" python3 -c 'import os,json;print(json.dumps([os.environ["MMS_D"],os.environ["MMS_DUR"]]))' | {
    read -r pair; printf '(() => { const [d,dur] = %s; return String(Array.from(document.querySelectorAll("tr")).some(r => { const td = Array.from(r.querySelectorAll("td")).map(t => t.innerText.trim()); return td[0]===d && td[2]===dur; })); })()' "$pair" | mms_eval; }
}

added=0; skipped=0; failed=0
EXISTING="$(existing_dates)"
while IFS=$'\t' read -r d m notes; do
  m=$((10#$m)); dur=$(printf '%d:%02d' $((m/60)) $((m%60)))
  if echo "$EXISTING" | grep -q "\"$d\""; then echo "SKIP  $d (already has a row)"; skipped=$((skipped+1)); continue; fi
  ab find role button click --name "Add Time" >/dev/null
  ab wait 600 >/dev/null
  ab find role menuitem click --name "Add Manually" >/dev/null
  ab wait --text "Practice Session Details" --timeout 10000 >/dev/null
  ab find first ".cdk-overlay-pane input" fill "$d" >/dev/null
  ab wait 800 >/dev/null
  ok=0; for attempt in 1 2 3; do ab fill ".cdk-overlay-pane input.mat-mdc-input-element" "$m" >/dev/null 2>&1 && { ok=1; break; }; ab wait 1000 >/dev/null; done
  if [[ $ok -eq 0 ]]; then echo "FAIL  $d (duration field not found)"; failed=$((failed+1)); ab find role button click --name "Cancel" >/dev/null 2>&1 || true; continue; fi
  [[ -n "${notes:-}" ]] && ab fill ".cdk-overlay-pane textarea" "$notes" >/dev/null
  ab find role button click --name "Save" >/dev/null
  ab wait 2000 >/dev/null
  if [[ "$(row_exists "$d" "$dur")" =~ ^[Tt]rue$ ]]; then echo "ADDED $d $dur"; added=$((added+1)); EXISTING="$EXISTING $d";
  else echo "FAIL  $d $dur (row not found after save)"; failed=$((failed+1)); fi
done <<< "$PLAN"
echo "Done for $LABEL: added=$added skipped=$skipped failed=$failed" >&2
[[ $failed -eq 0 ]]
