# mms-assistant

A Claude Code skill for the [MyMusicStaff](https://www.mymusicstaff.com) student portal.
Ask Claude for upcoming lessons, what the teacher said to practice, or to log practice
time, and it drives the portal for you through [agent-browser](https://github.com/vercel-labs/agent-browser)
with a persistent, already-logged-in session.

Works for any student or parent account, including accounts with several students.

## What it can do

| Ask for | Script behind it |
|---------|------------------|
| Upcoming lessons and events | `mms-lessons.sh [--student NAME] [--weeks N]` |
| Attendance and teacher notes | `mms-notes.sh --student NAME [--range "Last 6 Months"] [--limit N]` |
| Logged practice sessions | `mms-practice-list.sh --student NAME` |
| Record a practice session | `mms-practice-add.sh --student NAME --minutes N [--date YYYY-MM-DD] [--notes TEXT]` |
| Remove a practice session | `mms-practice-delete.sh --student NAME --date YYYY-MM-DD [--notes-match TEXT]` |
| Log in interactively | `mms-login.sh` |

`--student` accepts any case-insensitive substring of the name shown in the portal's
dropdown (for example a first name), or an alias from `~/.config/mymusicstaff/config.env`.

## Install

Requirements: [Claude Code](https://claude.com/claude-code), `agent-browser` 0.26+, `jq`, `python3`.

```bash
npm i -g agent-browser && agent-browser install
```

Then install the skill in one of these ways:

- **As a Claude Code plugin:** `claude plugin add trianglegrrl/mms-assistant` (or add this
  repo as a marketplace and install `mms-assistant`).
- **With the skills CLI:** `npx skills add trianglegrrl/mms-assistant`
- **By hand:** copy `skills/mymusicstaff` into `~/.claude/skills/` (all projects) or
  `<project>/.claude/skills/` (one project).

Finally run the setup script once. It checks dependencies and writes your credentials to
`~/.config/mymusicstaff/credentials.env` with owner-only permissions:

```bash
skills/mymusicstaff/scripts/setup.sh
```

## First login

MyMusicStaff emails a 6-digit verification code on the first login from a new device. If
Claude has a Gmail connector on the same inbox it fetches the code itself; otherwise it
asks you for it. After that the browser session is persisted (agent-browser session name
`mms`) and later runs do not prompt.

If the site shows a reCAPTCHA, the scripts stop and Claude runs `mms-login.sh`, which
opens a visible browser with your email prefilled so you can finish the login yourself.

## Security notes

- Credentials are read from the config file and passed to the browser over stdin, never
  on a command line or in chat.
- The scripts never snapshot the login page (agent-browser snapshots print field values).
- Session state files are created with mode 600 and are gitignored.

## Development

The skill was built test-first following the `writing-skills` method: a baseline agent
without the skill, then agents with the skill, then a code review, with every fix
re-tested against the live portal. `SKILL.md` documents the pitfalls that were found
(WebForms buttons that ignore clicks, Angular `mat-select` dropdowns, calendar state that
persists between runs).

## License

MIT
