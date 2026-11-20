#!/usr/bin/env bash
# End Claude Code sessions the user has explicitly chosen. Linux only.
#
# Usage: end.sh [--kill] PID:START [PID:START ...]
#   PID:START come straight from scan.sh (START guards against PID reuse).
#   Sends SIGTERM and waits up to 5 s. Survivors get SIGKILL only with --kill.
#
# Refuses (and says why) when the target: is gone or was recycled, belongs to
# another user, is this session or one of its ancestors, is not a Claude Code
# process, has child processes (a running job), or is an SSH bridge / a daemon
# that still has sessions attached.
set -uo pipefail
[ -r /proc/self/stat ] || { echo "end.sh needs Linux /proc" >&2; exit 2; }

FORCE=0
[ "${1:-}" = "--kill" ] && { FORCE=1; shift; }
[ $# -gt 0 ] || { echo "usage: end.sh [--kill] PID:START ..." >&2; exit 2; }

ME=$(id -u)

start_of() {
  local s
  { s=$(<"/proc/$1/stat"); } 2>/dev/null || return 1
  s=${s##*) }
  set -- $s
  echo "${20}"
}

declare -A ANC
p=$$
while [ -n "$p" ] && [ "$p" -gt 1 ]; do
  ANC[$p]=1
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') || break
done

targets=() rss_of=() label_of=() start_of_pid=()
refuse() { echo "refused $1: $2"; }

for arg in "$@"; do
  pid=${arg%%:*} start=${arg#*:}
  case "$pid$start" in *[!0-9]*|"") refuse "$arg" "expected PID:START (numbers)"; continue ;; esac
  now=$(start_of "$pid") || { refuse "$pid" "already gone"; continue; }
  [ "$now" = "$start" ] || { refuse "$pid" "PID was reused by a different process"; continue; }
  [ "$(stat -c %u "/proc/$pid")" = "$ME" ] || { refuse "$pid" "not your process"; continue; }
  [ -z "${ANC[$pid]:-}" ] || { refuse "$pid" "this is the current session (or its parent)"; continue; }

  IFS= read -r -d '' argv0 < "/proc/$pid/cmdline" || true
  full=$(tr '\0' ' ' < "/proc/$pid/cmdline")
  kids=$(pgrep -P "$pid" | wc -l)
  case "$argv0" in
    */ccd-cli/*) kind=desktop-app ;;
    */extensions/anthropic.claude-code*) kind=vscode ;;
    claude|*/claude) kind=terminal ;;
    */remote/srv/*/server)
      case "$full" in
        *--serve*) kind=daemon ;;
        *) refuse "$pid" "SSH bridge, not a session"; continue ;;
      esac ;;
    *) refuse "$pid" "not a Claude Code process ($argv0)"; continue ;;
  esac
  if [ "$kids" -gt 0 ]; then
    refuse "$pid" "$kind has $kids child process(es); end them first if you really mean it"
    continue
  fi

  targets+=("$pid"); start_of_pid[$pid]=$start
  rss_of[$pid]=$(awk '/^VmRSS:/{print int($2/1024)}' "/proc/$pid/status")
  label_of[$pid]="$kind $(readlink "/proc/$pid/cwd" 2>/dev/null)"
done

[ "${#targets[@]}" -gt 0 ] || exit 1

for pid in "${targets[@]}"; do kill -TERM "$pid" 2>/dev/null; done
for _ in 1 2 3 4 5 6 7 8 9 10; do
  alive=0
  for pid in "${targets[@]}"; do
    [ "$(start_of "$pid" 2>/dev/null)" = "${start_of_pid[$pid]}" ] && alive=1
  done
  [ "$alive" = 0 ] && break
  sleep 0.5
done

freed=0 survivors=0
for pid in "${targets[@]}"; do
  if [ "$(start_of "$pid" 2>/dev/null)" = "${start_of_pid[$pid]}" ]; then
    if [ "$FORCE" = 1 ]; then
      kill -KILL "$pid" 2>/dev/null
      sleep 0.5
      echo "killed (SIGKILL) $pid: ${label_of[$pid]}"
      freed=$(( freed + rss_of[$pid] ))
    else
      echo "still running $pid: ${label_of[$pid]} (ignored SIGTERM; re-run with --kill if you want SIGKILL)"
      survivors=$(( survivors + 1 ))
    fi
  else
    echo "ended $pid: ${label_of[$pid]} (~${rss_of[$pid]} MB)"
    freed=$(( freed + rss_of[$pid] ))
  fi
done
echo "# freed ~${freed} MB, ${survivors} still running"
[ "$survivors" = 0 ]
