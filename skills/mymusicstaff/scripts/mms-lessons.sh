#!/usr/bin/env bash
# Usage: mms-lessons.sh [--student <name>|all] [--weeks N] [--json]
# Lists upcoming lessons/events from the Calendar (Schedule tab), today onward.
source "$(dirname "$0")/lib.sh"
STUDENT=all; WEEKS=2; JSON=0
while [[ $# -gt 0 ]]; do case "$1" in
  --student) need_value "$@"; STUDENT="$2"; shift 2;; --weeks) need_value "$@"; WEEKS="$2"; shift 2;; --json) JSON=1; shift;;
  *) die "Unknown arg $1";; esac; done

extract() { mms_eval <<'JS'
(() => {
  const out = [];
  for (const c of document.querySelectorAll('.mbsc-calendar-day')) {
    const dt = c.querySelector('.mbsc-calendar-day-text');
    const label = dt ? (dt.getAttribute('aria-label')||'').replace(/^Today, /,'') : '';
    if (!label) continue;
    const d = new Date(label.replace(/^\w+, /,''));
    const iso = isNaN(d) ? label : d.toISOString().slice(0,10);
    for (const l of c.querySelectorAll('.mbsc-calendar-label, .mbsc-calendar-text')) {
      const t = (l.getAttribute('aria-label')||l.textContent).replace(/\s+/g,' ').trim();
      if (t) out.push({date: iso, day: label.split(',')[0], event: t});
    }
  }
  return JSON.stringify(out);
})()
JS
}

mms_open "$MMS_BASE/calendar#Schedule" "Schedule"
# Re-opening the same URL does not reload the SPA, so the calendar may still be paged
# forward from a previous run. "Today" resets the view to the current month.
ab find role button click --name "Today" >/dev/null
ab wait 1500 >/dev/null
ALL="$(extract)"
# Month view: page forward enough months to cover the requested weeks.
[[ "$WEEKS" =~ ^[0-9]+$ ]] || die "--weeks must be a positive integer"
WEEKS=$((10#$WEEKS)); [[ $WEEKS -gt 0 ]] || die "--weeks must be a positive integer"
MONTHS=$(( (WEEKS + 3) / 4 ))
for _ in $(seq 1 "$MONTHS"); do
  ab find role button click --name "Next page" >/dev/null
  ab wait 1500 >/dev/null
  ALL="$(printf '%s\n%s' "$ALL" "$(extract)")"
done

TODAY=$(date +%F); END=$(date -v+"${WEEKS}"w +%F 2>/dev/null || date -d "+${WEEKS} weeks" +%F)
FILTER='.'
if [[ "$(echo "$STUDENT" | tr '[:upper:]' '[:lower:]')" != "all" ]]; then
  ALIAS_VAR="MMS_STUDENT_$(echo "$STUDENT" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9\n' '_')"
  NAME="$(mms_first_name "${!ALIAS_VAR:-$STUDENT}")"
  FILTER="select(.event | ascii_downcase | contains(\"$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | sed 's/"//g')\"))"
fi
RESULT=$(echo "$ALL" | jq -s --arg t "$TODAY" --arg e "$END" \
  "(add // []) | unique_by(.date + .event) | map(select(.date >= \$t and .date <= \$e)) | map($FILTER) | sort_by(.date)")
if [[ $JSON -eq 1 ]]; then echo "$RESULT"; else
  echo "$RESULT" | jq -r '.[] | "\(.date) \(.day[0:3])  \(.event)"'
  [[ "$(echo "$RESULT" | jq length)" -eq 0 ]] && echo "(no events between $TODAY and $END)" || true
fi
