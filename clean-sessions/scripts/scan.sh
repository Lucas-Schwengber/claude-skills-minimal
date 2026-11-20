#!/usr/bin/env bash
# Scan the current user's Claude Code processes and flag dangling-session candidates.
# Linux only (/proc). Read-only: never sends a signal.
#
# Usage: scan.sh [--sample SECS] [--min-age-hours N] [--old-days N] [--hot-cpu PCT]
#
# Prints one tab-separated row per process, best candidates first:
#   PID KIND VERDICT AGE_H CPU_NOW CPU_TOTAL_MIN RSS_MB KIDS TTY START CWD REASON
# KIND:    terminal | desktop-app | vscode | daemon | bridge
# VERDICT: SUGGEST (propose ending) | OPTIONAL | KEEP | SELF
# START is the /proc start time in ticks; hand PID:START to end.sh so a recycled
# PID is never signalled. A "# ..." summary line goes to stderr.
set -euo pipefail
[ -r /proc/self/stat ] || { echo "scan.sh needs Linux /proc" >&2; exit 2; }

SAMPLE=3 MIN_AGE_H=1 OLD_DAYS=2 HOT_CPU=10
while [ $# -gt 0 ]; do
  case "$1" in
    --sample) SAMPLE=$2; shift 2 ;;
    --min-age-hours) MIN_AGE_H=$2; shift 2 ;;
    --old-days) OLD_DAYS=$2; shift 2 ;;
    --hot-cpu) HOT_CPU=$2; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

TCK=$(getconf CLK_TCK)
ME=$(id -u)

# "cpu_ticks start_ticks" for a pid; fails if it is gone. Fields are counted
# after stripping "pid (comm) " because comm may contain spaces.
ticks() {
  local s
  { s=$(<"/proc/$1/stat"); } 2>/dev/null || return 1
  s=${s##*) }
  set -- $s
  echo "$(( ${12} + ${13} )) ${20}"
}

# this shell's ancestors, so the session running the scan is never a candidate
declare -A ANC
p=$$
while [ -n "$p" ] && [ "$p" -gt 1 ]; do
  ANC[$p]=1
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') || break
done

# pass 1: classify by argv0 only (a substring match would also hit shell wrappers
# whose path mentions ".claude")
declare -A KIDS CHET KIND ET TTY RSS PPID_ CWD
pids=()
while read -r pid ppid et tty rss argv0 rest; do
  KIDS[$ppid]=$(( ${KIDS[$ppid]:-0} + 1 ))
  [ "$et" -gt "${CHET[$ppid]:-0}" ] && CHET[$ppid]=$et   # oldest child, seconds
  kind=""
  case "$argv0" in
    */ccd-cli/*) kind=desktop-app ;;
    */extensions/anthropic.claude-code*) kind=vscode ;;
    */remote/srv/*/server)
      case "$rest" in *--bridge*) kind=bridge ;; *--serve*) kind=daemon ;; esac ;;
    claude|*/claude) kind=terminal ;;
  esac
  [ -n "$kind" ] || continue
  pids+=("$pid")
  KIND[$pid]=$kind ET[$pid]=$et TTY[$pid]=$tty RSS[$pid]=$rss PPID_[$pid]=$ppid
  CWD[$pid]=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "?")
done < <(ps -u "$ME" -o pid=,ppid=,etimes=,tty=,rss=,args=)

[ "${#pids[@]}" -gt 0 ] || { echo "# no Claude Code processes found for uid $ME" >&2; exit 0; }

# pass 2: CPU sampled over SAMPLE seconds (lifetime averages hide a stuck loop)
declare -A T1 START
for pid in "${pids[@]}"; do
  if r=$(ticks "$pid"); then T1[$pid]=${r% *} START[$pid]=${r#* }; fi
done
sleep "$SAMPLE"

for pid in "${pids[@]}"; do
  [ -n "${T1[$pid]:-}" ] || continue
  r=$(ticks "$pid") || continue
  t2=${r% *}
  tty=${TTY[$pid]}
  orphan=0
  if [ "${KIND[$pid]}" = terminal ]; then
    { [ "${PPID_[$pid]}" = 1 ] || { [ "$tty" != "?" ] && [ ! -e "/dev/$tty" ]; }; } && orphan=1
  fi
  self=0; [ -n "${ANC[$pid]:-}" ] && self=1
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$pid" "${KIND[$pid]}" "${ET[$pid]}" "$t2" "$(( t2 - ${T1[$pid]} ))" \
    "${RSS[$pid]}" "${KIDS[$pid]:-0}" "$tty" "${START[$pid]}" "$orphan$self" \
    "${CWD[$pid]}" "${CHET[$pid]:-0}"
done | awk -F'\t' -v OFS='\t' -v tck="$TCK" -v sample="$SAMPLE" \
         -v minage="$MIN_AGE_H" -v oldd="$OLD_DAYS" -v hot="$HOT_CPU" '
  function dur(s) { return s<3600 ? sprintf("%dm", s/60) : s<86400 ? sprintf("%.1fh", s/3600) : sprintf("%.1fd", s/86400) }
  {
    pid=$1; kind=$2; age=$3/3600; tot=$4; cpu=$5*100/(tck*sample); rss=$6/1024
    kids=$7; tty=$8; start=$9; orphan=substr($10,1,1)+0; self=substr($10,2,1)+0; cwd=$11; chet=$12
    v="KEEP"; why="recent / normal"; rank=3
    if (self)                   { v="SELF"; why="this session"; rank=4 }
    else if (kind=="bridge")    { why="SSH bridge for the desktop app" }
    else if (kind=="daemon")    {
      if (kids==0) { v="OPTIONAL"; why="desktop-app daemon with no sessions"; rank=2 }
      else         { why=kids " session(s) attached" }
    }
    else if (kids>0)            { why=sprintf("%d child process(es), oldest running %s: a command or job is in flight", kids, dur(chet)) }
    else if (age<minage)        { why="started recently" }
    else if (orphan)            { v="SUGGEST"; why="orphaned: parent shell or terminal is gone"; rank=0 }
    else if (cpu>=hot)          { v="SUGGEST"; why=sprintf("burning %.0f%% CPU with no child processes", cpu); rank=0 }
    else if (age>=oldd*24)      { v="SUGGEST"; why=sprintf("%.1f days old, no child processes, %.1f%% CPU", age/24, cpu); rank=1 }
    n[v]++; mb[v]+=rss
    printf "%d\t%s\t%s\t%s\t%.1f\t%.1f\t%.1f\t%.0f\t%d\t%s\t%s\t%s\t%s\n",
      rank, pid, kind, v, age, cpu, tot/tck/60, rss, kids, tty, start, cwd, why
  }
  END {
    printf "# %d SUGGEST (%.0f MB), %d OPTIONAL, %d KEEP (%.0f MB), %d SELF  [sample=%ss min-age=%sh old=%sd hot=%s%%]\n",
      n["SUGGEST"], mb["SUGGEST"], n["OPTIONAL"], n["KEEP"], mb["KEEP"], n["SELF"],
      sample, minage, oldd, hot > "/dev/stderr"
  }' | sort -t $'\t' -k1,1n -k6,6nr | cut -f2-
