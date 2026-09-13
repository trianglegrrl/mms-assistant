---
name: mymusicstaff
description: Use when the user asks about MyMusicStaff (MMS, mymusicstaff.com student portal) - upcoming music lessons or appointments, attendance notes or what the teacher said to practice, logging or recording practice time for a student, or logging into the MMS student portal.
---

# MyMusicStaff student portal

## Overview

Run the bundled scripts; do not drive `agent-browser` by hand for these tasks.
The scripts hold a persistent, already-authenticated browser session (agent-browser
session name `mms`) and encode selectors that took real debugging to find. Credentials
live in `~/.config/mymusicstaff/credentials.env` and must never be printed, echoed,
or pasted into chat.

Scripts live in `scripts/` next to this file. Run them with an absolute path, for
example `<this skill dir>/scripts/mms-lessons.sh`. If the credentials file is missing,
run `scripts/setup.sh` (interactive; it prompts for the password without echo).

## Quick reference

| Task | Command |
|------|---------|
| Upcoming lessons (all students, next 2 weeks) | `mms-lessons.sh` |
| Lessons for one student, longer window | `mms-lessons.sh --student sam --weeks 4` |
| Latest teacher notes / what to practice | `mms-notes.sh --student sam --limit 3` |
| Notes over a longer period | `mms-notes.sh --student sam --range "Last 6 Months" --limit 10` |
| See logged practice | `mms-practice-list.sh --student sam` |
| Record practice | `mms-practice-add.sh --student sam --minutes 30 --date 2026-09-06 --notes "scales"` |
| Remove a wrong entry | `mms-practice-delete.sh --student sam --date 2026-09-06 --notes-match "scales"` |
| Change an entry's minutes or notes | `mms-practice-edit.sh --student sam --date 2026-09-06 --notes-match "scales" --minutes 40 --append-notes "studio 3"` |
| Backfill many days at once | `mms-practice-bulk.sh --student sam < plan.tsv` (lines: `date<TAB>minutes<TAB>notes`) |
| Interactive re-login (visible browser) | `mms-login.sh` |

`--student` is a case-insensitive substring of the name in the portal's dropdown
(shown as "Last, First"), so a first name is enough. If it matches no one or more than
one, the script exits with the list of options; pick from that list and re-run. Aliases
such as `me` can be defined in `~/.config/mymusicstaff/config.env` as
`MMS_STUDENT_ME="Last, First"`. When the user says "me" or "my lesson" and no alias
exists, ask which name in the dropdown is theirs, then suggest adding the alias.
`--date` defaults to today. Add `--json` to lessons/notes/list for structured output.
Ranges for notes: "Last 3 Months" (default), "Last 6 Months", "Last Year",
"Entire History", "Next 3 Months".

## Login and the persistent session

Every script opens the page and, only if the session has expired, logs in with the
credentials file. Three outcomes need you to act:

| Script output | What it means | What to do |
|---------------|---------------|------------|
| `OTP_REQUIRED` (exit 2) | Site emailed a 6-digit code to the account | Fetch the code from Gmail (below), then re-run the same command with `MMS_OTP=<code>` prefixed |
| `LOGIN_NEEDS_HUMAN` (exit 3) | reCAPTCHA is blocking automated login | Run `mms-login.sh`, tell the user a browser window opened for them to click Log In, solve the captcha, and enter the emailed code |
| `Login did not complete` | Submission was ignored | Run `mms-login.sh` as above; do not retry the automated login repeatedly (it escalates captcha) |

After any successful login the session is saved automatically; later runs do not
prompt again.

### Fetching the verification code from Gmail

The code arrives in the user's personal Gmail, which the Gmail connector can read.
Search with the Gmail tool:

```
from:support@mymusicstaff.com subject:"Verification Code" newer_than:1h
```

The 6-digit code is in the message snippet ("Your My Music Staff Verification Code
NNNNNN"). Take the newest message only; each code expires 15 minutes after it was sent
and every login attempt sends a new one. Then re-run the original command, for example:

```
MMS_OTP=123456 <skill dir>/scripts/mms-notes.sh --student sam
```

Two failure cases, both resolved by asking the user for the code from their inbox:

- Gmail returns nothing for that search: the connector is on a different account.
- The Gmail tool call is denied by a permission prompt: do not retry or rephrase it.

Do not run the login more than twice in a row, because repeated attempts turn on the
reCAPTCHA (`LOGIN_NEEDS_HUMAN`).

## Reading results

- `mms-lessons.sh` prints `(no events between ...)` when the window is genuinely empty.
  If that seems wrong, re-run once with `--weeks 8`; if notes/practice scripts work but
  lessons stay empty, report it as a script problem rather than improvising in the browser.
- Notes output is one block per lesson: date, event, attendance status, teacher, then the
  teacher's notes verbatim. Summarize the practice instructions for the user; do not
  paraphrase repertoire names. If the newest note is thin (a bare list of names or
  links), include the previous lesson's note too.

## Practice-logging rules

- Confirm student, minutes, and date with the user before running `mms-practice-add.sh`
  unless they gave all three. It writes to the real account.
- The script verifies the new row exists and fails loudly if it does not; trust its exit code.
- **Dates before the student's start date are refused silently by the portal**: the modal swaps the
  date for today, and before this was caught a "failed" add left a stray row dated today. Add and bulk
  now read the date back before Save and stop with `DATE_REJECTED` (nothing saved). Do not retry those
  dates; the teacher has to move the start date. If any add ever reports "row not found after save",
  list today's rows and look for a stray before doing anything else.
- Fix mistakes with `mms-practice-delete.sh`, which refuses unless exactly one row matches. Narrow with
  `--minutes N` and `--notes-match`; for true duplicates (same date, length, and notes) pass
  `--identical` to remove one at a time. Confirm with the user before deleting.
- For backfills ("catch up", "every day between X and Y"), generate a TSV plan with a small
  Python snippet, show the user the row count and total minutes, then run
  `mms-practice-bulk.sh`. It opens the page once, skips dates that already have a row,
  verifies each save, and prints ADDED / SKIP / FAIL per date. Runs take about 8 seconds
  per row, so run it in the background for more than ~20 rows.
- The practice table shows 25 rows per page. To verify a backfill, use
  `mms-practice-list.sh --all --json`, which pages through the whole table.

## Common mistakes

| Mistake | Why it fails | Instead |
|---------|--------------|---------|
| Opening the portal with plain `agent-browser open` | Uses a different session, lands on the login page, triggers the emailed code | Use the scripts (they pass `--session mms --session-name mms`) |
| `agent-browser snapshot` on the login form after filling | Snapshot prints the filled email address in plaintext | Never snapshot the login page; the scripts never do |
| `click` on the Log In / Continue buttons | ASP.NET WebForms submit buttons ignore ref and CSS clicks; nothing happens, no error | Scripts use a DOM `.click()` via `eval` |
| JS `.click()` on the student dropdown | Angular `mat-select` opens from its `.mat-mdc-select-trigger`, not the host element | `mms_select_student` in `lib.sh` handles it |
| Clicking a table row's menu without scrolling | Off-screen rows do not receive clicks | Scripts call `scrollIntoView` first |
| Taking the first menu-trigger button in a row | On rows with long notes that button is the notes cell's "Show More" toggle | Scripts use the button in the last cell |
| Waiting for `networkidle` after navigation | The SPA renders after network idle | Scripts wait for page text ("Practice log for", "Attendance for", "Schedule") |

## Concurrency

Every script takes a lock on the one browser session and waits (up to 10 minutes)
if another script holds it, so parallel subagents are safe but effectively serial.
Do not run two MMS scripts in parallel expecting speed; batch with the bulk script instead.

## When the scripts are not enough

For anything outside the tasks above (invoices, repertoire, booking, messages), load
`agent-browser skills get core` and drive the same session with
`agent-browser --session mms --session-name mms ...` so you inherit the login.
Source `scripts/lib.sh` to reuse `ab`, `mms_open`, and `mms_select_student`.
