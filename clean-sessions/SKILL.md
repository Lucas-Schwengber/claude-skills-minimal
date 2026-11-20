---
name: clean-sessions
description: Find dangling Claude Code sessions on this machine (stuck, orphaned, or long-idle processes wasting CPU or memory), show them, and ask the user which to end. Use when the user mentions dangling, stale, zombie, or leftover claude sessions, claude eating CPU or memory on a server, or says "clean up sessions" or "clean-sessions".
---

Scan for Claude Code processes that look forgotten, show them, ask which to end, and end only what the user picks. Linux only (reads `/proc`). Only ever look at the current user's processes: on a shared server other users' `claude` processes are none of your business, so never list, inspect, or signal them.

## Scripts

Both live in `${CLAUDE_SKILL_DIR}/scripts/`.

- `scan.sh` is read-only and takes about 4 s because it samples CPU. One tab-separated row per process, best candidates first: `PID KIND VERDICT AGE_H CPU_NOW CPU_TOTAL_MIN RSS_MB KIDS TTY START CWD REASON`, plus a `#` summary line on stderr. Flags: `--min-age-hours N` (default 1), `--old-days N` (default 2), `--hot-cpu PCT` (default 10), `--sample SECS`.
- `end.sh [--kill] PID:START ...` sends SIGTERM and waits 5 s. It re-checks every target and refuses with a reason if the PID was recycled, is not yours, is this session, is not a Claude process, or has child processes. `--kill` (SIGKILL) only for survivors.

Do not use `grep` in this shell: it can be an `ugrep` wrapper that segfaults. Use `awk`.

## Verdicts

| Verdict | Meaning |
|---|---|
| SUGGEST | Orphaned (parent shell or terminal gone), or burning CPU with no child processes, or old (past `--old-days`) with no child processes. Propose ending. |
| OPTIONAL | A desktop-app daemon with no sessions. Cheap (about 10 MB); offer it, never push it. |
| KEEP | Has a child process (a command or job is in flight), started within `--min-age-hours`, or is an SSH bridge or a daemon with sessions attached. Never offer these. |
| SELF | This session and its ancestors. Never offer. |

The verdict is a heuristic. A SUGGEST session may still hold a conversation the user wants to keep going, so say so when asking.

## Workflow

1. **Scan.** Run `scan.sh`, passing threshold flags if the user gave any ("older than a day" → `--old-days 1`).
2. **Report.** Show the SUGGEST and OPTIONAL rows as a table: PID, kind, age, CPU now, RSS MB, directory, reason. Collapse KEEP and SELF into one line (counts and total MB), and name any KEEP row whose child has been running for a long time. If nothing is SUGGEST or OPTIONAL, say so and stop.
3. **Ask** with `AskUserQuestion`. Nothing is ended without an explicit choice.
   - First question: "End all N suggested sessions?" with options *End all N (Recommended)*, *Let me pick*, *Keep all*. Add a separate yes/no question for an OPTIONAL daemon if one exists.
   - If they pick individually, ask `multiSelect` questions of up to 4 sessions each, labelled `PID · kind · age · CPU%`, with directory and reason as the description. Batch over several calls if there are more than 4.
   - Treat any free-text answer conservatively. If it is ambiguous, ask again rather than guessing.
4. **End.** Run `end.sh` with the exact `PID:START` pairs from the scan. If it refuses one, report the reason and leave it alone: do not work around a refusal with a raw `kill`. If a process survives SIGTERM, ask before using `--kill`.
5. **Report back.** What ended, what survived or was refused, and the MB freed. Add the relevant consequences:
   - Terminal session: its tmux pane or terminal is left at a shell prompt. `claude --resume` restores the conversation.
   - Desktop-app session: it stays in the app's sidebar and its transcript is safe. The app may respawn the process when it reconnects or when the session is opened.
   - VS Code session: the extension may respawn it.
