#!/usr/bin/env bash

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
SKILL="$ROOT/skills/wt-axi/SKILL.md"
CASES="$ROOT/tests/fixtures/worktree-decision-cases.tsv"
PROVIDER=all
MODEL_OVERRIDE=
OUTPUT_DIR=

usage() {
  printf '%s\n' 'usage: tests/model-decision-eval.sh [--provider codex|claude|opencode|all] [--model <model>] [--output-dir <path>]'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --provider)
      [ "$#" -ge 2 ] || { printf 'error: --provider requires a value\n' >&2; exit 2; }
      PROVIDER=$2
      shift 2
      ;;
    --model)
      [ "$#" -ge 2 ] || { printf 'error: --model requires a value\n' >&2; exit 2; }
      MODEL_OVERRIDE=$2
      shift 2
      ;;
    --output-dir)
      [ "$#" -ge 2 ] || { printf 'error: --output-dir requires a path\n' >&2; exit 2; }
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

case "$PROVIDER" in
  codex|claude|opencode|all) ;;
  *) printf 'error: unsupported provider: %s\n' "$PROVIDER" >&2; usage >&2; exit 2 ;;
esac
[ "$PROVIDER" != all ] || [ -z "$MODEL_OVERRIDE" ] || {
  printf 'error: --model requires one explicit provider\n' >&2
  exit 2
}

[ -f "$SKILL" ] || { printf 'error: missing skill: %s\n' "$SKILL" >&2; exit 1; }
[ -f "$CASES" ] || { printf 'error: missing cases: %s\n' "$CASES" >&2; exit 1; }

EVAL_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wt-axi-model-eval.XXXXXX")
trap 'rm -rf -- "$EVAL_ROOT"' EXIT HUP INT TERM
PROMPT="$EVAL_ROOT/prompt.txt"

{
  printf '%s\n' 'This is a conformance evaluation. Do not modify files or use tools.'
  printf '%s\n' 'Apply the supplied wt-axi skill exactly to every scenario.'
  printf '%s\n' 'Return one line per scenario and no omitted scenarios, using:'
  printf '%s\n\n' '<scenario-id><TAB><in-place|worktree>'
  printf '%s\n' '--- supplied SKILL.md ---'
  sed -n '1,120p' "$SKILL"
  printf '%s\n' '--- scenarios ---'
  while IFS="$(printf '\t')" read -r case_id _ case_text; do
    printf '%s: %s\n' "$case_id" "$case_text"
  done <"$CASES"
} >"$PROMPT"

run_codex() {
  response=$1
  stdout_log=$2
  stderr_log=$3
  selected_model=${MODEL_OVERRIDE:-${WT_AXI_EVAL_CODEX_MODEL:-}}
  if [ -n "$selected_model" ]; then
    codex exec --ignore-user-config --ephemeral --sandbox read-only \
      --skip-git-repo-check --cd "$EVAL_ROOT" \
      --model "$selected_model" --output-last-message "$response" - \
      <"$PROMPT" >"$stdout_log" 2>"$stderr_log"
  else
    codex exec --ignore-user-config --ephemeral --sandbox read-only \
      --skip-git-repo-check --cd "$EVAL_ROOT" \
      --output-last-message "$response" - \
      <"$PROMPT" >"$stdout_log" 2>"$stderr_log"
  fi
}

run_claude() {
  response=$1
  stdout_log=$2
  stderr_log=$3
  selected_model=${MODEL_OVERRIDE:-${WT_AXI_EVAL_CLAUDE_MODEL:-}}
  if [ -n "$selected_model" ]; then
    claude --print --safe-mode --no-session-persistence --permission-mode plan \
      --output-format text --model "$selected_model" \
      <"$PROMPT" >"$response" 2>"$stderr_log"
  else
    claude --print --safe-mode --no-session-persistence --permission-mode plan \
      --output-format text <"$PROMPT" >"$response" 2>"$stderr_log"
  fi
  : >"$stdout_log"
}

run_opencode() {
  response=$1
  stdout_log=$2
  stderr_log=$3
  prompt_text=$(sed -n '1,240p' "$PROMPT")
  selected_model=${MODEL_OVERRIDE:-${WT_AXI_EVAL_OPENCODE_MODEL:-}}
  if [ -n "$selected_model" ]; then
    opencode run --pure --dir "$EVAL_ROOT" --model "$selected_model" \
      "$prompt_text" >"$response" 2>"$stderr_log"
  else
    opencode run --pure --dir "$EVAL_ROOT" "$prompt_text" \
      >"$response" 2>"$stderr_log"
  fi
  : >"$stdout_log"
}

evaluate_response() {
  eval_provider=$1
  eval_response=$2
  eval_details=$3
  eval_passed=0
  eval_total=0
  printf 'scenario\texpected\tobserved\tpassed\n' >"$eval_details"

  while IFS="$(printf '\t')" read -r case_id expected _; do
    eval_total=$((eval_total + 1))
    observed=$(awk -v wanted="$case_id" '
      BEGIN { wanted=tolower(wanted); found=""; ambiguous=0 }
      {
        line=tolower($0)
        if (index(line, wanted) == 0) next
        has_in_place=(line ~ /in[-_ ]place/)
        has_worktree=(line ~ /worktree/)
        if (has_in_place && !has_worktree) value="in-place"
        else if (has_worktree && !has_in_place) value="worktree"
        else { ambiguous=1; next }
        if (found != "" && found != value) ambiguous=1
        found=value
      }
      END {
        if (ambiguous || found == "") print "invalid"
        else print found
      }
    ' "$eval_response")

    if [ "$observed" = "$expected" ]; then
      eval_passed=$((eval_passed + 1))
      case_passed=true
    else
      case_passed=false
      printf 'error: %s case %s expected %s, observed %s\n' \
        "$eval_provider" "$case_id" "$expected" "$observed" >&2
    fi
    printf '%s\t%s\t%s\t%s\n' \
      "$case_id" "$expected" "$observed" "$case_passed" >>"$eval_details"
  done <"$CASES"

  printf '%s\t%s\t%s\t%s\n' \
    "$eval_provider" "${MODEL_OVERRIDE:-default}" "$eval_passed" "$eval_total"
  [ "$eval_passed" -eq "$eval_total" ]
}

providers_requested=0
providers_passed=0
case_count=$(wc -l <"$CASES" | tr -d ' ')
results="$EVAL_ROOT/results.tsv"
: >"$results"

for current_provider in codex claude opencode; do
  if [ "$PROVIDER" != all ] && [ "$PROVIDER" != "$current_provider" ]; then
    continue
  fi
  providers_requested=$((providers_requested + 1))
  if ! command -v "$current_provider" >/dev/null 2>&1; then
    printf 'error: provider CLI is unavailable: %s\n' "$current_provider" >&2
    continue
  fi

  response="$EVAL_ROOT/$current_provider.response"
  stdout_log="$EVAL_ROOT/$current_provider.stdout"
  stderr_log="$EVAL_ROOT/$current_provider.stderr"
  detail_log="$EVAL_ROOT/$current_provider.details.tsv"
  printf 'diagnostic: evaluating %s with %s scenarios\n' \
    "$current_provider" "$case_count" >&2

  if "run_$current_provider" "$response" "$stdout_log" "$stderr_log"; then
    if evaluate_response "$current_provider" "$response" "$detail_log" >>"$results"; then
      providers_passed=$((providers_passed + 1))
    else
      printf 'diagnostic: %s response follows\n' "$current_provider" >&2
      sed -n '1,160p' "$response" >&2
    fi
  else
    printf 'error: %s invocation failed\n' "$current_provider" >&2
    sed -n '1,160p' "$stderr_log" >&2
  fi

  if [ -n "$OUTPUT_DIR" ] && [ -f "$response" ]; then
    mkdir -p "$OUTPUT_DIR"
    artifact_model=${MODEL_OVERRIDE:-default}
    artifact_slug=$(printf '%s-%s' "$current_provider" "$artifact_model" | tr -c 'A-Za-z0-9._-' '-')
    cp "$PROMPT" "$OUTPUT_DIR/$artifact_slug.prompt.txt"
    cp "$response" "$OUTPUT_DIR/$artifact_slug.response.txt"
    [ ! -f "$detail_log" ] || cp "$detail_log" "$OUTPUT_DIR/$artifact_slug.results.tsv"
  fi
done

printf 'modelDecisionEval:\n'
printf '  providersRequested: %s\n' "$providers_requested"
printf '  providersPassed: %s\n' "$providers_passed"
printf '  scenariosPerProvider: %s\n' "$case_count"
results_count=$(wc -l <"$results" | tr -d ' ')
printf '  results[%s]{provider,model,passed,total}:\n' "$results_count"
while IFS="$(printf '\t')" read -r result_provider result_model result_passed result_total; do
  printf '    "%s","%s",%s,%s\n' \
    "$result_provider" "$result_model" "$result_passed" "$result_total"
done <"$results"

[ "$providers_passed" -eq "$providers_requested" ]
