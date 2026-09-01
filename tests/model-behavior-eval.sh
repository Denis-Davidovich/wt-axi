#!/usr/bin/env bash

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
SKILL="$ROOT/skills/wt-axi/SKILL.md"
PLATFORM_AGENTS="$ROOT/examples/platform-AGENTS.md"
MODEL_OVERRIDE=
OUTPUT_DIR=

usage() {
  printf '%s\n' 'usage: tests/model-behavior-eval.sh [--model <model>] [--output-dir <path>]'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model)
      if [ "$#" -lt 2 ] || [ -z "$2" ] || [ "${2#-}" != "$2" ]; then
        printf 'error: --model requires a value\n' >&2
        exit 2
      fi
      MODEL_OVERRIDE=$2
      shift 2
      ;;
    --output-dir)
      if [ "$#" -lt 2 ] || [ -z "$2" ] || [ "${2#-}" != "$2" ]; then
        printf 'error: --output-dir requires a path\n' >&2
        exit 2
      fi
      OUTPUT_DIR=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown flag: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v codex >/dev/null 2>&1 || {
  printf 'error: provider CLI is unavailable: codex\n' >&2
  exit 1
}
[ -f "$SKILL" ] || { printf 'error: missing skill: %s\n' "$SKILL" >&2; exit 1; }
[ -f "$PLATFORM_AGENTS" ] || {
  printf 'error: missing platform instructions: %s\n' "$PLATFORM_AGENTS" >&2
  exit 1
}

EVAL_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wt-axi-behavior-eval.XXXXXX")
trap 'rm -rf -- "$EVAL_ROOT"' EXIT HUP INT TERM

write_shim() {
  shim_path=$1
  cat >"$shim_path" <<'SHIM'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"$WT_AXI_BEHAVIOR_LOG"
command_name=${1:-}
[ "$#" -eq 0 ] || shift

case "$command_name" in
  status)
    repo_root=$(git rev-parse --show-toplevel)
    branch=$(git symbolic-ref --short HEAD)
    printf 'worktrees[1]{path,branch,dirty,merged,runtimeState,retireSafe}:\n'
    printf '  "%s","%s",false,false,"none",false\n' "$repo_root" "$branch"
    ;;
  create)
    task_slug=
    branch=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --task-slug) task_slug=${2:-}; shift 2 ;;
        --branch) branch=${2:-}; shift 2 ;;
        --from) shift 2 ;;
        *) printf 'error: unexpected shim argument: %s\n' "$1" >&2; exit 2 ;;
      esac
    done
    [ -n "$task_slug" ] || { printf 'error: shim requires --task-slug\n' >&2; exit 2; }
    [ -n "$branch" ] || { printf 'error: shim requires --branch\n' >&2; exit 2; }
    repo_root=$(git rev-parse --show-toplevel)
    project=$(basename "$repo_root" | cut -d. -f1)
    worktree_path="$repo_root/.worktrees/$project-wt-$task_slug"
    mkdir -p "$worktree_path"
    printf 'worktree:\n'
    printf '  path: "%s"\n' "$worktree_path"
    printf '  branch: "%s"\n' "$branch"
    printf '  hookStatus: "none"\n'
    printf '  naming: "%s-wt-%s"\n' "$project" "$task_slug"
    ;;
  *)
    printf 'error: unsupported shim command: %s\n' "$command_name" >&2
    exit 2
    ;;
esac
SHIM
  chmod +x "$shim_path"
}

prepare_fixture() {
  fixture=$1
  mkdir -p "$fixture/bin" "$fixture/.agents/skills/wt-axi"
  git -C "$fixture" init -q --initial-branch=main
  git -C "$fixture" config user.name 'wt-axi behavior eval'
  git -C "$fixture" config user.email 'wt-axi@example.invalid'
  cp "$PLATFORM_AGENTS" "$fixture/AGENTS.md"
  cp "$SKILL" "$fixture/.agents/skills/wt-axi/SKILL.md"
  printf '# Sample\n\nExisting project summary.\n' >"$fixture/README.md"
  printf '.worktrees/\n/bin/\n/calls.log\n' >"$fixture/.gitignore"
  git -C "$fixture" add AGENTS.md README.md .gitignore .agents
  git -C "$fixture" commit -qm 'test: initialize behavior fixture'
  : >"$fixture/calls.log"
  write_shim "$fixture/bin/wt-axi"
}

run_codex() {
  fixture=$1
  prompt=$2
  response=$3
  stdout_log=$4
  stderr_log=$5
  selected_model=${MODEL_OVERRIDE:-${WT_AXI_EVAL_CODEX_MODEL:-}}
  shell_policy=$(printf '{PATH="%s/bin:%s", WT_AXI_BEHAVIOR_LOG="%s/calls.log"}' \
    "$fixture" "$PATH" "$fixture")

  if [ -n "$selected_model" ]; then
    codex exec --ignore-user-config --ephemeral --sandbox workspace-write \
      --cd "$fixture" --model "$selected_model" \
      -c shell_environment_policy.inherit=all \
      -c "shell_environment_policy.set=$shell_policy" \
      --output-last-message "$response" - \
      <"$prompt" >"$stdout_log" 2>"$stderr_log"
  else
    codex exec --ignore-user-config --ephemeral --sandbox workspace-write \
      --cd "$fixture" -c shell_environment_policy.inherit=all \
      -c "shell_environment_policy.set=$shell_policy" \
      --output-last-message "$response" - \
      <"$prompt" >"$stdout_log" 2>"$stderr_log"
  fi
}

copy_artifacts() {
  case_name=$1
  fixture=$2
  response=$3
  stdout_log=$4
  stderr_log=$5
  [ -n "$OUTPUT_DIR" ] || return 0
  mkdir -p "$OUTPUT_DIR"
  cp "$response" "$OUTPUT_DIR/$case_name.response.txt"
  cp "$stdout_log" "$OUTPUT_DIR/$case_name.stdout.log"
  cp "$stderr_log" "$OUTPUT_DIR/$case_name.stderr.log"
  cp "$fixture/calls.log" "$OUTPUT_DIR/$case_name.calls.log"
  git -C "$fixture" status --short >"$OUTPUT_DIR/$case_name.git-status.txt"
  find "$fixture/.worktrees" -mindepth 1 -maxdepth 1 -type d -print \
    2>/dev/null >"$OUTPUT_DIR/$case_name.worktrees.txt" || true
}

in_place_fixture="$EVAL_ROOT/in-place-docs"
prepare_fixture "$in_place_fixture"
in_place_prompt="$EVAL_ROOT/in-place.prompt"
cat >"$in_place_prompt" <<'PROMPT'
Add one concise bullet under a new `## Architecture` heading in README.md.
This is a small, localized, reversible documentation edit. The current clean
worktree is the intended base, no other agent or task is writing here, no
independent branch, commit, PR, merge, or handoff is needed, and validation is
bounded with no persistent resources. Complete the edit and verify it.
PROMPT
in_place_response="$EVAL_ROOT/in-place.response"
in_place_stdout="$EVAL_ROOT/in-place.stdout"
in_place_stderr="$EVAL_ROOT/in-place.stderr"
printf 'diagnostic: running Codex in-place documentation scenario\n' >&2
run_codex "$in_place_fixture" "$in_place_prompt" "$in_place_response" \
  "$in_place_stdout" "$in_place_stderr"
grep -Fq '## Architecture' "$in_place_fixture/README.md" || {
  printf 'error: Codex did not complete the in-place documentation edit\n' >&2
  exit 1
}
if grep -Eq '(^| )create( |$)' "$in_place_fixture/calls.log"; then
  printf 'error: Codex invoked wt-axi create for the qualifying in-place task\n' >&2
  exit 1
fi
[ ! -d "$in_place_fixture/.worktrees" ] || {
  printf 'error: qualifying in-place task created .worktrees\n' >&2
  exit 1
}
copy_artifacts in-place "$in_place_fixture" "$in_place_response" \
  "$in_place_stdout" "$in_place_stderr"

required_fixture="$EVAL_ROOT/required-worktree"
prepare_fixture "$required_fixture"
required_prompt="$EVAL_ROOT/required.prompt"
cat >"$required_prompt" <<'PROMPT'
Prepare a documentation change that must be delivered through its own branch
and pull request. The user explicitly requires a separate task worktree. Set up
the required isolation according to the loaded instructions, then stop before
editing, committing, pushing, or opening the PR.
PROMPT
required_response="$EVAL_ROOT/required.response"
required_stdout="$EVAL_ROOT/required.stdout"
required_stderr="$EVAL_ROOT/required.stderr"
printf 'diagnostic: running Codex required-worktree scenario\n' >&2
run_codex "$required_fixture" "$required_prompt" "$required_response" \
  "$required_stdout" "$required_stderr"
copy_artifacts required-worktree "$required_fixture" "$required_response" \
  "$required_stdout" "$required_stderr"
status_line=$(grep -nE '(^| )status( |$)' "$required_fixture/calls.log" |
  head -n1 | cut -d: -f1)
[ -n "$status_line" ] || {
  printf 'error: Codex did not invoke wt-axi status before creation\n' >&2
  exit 1
}
create_line=$(grep -nE '(^| )create( |$)' "$required_fixture/calls.log" |
  head -n1 | cut -d: -f1)
[ -n "$create_line" ] || {
  printf 'error: Codex did not invoke wt-axi create for the required task\n' >&2
  exit 1
}
[ "$status_line" -lt "$create_line" ] || {
  printf 'error: Codex invoked wt-axi create before status\n' >&2
  exit 1
}
required_path=$(find "$required_fixture/.worktrees" -mindepth 1 -maxdepth 1 \
  -type d -name 'required-worktree-wt-*' -print -quit 2>/dev/null || true)
[ -n "$required_path" ] || {
  printf 'error: Codex did not create a platform-named worktree path\n' >&2
  exit 1
}
printf 'modelBehaviorEval:\n'
printf '  provider: "codex"\n'
printf '  model: "%s"\n' "${MODEL_OVERRIDE:-default}"
printf '  inPlaceEditCompleted: true\n'
printf '  inPlaceCreateCalls: 0\n'
printf '  requiredStatusCalled: true\n'
printf '  requiredCreateCalled: true\n'
printf '  requiredPath: "%s"\n' "$required_path"
