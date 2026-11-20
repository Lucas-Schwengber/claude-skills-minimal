---
name: resume-later
description: Wrap up a Claude session before the user leaves, so nothing that needs the session to stay open is lost, and leave a handoff note with ready-made checks on running experiments; on return, run those checks and report what changed. Use when the user says they are leaving, stopping for the day, closing the session or laptop, wants to "wrap up", "pause" or "resume later", or comes back asking how their experiments went, or says "resume-later check".
---

Two modes: **wrap** (default, before leaving) and **check** (`/resume-later check`, or the user is back and asks how things went).

**Survives closing the session:** Slurm jobs submitted with `sbatch`, tmux or screen sessions, processes started with `setsid nohup`.
**Dies with it:** background Bash tasks and anything else still under the claude process, including `srun` and `salloc` (Slurm cancels the job when its `srun` process dies, even though `squeue` lists it like any other job). Also subagents, workflows, Monitors, `/loop` and ScheduleWakeup, session crons (CronCreate). Treat a long command in the app's Terminal tabs as at risk too: it belongs to the app, not to a job manager.

Handoff notes live in `~/.claude/resume-later/`, one per session: `<YYYY-MM-DD>_<project-slug>_<first 8 chars of $CLAUDE_CODE_SESSION_ID>.md`.

## Wrap

1. **Audit.** Run `${CLAUDE_SKILL_DIR}/scripts/audit.sh` (read-only, about 1 s). It lists processes started from this session as `AT_RISK` (under the claude process) or `DETACHED`, with a `_SRUN` suffix when the process runs `srun` or `salloc`, then all your Slurm jobs and tmux panes. A Slurm job whose `srun` shows as `AT_RISK_SRUN` is tied to the session. Add what the script cannot see, from this conversation: background agents, workflows, Monitors, loops, crons (CronList), Terminal tabs (`mcp__terminal__list_terminal_tabs`), results that exist only in the conversation, and uncommitted edits in repos you touched. Keep only Slurm jobs and tmux panes that belong to this session's work (job IDs seen in the conversation, submit time, work dir).
2. **Report.** A short table of the at-risk items: what each is, its progress, and what is lost if the session closes. Then one line on what already survives. If nothing is at risk, say so and skip to step 4.
3. **Wrap up.** Use AskUserQuestion when there is a real choice, and never stop, kill or `scancel` anything without an explicit yes.
   - **Keep running.** This is the default for anything that already survives (`sbatch` jobs, tmux, `DETACHED` processes). Leave it alone and record it in the note, with its job ID, log and outputs.

   For each at-risk item, choose one:
   - **Wait**, if it finishes within a few minutes (estimate from its log).
   - **Move to Slurm**, if it is long. This is the preferred relaunch on a Slurm cluster. Resubmit it with `sbatch`, using the same resources as the `srun` (`-p`, `-c`, `--mem`, `-t`, `-J`) plus `--chdir=<abs dir> -o <abs log> --wrap '<cmd>'`. A running process cannot be moved, so the relaunch starts it over. First check whether it resumes from a checkpoint, and tell the user how much progress is lost. Confirm the new job is `PENDING` or `RUNNING` before stopping the old copy. If both copies would write to the same outputs, stop the old one first. Use `setsid nohup <cmd> > <log> 2>&1 < /dev/null &` only for light work that does not belong in Slurm.
   - **Stop**, if it is no longer needed.
   - Agents and workflows: wait for them or let them go, and save what they produced. Monitors, loops and crons: stop them and put what they were watching into the note's checks.
   - Results that exist only in the conversation go into the note, or into a project file if they are meant to last. Do not commit unless asked.
4. **Write the note** (template below). Every check must be read-only, quick, use absolute paths, and work when pasted into a shell.
5. **Mark the session**, if the session tools are available: prefix this session's title with `⏸ ` (`set_session_title` with `"self"`), and record the `link` from `get_session("self")` in the note.
6. **Final message**, kept short: what is still running and where, what was relaunched or stopped, the note path, and how to come back. Either reopen this session (app sidebar, or `claude --resume <session-id>` from the project directory) or start a new session in that directory, then type `/resume-later check`.

### Note template

````markdown
---
session: <CLAUDE_CODE_SESSION_ID>
link: <session link, if known>
project: <absolute cwd>
created: <YYYY-MM-DD HH:MM>
status: waiting        # waiting | done
---
# <one-line topic>

## Where we are
Two to five lines: the goal, what was done, and the decision that waits on the results.

## Running
| what | PID / job ID | started | expected done | outputs and log |

## Checks
```bash
squeue -h -j 123,124 -o '%i %T %M' ; sacct -X -j 123,124 -o JobID,State,Elapsed,ExitCode
kill -0 4567 2>/dev/null && echo "4567 alive" || echo "4567 gone"; tail -n 5 /abs/path/run.log
ls -lt /abs/path/results | head
```

## On return
Numbered next steps, saying what to do if the runs succeeded and what to do if they failed.

## Loose ends
Uncommitted changes, what was stopped or relaunched during wrap-up, caveats.
````

## Check

1. **Find the note.** First look for the note whose `session` matches `$CLAUDE_CODE_SESSION_ID`. Failing that, look for a `waiting` note whose `project` is the current directory. If there are several or none, list all `waiting` notes and ask which one.
2. **Run the Checks block.** Report each item as still running (progress and ETA against "expected done"), finished (where the results are, with a one-line summary), or failed (exit code and the relevant log lines).
3. **Update the note.** Append `## Check <YYYY-MM-DD HH:MM>` with a one-line result for each item. When nothing is left running, set `status: done` and remove the `⏸ ` title prefix.
4. **Pick up** from "On return": propose the next step and wait for the user before starting new work.
