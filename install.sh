#!/usr/bin/env bash
# Symlink every skill folder in this repo (a top-level directory with a SKILL.md)
# into ~/.claude/skills, prune links into this repo whose target is gone, link
# global/hooks/* into ~/.claude/hooks and register them (global/hooks.json) in
# ~/.claude/settings.json, and point git's hooksPath at ./hooks so later pulls relink.
# Safe to re-run. Overrides: CLAUDE_SKILLS_DIR, CLAUDE_HOOKS_DIR, CLAUDE_SETTINGS_PATH.
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

# --- 3b. link Claude Code hook scripts from global/hooks ----------------------
# Only the scripts are linked here; step 3c registers them in settings.json.
hooks_dest="${CLAUDE_HOOKS_DIR:-$HOME/.claude/hooks}"
for src in "$REPO"/global/hooks/*; do
  [ -f "$src" ] || continue
  mkdir -p "$hooks_dest"
  dest="$hooks_dest/$(basename "$src")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "skipped (real file already at $dest): $(basename "$src")" >&2
    continue
  fi
  ln -sfn "$src" "$dest"
done

# --- 3c. register those hooks in ~/.claude/settings.json ---------------------
# global/hooks.json has the shape of settings.json's "hooks" object (event ->
# list of matcher groups). Each group is appended to the same event in settings.json
# unless it is already there, or one of its commands is already registered for that
# event, so re-running never duplicates and hooks you added yourself are kept.
# Entries should be "type": "command" hooks; the command is what identifies them.
manifest="$REPO/global/hooks.json"
settings="${CLAUDE_SETTINGS_PATH:-$HOME/.claude/settings.json}"
if [ -f "$manifest" ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "skipped (jq not found): add the entries of global/hooks.json under \"hooks\" in $settings by hand" >&2
  elif ! jq -e 'type == "object"' "$manifest" >/dev/null 2>&1; then
    echo "skipped (not a JSON object): $manifest" >&2
  else
    had_content=0
    [ -s "$settings" ] && had_content=1
    if [ "$had_content" -eq 1 ] && ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
      echo "skipped (not a JSON object, left untouched): $settings" >&2
    else
      mkdir -p "$(dirname "$settings")"
      merged="$(mktemp)"
      src="$settings"
      [ "$had_content" -eq 1 ] || { src="$(mktemp)"; echo '{}' > "$src"; }
      if jq --slurpfile m "$manifest" '
           .hooks = ((.hooks // {}) as $cur
             | reduce ($m[0] | to_entries[]) as $e ($cur;
                 .[$e.key] as $evt
                 | ([($evt // [])[]?.hooks[]?.command]) as $have
                 | .[$e.key] = (($evt // []) + [
                     $e.value[] | . as $g
                     | select((($evt // []) | index([$g])) == null
                              and (any($g.hooks[]?.command; IN($have[])) | not))
                   ])))
         ' "$src" > "$merged"; then
        if [ "$(jq -c . "$src")" != "$(jq -c . "$merged")" ]; then
          if [ "$had_content" -eq 1 ]; then
            backup="$settings.bak.$(date +%Y%m%d-%H%M%S)"
            cp -p "$settings" "$backup"
            cat "$merged" > "$settings"
            echo "registered hooks in $settings (backup: $backup)"
          else
            cat "$merged" > "$settings"
            echo "registered hooks in $settings (new file)"
          fi
        fi
      else
        echo "skipped (could not merge hooks into $settings, left untouched)" >&2
      fi
      [ "$src" = "$settings" ] || rm -f "$src"
      rm -f "$merged"
    fi
  fi
fi

# --- 4. install the git hooks (once) -----------------------------------------
if [ -d "$REPO/.git" ] || git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  mkdir -p "$REPO/hooks"
  for hook in post-merge post-rewrite; do
    path="$REPO/hooks/$hook"
    if [ ! -f "$path" ]; then
      cat > "$path" <<'HOOK'
#!/usr/bin/env bash
# Relink skills and re-register hooks, after a pull. Only runs
# install.sh when a SKILL.md or a file under global/ was added or removed, or
# global/hooks.json was edited; other edits need no relinking.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
base=ORIG_HEAD
git rev-parse --verify -q ORIG_HEAD >/dev/null || base='HEAD@{1}'
if { git diff --name-only --diff-filter=ADR "$base" HEAD -- '*/SKILL.md' 'global/*'
     git diff --name-only --diff-filter=M "$base" HEAD -- 'global/hooks.json'
   } 2>/dev/null | grep -q .; then
  exec "$root/install.sh"
fi
HOOK
      chmod +x "$path"
      echo "created hook: hooks/$hook"
    fi
  done
  git -C "$REPO" config core.hooksPath hooks
fi
