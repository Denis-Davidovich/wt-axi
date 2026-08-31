#!/usr/bin/env bash

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
SMOKE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wt-axi-skill-smoke.XXXXXX")
trap 'rm -rf -- "$SMOKE_ROOT"' EXIT HUP INT TERM

verified=0
for agent in codex claude-code opencode; do
  project="$SMOKE_ROOT/$agent"
  mkdir -p "$project"
  git -C "$project" init -q
  (
    cd "$project"
    npx -y skills add "$ROOT" --skill wt-axi --agent "$agent" --copy -y >/dev/null
  )

  candidate=$(find "$project" -type f -path '*/wt-axi/SKILL.md' -print -quit)
  [ -n "$candidate" ] || { printf 'error: skill was not discoverable for %s\n' "$agent" >&2; exit 1; }
  grep -Fq 'guarded terminal cleanup' "$candidate"
  grep -Fq 'completed work should retire its local worktree' "$candidate"
  grep -Fq '<repo>/.worktrees/<project>-wt-<task-slug>' "$candidate"
  grep -Fq 'wt-axi status' "$candidate"
  grep -Fq 'wt-axi retire --path' "$candidate"
  verified=$((verified + 1))
done

printf 'skillSmoke:\n  agentsRequested: 3\n  agentsVerified: %s\n  triggerPathAndCommands: true\n' "$verified"
