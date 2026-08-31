#!/usr/bin/env bash
# shellcheck disable=SC2016

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
TARGET="$ROOT/skills/wt-axi/SKILL.md"
MODE='write'

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE=check; shift ;;
    --skill-file)
      [ "$#" -ge 2 ] || { printf 'error: --skill-file requires a path\n' >&2; exit 2; }
      TARGET=$2; shift 2 ;;
    --help|-h)
      printf 'usage: scripts/generate-skill.sh [--check] [--skill-file <path>]\n'
      exit 0
      ;;
    *) printf 'error: unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

generated=$(mktemp "${TMPDIR:-/tmp}/wt-axi-skill.XXXXXX")
trap 'rm -f -- "$generated"' EXIT HUP INT TERM

{
  printf '%s\n' '---'
  printf '%s\n' 'name: wt-axi'
  printf '%s\n' 'description: Safely create, inspect, or retire Git worktrees for agent tasks with platform naming, machine-readable preflight, merge proof, and guarded cleanup. Use for worktree lifecycle requests; do not use for ordinary branch-only Git operations.'
  printf '%s\n' '---'
  printf '\n# wt-axi\n\n'
  printf '%s\n\n' 'Use `wt-axi` as the project-agnostic lifecycle boundary. It delegates Git worktree primitives to the pinned upstream engine and adds platform naming, TOON output, and retirement safety gates.'
  printf '%s\n\n' 'This skill does not grant cleanup authority. Create a worktree only within an implementation task. Retire one only after explicit cleanup intent or a terminal workflow with proven merge. Never bypass wt-axi with raw removal commands.'
  printf '## Commands\n\n'
  while IFS=$'\t' read -r _ usage summary flags; do
    printf -- '- `%s` — %s. Flags: %s.\n' "$usage" "$summary" "$flags"
  done <"$ROOT/contract/cli-contract.tsv"
  printf '\n## Workflow\n\n'
  printf '%s\n' '1. Run `wt-axi status` before creating or retiring anything. Read `retireSafe`; do not infer safety from a clean-looking folder.'
  printf '%s\n' '2. For creation, derive a short lowercase kebab-case task slug and run `wt-axi create --task-slug <slug> --branch <branch>`. Work only in the returned `<repo>/.worktrees/<project>-wt-<task-slug>` path.'
  printf '%s\n' '3. For retirement, leave the target worktree first. Run `wt-axi retire --path <path>` and preserve the remote branch by default.'
  printf '%s\n' '4. Add `--delete-remote-branch` only when the user explicitly asked to delete that remote branch. Do not treat a general cleanup request as remote deletion consent.'
  printf '%s\n' '5. On any non-zero result, report the structured error and follow its help field. Never retry with force or run upstream hooks directly.'
  printf '\n## Safety contract\n\n'
  while IFS=$'\t' read -r code statement; do
    printf -- '- `%s`: %s\n' "$code" "$statement"
  done <"$ROOT/contract/safety-rules.tsv"
  printf '\n## Exit codes\n\n'
  while IFS=$'\t' read -r code meaning; do
    printf -- '- `%s` — %s.\n' "$code" "$meaning"
  done <"$ROOT/contract/exit-codes.tsv"
  printf '\n## Missing installation\n\n'
  printf '%s\n' 'If `wt-axi` is unavailable, report that installation is required and point to the repository README. Do not install software or alter global agent configuration unless the user requested setup.'
} >"$generated"

if [ "$MODE" = check ]; then
  if ! cmp -s "$generated" "$TARGET"; then
    printf 'error: generated skill is stale: %s\n' "$TARGET" >&2
    diff -u "$TARGET" "$generated" >&2 || true
    exit 1
  fi
  printf 'skill_sync: ok\n'
  exit 0
fi

cp "$generated" "$TARGET"
printf 'generated: %s\n' "$TARGET"
