---
name: resources-summary
description: One compact table of the compute jobs and processes behind the current Claude session (or all of the user's runs), with node, cores, memory, GPUs, start, elapsed and a predicted completion time. Use when the user asks what is running, where it runs, for how long, with what resources, about GPU usage or job status, wants a resources summary or an overview of their jobs, or says "resources-summary".
---

Report what is running and when it should finish: Slurm jobs plus processes on this login machine. Read-only; never start, stop or `scancel` anything.

Two modes: **session** (default) covers only this session's work; **all** (`/resources-summary all`, or the user asks about all their runs, other sessions, "everything I have running") covers every Slurm job of the user and their experiment processes on this machine.

## Script

`${CLAUDE_SKILL_DIR}/scripts/resources.sh` is read-only and takes 1-3 s. It prints tab-separated sections: `## slurm` (`JOBID NAME STATE PARTITION NODE CPUS MEM GPUS START ELAPSED LIMIT EXPECTED_END WHAT SCRIPT LOG WORKDIR WHY`), `## local` (processes: `PID STATUS ELAPSED CPU% RSS_MB NPROC CWD CMD`), `## gpu` (local GPUs from `nvidia-smi`, or "no GPU on this machine"), and with `--all` also `## notes` (resume-later handoff notes still waiting). Comment lines start with `#`.

- Default mode keeps the Slurm jobs whose submit script, log or work dir lies under the project directory (`--project DIR`, default cwd), and the processes started from this session (resume-later's `audit.sh` logic: `AT_RISK` dies with the session, `DETACHED` survives).
- `--job ID,ID` adds jobs by id. Always pass the job ids you have seen in this conversation (`sbatch` output, `squeue` listings, handoff notes), since a job submitted from another directory is otherwise not matched.
- `--all` lists every job of the user and the user's long-running python/R/julia processes grouped by directory (editors and language servers skipped).
- `WHAT` is the `# ...` description line(s) after the SBATCH header of the submit script. `EXPECTED_END` states its basis: the median of past completed runs of the same job name (`sacct`, last 21 days, `--days N` to change), an `# ETA:` comment in the script or a `<log>.eta` sidecar, or otherwise "unknown" with the time limit as upper bound.

Do not use `grep` in this shell: it can be an `ugrep` wrapper that segfaults. Use `awk`.

## Workflow

1. Run the script: default mode, or `--all` when the user asks about all or other sessions' runs; add `--job` with the ids known from the conversation.
2. Render ONE compact markdown table, one row per job, with these columns: `job | what | node | cores / mem | GPUs | started | elapsed | expected end`. `what` is the script description shortened to a few words (fill in from the conversation when the script has none). `node` as `scf-sm10 (low)` (node and partition). `cores / mem` merged, e.g. `32 / 64 GB`. GPUs as `0` or `1 x A100`. `started` as `HH:MM` (add the date when it is not today). `elapsed` as `3 h 48 min`. `expected end` as a clock time or range plus the basis in a few words: "20:00 to 21:00 (past runs)", "about 20:15 (estimate from conversation)", "unknown, limit ends 2026-11-09 15:39". Pending jobs: state and reason instead of times. The sampler jobs here print no progress to their logs, so the prediction comes from past durations of the same job name, the time limit, or an estimate already made in the conversation; say which.
3. Below the table, one line on the login machine: the session's own processes (what they are, AT_RISK or not; omit the bash loop that is this very check) and the local GPUs. In `--all` mode group the local processes by project directory and mention jobs listed in handoff notes.
4. Keep it brief: a sentence or two before the table (how many jobs, where, anything finishing soon or overdue), nothing after it unless something failed, is overdue against its past runs, or is close to its time limit.

GPU utilisation of a running Slurm job can be read with `srun --jobid=<id> --overlap nvidia-smi`, and partition GPU types with `sinfo -o "%P %N %G"`. Run these only when the user asks for them.
