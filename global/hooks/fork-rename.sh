#!/usr/bin/env bash
# UserPromptSubmit hook: when a desktop session's title is still the default
# "<parent title> (fork)" / "(fork N)", tell Claude to rename it once.
# The title comes from the session registry in ~/.claude/sessions/<pid>.json,
# matched on the hook's session_id. Renamed titles start with "↳" and are skipped.

sid=$(jq -r '.session_id // empty')
[ -n "$sid" ] || exit 0

name=$(jq -rs --arg sid "$sid" \
  'map(select(.sessionId == $sid)) | sort_by(.updatedAt // 0) | last | .name // empty' \
  ~/.claude/sessions/*.json 2>/dev/null)

case "$name" in "↳"*) exit 0 ;; esac
printf '%s' "$name" | grep -Eq '\(fork( [0-9]+)?\)$' || exit 0

jq -n --arg t "$name" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: ("This session is a fork whose title is still the default \"" + $t + "\". Before answering, rename it with set_session_title(\"self\", ...); if that tool is only listed as deferred, load it with ToolSearch first. New title: \"↳ <a few words on what this fork is for, based on the user prompt> <the original (fork) suffix>\", for example \"↳ linearization check (fork 2)\". Do not mention the rename unless the user asks.")
  }
}'
