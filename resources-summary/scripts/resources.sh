#!/usr/bin/env bash
# Read-only summary for resources-summary: which compute jobs and processes are running,
# where, with what resources, since when, and when they should finish. Current user only.
# Uses awk, never grep (grep here can be a crashing ugrep wrapper). About 1-3 s; the
# slow part is sacct, which is bounded by a timeout.
#
# Usage: resources.sh [--all] [--project DIR] [--job ID[,ID...]] [--days N] [--min-etime SECS]
#   default      only what belongs to this Claude session: Slurm jobs whose script, log or
#                work dir lies under the project dir (cwd), jobs named with --job, and
#                processes started from this session (resume-later's audit.sh logic).
#   --all        every Slurm job of the user, the user's experiment processes on this
#                machine grouped by directory, and resume-later handoff notes.
#   --project    project directory for the relevance test (default: cwd).
#   --job        extra job ids to include (ids seen in the conversation).
#   --days       how far back sacct looks for past runs of the same job name (default 21).
#   --min-etime  --all only: ignore local processes younger than this (default 120 s).
#
# Output sections (tab-separated rows, "#" lines are comments):
#   ## slurm   JOBID NAME STATE PARTITION NODE CPUS MEM GPUS START ELAPSED LIMIT EXPECTED_END WHAT SCRIPT LOG WORKDIR WHY
#              GPUS is 0 or "N x TYPE". EXPECTED_END says what it is based on: past runs of
#              the same job name (sacct), an "# ETA:" comment in the script, or the time limit.
#              WHY is why the job is listed (project, --job, all).
#   ## local   PID STATUS ELAPSED CPU% RSS_MB NPROC CWD CMD
#              default: AT_RISK / DETACHED as in audit.sh (processes of this session).
#              --all: STATUS is LOCAL for every long-running python/R/julia process.
#   ## gpu     local GPUs from nvidia-smi, or "no GPU on this machine".
#   ## notes   --all only: resume-later handoff notes still "waiting" and their Running rows.
set -u
ALL=0 PROJ=$PWD EXTRA= DAYS=21 MIN_ETIME=120
while [ $# -gt 0 ]; do
  case "$1" in
    --all) ALL=1; shift ;;
    --project) PROJ=$2; shift 2 ;;
    --job) EXTRA="$EXTRA,$2"; shift 2 ;;
    --days) DAYS=$2; shift 2 ;;
    --min-etime) MIN_ETIME=$2; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
PROJ=$(cd "$PROJ" 2>/dev/null && pwd -P || printf '%s' "$PROJ")
EXTRA=$(printf '%s' "$EXTRA" | tr ', ' '\n\n' | awk 'NF' | sort -u | tr '\n' ',')
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
NOW=$(date +%s)

# Slurm durations (D-HH:MM:SS, HH:MM:SS, MM:SS) to seconds; "" when not a duration.
secs() {
  printf '%s' "$1" | awk -F'[-:]' '
    /^[0-9]+-[0-9]+:[0-9]+:[0-9]+$/ { print $1*86400 + $2*3600 + $3*60 + $4; next }
    /^[0-9]+:[0-9]+:[0-9]+$/        { print $1*3600 + $2*60 + $3; next }
    /^[0-9]+:[0-9]+$/               { print $1*60 + $2; next }
    { print "" }'
}
clock() { date -d "@$1" +%Y-%m-%dT%H:%M 2>/dev/null; }
under() { case "$1" in "$PROJ"|"$PROJ"/*) return 0 ;; esac; return 1; }

# predict START_EPOCH USED_SECS LIMIT_TEXT, with past Slurm durations of the same job name
# on stdin (one per line): median-based end time, range over past runs, and a flag when the
# job already ran longer than any of them.
predict() {
  awk -F'[-:]' -v start="$1" -v used="$2" -v lim="$3" '
    function fmt(s) { s = int(s); return (s >= 86400) ? sprintf("%dd %dh%02dm", s/86400, (s%86400)/3600, (s%3600)/60) : sprintf("%dh%02dm", s/3600, (s%3600)/60) }
    function at(e, f,   c, t) { c = "date -d @" int(e) " +" f; c | getline t; close(c); return t }
    NF { s = (NF == 4) ? $1*86400 + $2*3600 + $3*60 + $4 : (NF == 3) ? $1*3600 + $2*60 + $3 : $1*60 + $2
         v[++n] = s; if (n == 1 || s < lo) lo = s; if (n == 1 || s > hi) hi = s }
    END {
      if (n == 0) exit
      for (i = 2; i <= n; i++) { x = v[i]; for (j = i - 1; j >= 1 && v[j] > x; j--) v[j+1] = v[j]; v[j+1] = x }
      med = (n % 2) ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2
      rng = (n > 1) ? " (range " at(start + lo, "%H:%M") " to " at(start + hi, "%H:%M") ")" : ""
      over = (used > hi) ? sprintf("; already %s past the longest past run", fmt(used - hi)) : ""
      printf "%s%s [median of %d past run%s of this job name, %s%s; %s]", at(start + med, "%Y-%m-%dT%H:%M"), rng, n, (n > 1 ? "s" : ""), fmt(med), over, lim }'
}

# ---------------------------------------------------------------- slurm
echo "## slurm (project $PROJ; mode $([ "$ALL" = 1 ] && echo all || echo session)${EXTRA:+; extra jobs ${EXTRA%,}})"
if ! command -v squeue >/dev/null 2>&1; then
  echo "# no slurm on this machine"
else
  # Past runs per job name, for the prediction: "name<TAB>secs" rows of finished jobs.
  hist=""
  if command -v sacct >/dev/null 2>&1; then
    since=$(date -d "$DAYS days ago" +%Y-%m-%d 2>/dev/null || echo "")
    hist=$(timeout 25 sacct -u "$USER" -X -n -P -S "${since:-2020-01-01}" -o JobName%60,Elapsed,State 2>/dev/null \
      | awk -F'|' '$3 == "COMPLETED" || $3 == "TIMEOUT" { print $1 "\t" $2 "\t" $3 }')
  fi

  shown=0 hidden=0
  while IFS='|' read -r jid name part state used start cpus mem nodes tres wdir cmd limit log reason _; do
    [ -n "$jid" ] || continue
    why=""
    if [ "$ALL" = 1 ]; then why="all"; fi
    case ",$EXTRA" in *",$jid,"*) why="${why:+$why,}job-id" ;; esac
    if under "$wdir" || under "$cmd" || under "$log"; then why="${why:+$why,}project"; fi
    if [ -z "$why" ]; then hidden=$((hidden + 1)); continue; fi
    shown=$((shown + 1))

    # GPUs from TRES per node: gres/gpu:A100:1, gres/gpu:2, gres:gpu:a100:1, N/A ...
    gpus=$(printf '%s' "$tres" | awk -F, '{
      out = ""
      for (i = 1; i <= NF; i++) if ($i ~ /gpu/) {
        g = $i; sub(/^.*gpu/, "", g); n = split(g, p, "[:=]"); cnt = ""; typ = ""
        for (k = 2; k <= n; k++) { if (p[k] ~ /^[0-9]+$/) cnt = p[k]; else if (p[k] != "") typ = p[k] }
        if (cnt == "") cnt = 1
        out = out (out == "" ? "" : "+") cnt (typ == "" ? "" : " x " typ)
      }
      print (out == "" ? "0" : out) }')

    # "what": the "# ..." description lines of the submit script after the SBATCH header.
    what=""; eta=""
    if [ -f "$cmd" ]; then
      what=$(awk 'NR == 1 && /^#!/ { next }
                  /^#SBATCH/ { next }
                  /^#[ \t]*(ETA|eta|Eta|expected)[:=]/ { next }
                  /^#/ { s = $0; sub(/^#+[ \t]*/, "", s); if (s != "") d = d (d == "" ? "" : " ") s; next }
                  NF { exit }
                  END { print d }' "$cmd" | cut -c1-200)
      eta=$(awk '/^#[ \t]*(ETA|eta|Eta|expected)[:=]/ { s = $0; sub(/^#[ \t]*[A-Za-z]+[:=][ \t]*/, "", s); print s; exit }' "$cmd")
    fi
    # Sidecar estimate next to the log: <log>.eta with a free-text line.
    [ -z "$eta" ] && [ -n "$log" ] && [ -r "$log.eta" ] && eta=$(head -n 1 "$log.eta")

    # Expected end.
    used_s=$(secs "$used"); lim_s=$(secs "$limit"); start_s=""
    case "$start" in N/A|Unknown|"") ;; *) start_s=$(date -d "$start" +%s 2>/dev/null) ;; esac
    if [ "$state" != "RUNNING" ]; then
      exp="not running ($state${reason:+, $reason})"
      [ -n "$start_s" ] && [ "$start_s" -gt "$NOW" ] && exp="$exp; scheduled start $(clock "$start_s")"
    else
      [ -z "$start_s" ] && start_s=$((NOW - ${used_s:-0}))
      lim_txt="no limit"; [ -n "$lim_s" ] && lim_txt="limit $limit, by $(clock $((start_s + lim_s)))"
      past=$(printf '%s\n' "$hist" | awk -F'\t' -v n="$name" '$1 == n && $3 == "COMPLETED" { print $2 }')
      if [ -n "$eta" ]; then
        exp="$eta (ETA note in script; $lim_txt)"
      elif [ -n "$past" ]; then
        exp=$(printf '%s\n' "$past" | predict "$start_s" "${used_s:-0}" "$lim_txt")
      else
        exp="unknown (no past run of this name; $lim_txt)"
      fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$jid" "$name" "$state" "$part" "${nodes:-?}" "$cpus" "$mem" "$gpus" "$start" "$used" "$limit" "$exp" "${what:-?}" "$cmd" "$log" "$wdir" "$why"
  done < <(squeue -u "$USER" -h -O "JobID:|,Name:|,Partition:|,State:|,TimeUsed:|,StartTime:|,NumCPUs:|,MinMemory:|,NodeList:|,tres-per-node:|,WorkDir:|,Command:|,TimeLimit:|,StdOut:|,Reason:|" 2>/dev/null)
  [ "$shown" = 0 ] && echo "# no matching slurm jobs"
  [ "$hidden" -gt 0 ] && echo "# $hidden other job(s) of yours not shown (use --all)"
  [ -n "$hist" ] || echo "# no sacct history available (predictions fall back to the time limit)"
fi

# ---------------------------------------------------------------- local processes
if [ "$ALL" = 0 ]; then
  echo "## local (processes started from this Claude session; AT_RISK dies with it, DETACHED survives)"
  audit=$HERE/../../resume-later/scripts/audit.sh
  if [ -x "$audit" ]; then
    out=$("$audit" 2>/dev/null | awk '/^## session/ { on = 1; next } /^## / { on = 0 } on')
    if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "# none"; fi
  else
    echo "# resume-later/scripts/audit.sh not found; falling back to session-tagged processes (no AT_RISK/DETACHED split)"
    # Our own Bash-tool wrapper and everything under it is this script, not work.
    self_top=$$; p=$$
    while [ -n "$p" ] && [ "$p" -gt 1 ] && [ "$p" != "${CLAUDE_PID:-}" ]; do
      self_top=$p; p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    done
    tagged=""
    for e in /proc/[0-9]*/environ; do
      [ -r "$e" ] || continue
      tr '\0' '\n' 2>/dev/null < "$e" | awk -v s="${CLAUDE_CODE_SESSION_ID:-}" -v p="${CLAUDE_PID:-}" \
        '($0 == "CLAUDE_CODE_SESSION_ID=" s && s != "") || ($0 == "CLAUDE_PID=" p && p != "") { f = 1; exit } END { exit !f }' \
        && tagged="$tagged ${e#/proc/}"
    done
    ps -u "$(id -u)" -o pid=,ppid=,etime=,pcpu=,rss=,args= 2>/dev/null | awk -v tagged="${tagged//\/environ/}" -v self="$self_top" -v cpid="${CLAUDE_PID:-}" '
      BEGIN { n = split(tagged, t, " "); for (i = 1; i <= n; i++) tag[t[i]] = 1 }
      { pid = $1; par[pid] = $2; et[pid] = $3; cpu[pid] = $4; rss[pid] = $5
        a = $0; sub(/^ *[0-9]+ +[0-9]+ +[^ ]+ +[^ ]+ +[0-9]+ /, "", a); args[pid] = a }
      function under(x, y) { while (x != "" && x > 1) { if (x == y) return 1; x = par[x] } return 0 }
      END {
        for (pid in tag) {
          if (!(pid in par) || pid == cpid || under(pid, self) || (par[pid] in tag)) continue
          cwd = ""; f = "readlink /proc/" pid "/cwd 2>/dev/null"; f | getline cwd; close(f)
          printf "%s\tSESSION\t%s\t%s\t%d\t1\t%s\t%s\n", pid, et[pid], cpu[pid], rss[pid] / 1024, cwd, substr(args[pid], 1, 200)
        }
      }' | sort -t$'\t' -k1,1n
  fi
else
  echo "## local (user's python/R/julia processes older than ${MIN_ETIME}s on $(hostname), grouped by directory; editors and language servers skipped)"
  ps -u "$(id -u)" -o pid=,etimes=,etime=,pcpu=,rss=,args= 2>/dev/null | awk -v min="$MIN_ETIME" '
    {
      pid = $1; ets = $2; et = $3; cpu = $4; rss = $5
      a = $0; sub(/^ *[0-9]+ +[0-9]+ +[^ ]+ +[^ ]+ +[0-9]+ /, "", a)
      split(a, w, " "); b = w[1]; sub(/.*\//, "", b)
      if (b !~ /^(python[0-9.]*|R|Rscript|julia|matlab|MATLAB|stan|cmdstan|sample)$/) next
      if (a ~ /vscode-server|language_server|pylance|jedi|lsp_server|python-env-tools|pyright|debugpy|black|ruff/) next
      if (ets + 0 < min + 0) next
      cwd = ""; f = "readlink /proc/" pid "/cwd 2>/dev/null"; f | getline cwd; close(f)
      printf "%s\tLOCAL\t%s\t%s\t%d\t1\t%s\t%s\n", pid, et, cpu, rss / 1024, cwd, substr(a, 1, 200)
    }' | sort -t$'\t' -k7,7 -k3,3r
  [ "${PIPESTATUS[0]:-0}" = 0 ] || true
fi

# ---------------------------------------------------------------- GPUs
echo "## gpu (local machine $(hostname))"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null \
    || echo "# nvidia-smi present but failed"
else
  echo "no GPU on this machine"
fi

# ---------------------------------------------------------------- handoff notes
if [ "$ALL" = 1 ]; then
  echo "## notes (resume-later handoff notes still waiting)"
  found=0
  for n in "$HOME"/.claude/resume-later/*.md; do
    [ -f "$n" ] || continue
    st=$(awk -F': *' 'NR > 1 && /^status:/ { print $2; exit } /^---$/ && NR > 1 { exit }' "$n")
    case "$st" in waiting*) ;; *) continue ;; esac
    found=1
    pj=$(awk -F': *' 'NR > 1 && /^project:/ { print $2; exit } /^---$/ && NR > 1 { exit }' "$n")
    printf '%s\t%s\n' "$n" "$pj"
    awk '/^## Running/ { on = 1; next } /^## / { on = 0 } on && /^\|/ && $0 !~ /^\| *what *\|/ && $0 !~ /^\|[- |]*\|$/ { print "\t" $0 }' "$n"
  done
  [ "$found" = 1 ] || echo "# none"
fi
exit 0
