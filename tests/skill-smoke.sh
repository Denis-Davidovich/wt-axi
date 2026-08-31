#!/usr/bin/env bash

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
SMOKE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wt-axi-skill-smoke.XXXXXX")
trap 'rm -rf -- "$SMOKE_ROOT"' EXIT HUP INT TERM

mkdir -p "$SMOKE_ROOT/project"
git -C "$SMOKE_ROOT/project" init -q
(
  cd "$SMOKE_ROOT/project"
  npx -y skills add "$ROOT" --skill wt-axi --agent codex claude-code opencode --copy -y >/dev/null
)

found=0
for candidate in \
  "$SMOKE_ROOT/project/.agents/skills/wt-axi/SKILL.md" \
  "$SMOKE_ROOT/project/.codex/skills/wt-axi/SKILL.md" \
  "$SMOKE_ROOT/project/.claude/skills/wt-axi/SKILL.md" \
  "$SMOKE_ROOT/project/.config/opencode/skills/wt-axi/SKILL.md"; do
  if [ -f "$candidate" ]; then
    found=$((found + 1))
    rg -q 'Safely create, inspect, or retire Git worktrees' "$candidate"
    rg -q 'wt-axi status' "$candidate"
    rg -q 'wt-axi retire --path' "$candidate"
  fi
done
[ "$found" -gt 0 ] || { printf 'error: installed skill was not discoverable\n' >&2; exit 1; }
printf 'skillSmoke:\n  agentsRequested: 3\n  installedCopiesFound: %s\n  triggerAndCommands: true\n' "$found"
