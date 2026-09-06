#!/usr/bin/env bash
# Usage: mms-notes.sh --student <name> [--range "Last 3 Months"|"Last 6 Months"|"Last Year"|"Entire History"|"Next 3 Months"] [--limit N] [--json]
# Prints attendance + teacher notes for each lesson (opens each row's Attendance Details popup).
source "$(dirname "$0")/lib.sh"
STUDENT=""; RANGE=""; LIMIT=5; JSON=0
while [[ $# -gt 0 ]]; do case "$1" in
  --student) need_value "$@"; STUDENT="$2"; shift 2;; --range) need_value "$@"; RANGE="$2"; shift 2;; --limit) need_value "$@"; LIMIT="$2"; shift 2;; --json) JSON=1; shift;;
  *) die "Unknown arg $1";; esac; done
[[ -n "$STUDENT" ]] || die "--student is required"

mms_open "$MMS_BASE/attendance-notes" "Attendance for"
LABEL="$(mms_student_label "$STUDENT")"
mms_select_student "$LABEL"
if [[ -n "$RANGE" ]]; then
  ab find role combobox click --name "last" >/dev/null 2>&1 || ab find role combobox click --name "Last" >/dev/null 2>&1 || true
  ab wait 500 >/dev/null
  ab find role option click --name "$RANGE" >/dev/null || die "Range option '$RANGE' not found"
  ab wait 2000 >/dev/null
fi

RESULT=$(MMS_LIMIT="$LIMIT" python3 - <<'PY' | mms_eval
import os
print("""
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const rows = Array.from(document.querySelectorAll('tr')).filter(r => r.querySelector('a.mat-mdc-menu-trigger'));
  const out = [];
  for (const r of rows.slice(0, %d)) {
    const link = r.querySelector('a.mat-mdc-menu-trigger');
    link.scrollIntoView({block:'center'}); link.click();
    await sleep(900);
    const pane = document.querySelector('.cdk-overlay-pane');
    const lines = pane ? pane.innerText.split('\\n').map(s => s.trim()).filter(Boolean) : [];
    const grab = (h, next) => { const i = lines.indexOf(h); if (i < 0) return ''; const j = next ? lines.indexOf(next) : lines.length; return lines.slice(i+1, j > i ? j : lines.length).join('\\n'); };
    out.push({
      event: (r.querySelector('td')||{}).innerText?.split('\\n')[0]?.trim() || '',
      attendance: grab('Attendance', 'Date & Time').trim(),
      datetime: grab('Date & Time', 'Teacher').trim(),
      teacher: grab('Teacher', 'Student Notes').trim(),
      notes: grab('Student Notes', 'Linked Resources').trim(),
    });
    const closeBtn = pane && Array.from(pane.querySelectorAll('button')).find(b => /^Close$/.test(b.innerText.trim()));
    if (closeBtn) closeBtn.click();
    await sleep(500);
  }
  return JSON.stringify(out);
})()
""" % int(os.environ["MMS_LIMIT"]))
PY
)
if [[ $JSON -eq 1 ]]; then echo "$RESULT"; else
  echo "Attendance & notes for $LABEL${RANGE:+ ($RANGE)}:"
  echo "$RESULT" | jq -r '.[] | "\n=== \(.datetime) — \(.event) — \(.attendance) — \(.teacher) ===\n\(if .notes == "" then "(no notes)" else .notes end)"'
fi
