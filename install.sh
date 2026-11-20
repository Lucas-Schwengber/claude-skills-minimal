#!/usr/bin/env bash
# Symlink every skill folder in this repo (a top-level directory with a SKILL.md)
# into ~/.claude/skills, and prune links into this repo whose target is gone.
# Safe to re-run. Override the destination with CLAUDE_SKILLS_DIR.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
mkdir -p "$DEST"

for link in "$DEST"/*; do                       # prune dead links into this repo
  [ -L "$link" ] || continue
  case "$(readlink "$link")" in "$REPO"/*) ;; *) continue ;; esac
  [ -e "$link" ] || { rm -f "$link"; echo "unlinked: $(basename "$link")"; }
done

for d in "$REPO"/*/; do
  d="${d%/}"; name="$(basename "$d")"
  [ -f "$d/SKILL.md" ] || continue
  if [ -e "$DEST/$name" ] && [ ! -L "$DEST/$name" ]; then
    echo "skipped (real directory already at $DEST/$name): $name" >&2; continue
  fi
  ln -sfn "$d" "$DEST/$name"
  echo "linked: $name"
done
