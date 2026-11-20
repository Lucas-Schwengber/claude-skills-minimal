#!/usr/bin/env bash
# Read-only audit for resume-later: what this Claude session started that is still
# running, and whether it dies with the session. Linux only (reads /proc), current
# user only. Uses awk, never grep (grep here can be a crashing ugrep wrapper).
#
# Output sections (tab-separated rows):
#   ## session   UNIT_PID STATUS ELAPSED CPU% RSS_MB NPROC CWD CMD
#                STATUS is AT_RISK (a descendant of the claude process: dies with it)
#                or DETACHED (reparented away from claude: survives). A _SRUN suffix
#                means the unit runs srun/salloc: its Slurm job ends when that process does.
#   ## slurm     JOBID NAME STATE ELAPSED LIMIT SUBMIT WORKDIR    (survives)
#   ## tmux      PANE CMD PATH                                    (survives)
set -u
cpid=${CLAUDE_PID:-}
csid=${CLAUDE_CODE_SESSION_ID:-}

# Our own top-level Bash-tool wrapper: everything under it is this audit, not work.
self_top=$$
p=$$
while [ -n "$p" ] && [ "$p" -gt 1 ] && [ "$p" != "$cpid" ]; do
  self_top=$p
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done

# Processes launched from this session carry its env vars (BEGINFILE needs gawk).
tagged=$(ps -u "$(id -u)" -o pid= | awk '{printf "/proc/%s/environ\n", $1}' \
  | xargs gawk -v c="$cpid" -v s="$csid" 'BEGIN { RS = "\0"; FS = "=" }
      BEGINFILE { if (ERRNO != "") nextfile }
      ($1 == "CLAUDE_PID" && c != "" && $2 == c) || ($1 == "CLAUDE_CODE_SESSION_ID" && s != "" && $2 == s) {
        split(FILENAME, f, "/"); printf " %s", f[3]; nextfile }' 2>/dev/null)

echo "## session (claude pid ${cpid:-?}, session ${csid:-?})"
ps -u "$(id -u)" -o pid=,ppid=,etime=,pcpu=,rss=,args= 2>/dev/null | awk \
  -v cpid="$cpid" -v self="$self_top" -v tagged="$tagged" -v sq="'" -v esc="'\"'\"'" '
  BEGIN { n = split(tagged, t, " "); for (i = 1; i <= n; i++) tag[t[i]] = 1 }
  {
    pid = $1; par[pid] = $2; et[pid] = $3; cpu[pid] = $4; rss[pid] = $5
    a = $0; sub(/^ *[0-9]+ +[0-9]+ +[^ ]+ +[^ ]+ +[0-9]+ /, "", a); args[pid] = a
  }
  function under(x, y) { while (x != "" && x > 1) { if (x == y) return 1; x = par[x] } return 0 }
  function top(x) { while ((par[x] in tag) && par[x] != cpid) x = par[x]; return x }
  END {
    for (pid in tag) {
      if (!(pid in par) || pid == cpid || under(pid, self)) continue
      split(args[pid], w, " "); b = w[1]; sub(/.*\//, "", b)
      # Desktop helpers that some commands spawn on the side: not work.
      if (b ~ /^(dbus-daemon|dbus-launch|gnome-keyring-daemon|ssh-agent|gpg-agent)$/) continue
      u = top(pid); np[u]++; tc[u] += cpu[pid]; tr[u] += rss[pid]
      if (b == "srun" || b == "salloc") tied[u] = 1
    }
    for (u in np) {
      st = (cpid != "" && under(u, cpid)) ? "AT_RISK" : "DETACHED"
      if (u in tied) st = st "_SRUN"
      cmd = args[u]
      # Bash-tool wrapper: show the command it evals, not the snapshot boilerplate.
      if (index(cmd, "shell-snapshots/snapshot-") && (i = index(cmd, "&& eval " sq))) {
        cmd = substr(cmd, i + 9); sub(sq "( < /dev/null)? && pwd -P >\\| .*$", "", cmd)
        gsub(esc, sq, cmd); cmd = "[bash-tool] " cmd
      }
      cwd = ""; f = "readlink /proc/" u "/cwd 2>/dev/null"; f | getline cwd; close(f)
      printf "%s\t%s\t%s\t%.1f\t%d\t%d\t%s\t%s\n", u, st, et[u], tc[u], tr[u] / 1024, np[u], cwd, substr(cmd, 1, 200)
    }
  }' | sort -t$'\t' -k2,2 -k1,1n

echo "## slurm"
command -v squeue >/dev/null && squeue -u "$USER" -h -o $'%i\t%j\t%T\t%M\t%l\t%V\t%Z' 2>/dev/null

echo "## tmux"
command -v tmux >/dev/null && tmux list-panes -a \
  -F '#{session_name}:#{window_index}.#{pane_index}	#{pane_current_command}	#{pane_current_path}' 2>/dev/null
exit 0
