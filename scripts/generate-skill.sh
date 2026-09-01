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
  printf '%s\n' 'description: Safely create, inspect, and retire Git worktrees across an agent task lifecycle with platform naming, machine-readable preflight, merge proof, and guarded terminal cleanup. Use when implementation needs a task worktree, when auditing worktrees, or when completed work should retire its local worktree; do not use for ordinary branch-only Git operations.'
  printf '%s\n' '---'
  printf '\n# wt-axi\n\n'
  printf '%s\n\n' 'Use `wt-axi` as the project-agnostic lifecycle boundary. It delegates Git worktree primitives to the pinned upstream engine and adds platform naming, TOON output, and retirement safety gates.'
  printf '%s\n\n' 'Do not create a worktree for read-only work. For implementation, decide whether isolation is needed before invoking `wt-axi create`. When a task uses a task-specific worktree, a successfully completed terminal workflow should retire it after delivery and merge are proven, unless the user asked to preserve it. This terminal cleanup does not authorize remote-branch deletion. Never bypass wt-axi with raw removal commands.'
  printf '## Worktree decision\n\n'
  printf '%s\n\n' 'A separate worktree is optional only when every condition below is true:'
  printf '%s\n' '- Neither the user nor repository instructions require a separate worktree.'
  printf '%s\n' '- The change is small, localized, and reversible; it does not include dependency changes, schema or data migrations, or bulk-generated output.'
  printf '%s\n' '- The current worktree is the intended base, and the files to edit contain no unrelated changes.'
  printf '%s\n' '- No other agent or task will write to the repository concurrently.'
  printf '%s\n' '- The task needs no independent branch, commit, pull request, merge, or handoff.'
  printf '%s\n\n' '- Validation is bounded and does not require persistent services or scoped runtime resources.'
  printf '%s\n\n' 'If any condition is false or unknown, use a task-specific worktree. Typical in-place tasks are a typo, wording correction, or similarly local config edit. Use a worktree for a feature, cross-cutting bug fix, refactor, migration, dependency update, bulk generation, parallel-agent work, or any task requiring independent delivery.'
  printf '## Commands\n\n'
  while IFS=$'\t' read -r _ usage summary flags; do
    printf -- '- `%s` — %s. Flags: %s.\n' "$usage" "$summary" "$flags"
  done <"$ROOT/contract/cli-contract.tsv"
  printf '\n## Workflow\n\n'
  printf '%s\n' '1. Classify the task with the worktree decision above. For read-only or qualifying in-place work, stay in the current worktree and do not invoke create or retirement.'
  printf '%s\n' '2. When isolation is needed, run `wt-axi status`, derive a short lowercase kebab-case task slug, and create the task worktree with `wt-axi create --task-slug <slug> --branch <branch>`. Work only in the returned `<repo>/.worktrees/<project>-wt-<task-slug>` path.'
  printf '%s\n' '3. Do not run retirement merely because a session started or while implementation, review, delivery, or merge work remains active.'
  printf '%s\n' '4. At successful terminal completion, leave the task worktree, return to the primary worktree, and run `wt-axi status --target <ref>`. Read `retireSafe`; do not infer safety from a clean-looking folder.'
  printf '%s\n' '5. When `retireSafe` is true, run `wt-axi retire --path <path> --target <ref>` as the normal final local cleanup. When it is false, preserve the worktree and report the exact blocker.'
  printf '%s\n' '6. Preserve the remote branch by default. Add `--delete-remote-branch` only when the user explicitly asked to delete that remote branch; terminal completion alone is not consent.'
  printf '%s\n' '7. On any non-zero result, report the structured error and follow its help field. Never retry with force or run upstream hooks directly.'
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
