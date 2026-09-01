#!/usr/bin/env bash

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
OUTPUT_DIR=

usage() {
  printf '%s\n' 'usage: evals/run-model-matrix.sh --output-dir <path>'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-dir)
      [ "$#" -ge 2 ] || { printf 'error: --output-dir requires a path\n' >&2; exit 2; }
      OUTPUT_DIR=$2
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'error: unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$OUTPUT_DIR" ] || { printf 'error: --output-dir is required\n' >&2; exit 2; }
mkdir -p "$OUTPUT_DIR"

matrix=$(mktemp "${TMPDIR:-/tmp}/wt-axi-model-matrix.XXXXXX")
trap 'rm -f -- "$matrix"' EXIT HUP INT TERM
printf '%s\n' 'claude sonnet' 'claude opus' 'codex gpt-5.6-terra' 'codex gpt-5.6-sol' >"$matrix"

models_passed=0
models_requested=0
while read -r provider model; do
  models_requested=$((models_requested + 1))
  model_slug=$(printf '%s-%s' "$provider" "$model" | tr -c 'A-Za-z0-9._-' '-')
  printf 'diagnostic: running %s with %s\n' "$provider" "$model" >&2
  if "$ROOT/tests/model-decision-eval.sh" \
    --provider "$provider" --model "$model" --output-dir "$OUTPUT_DIR" \
    >"$OUTPUT_DIR/$model_slug.summary.toon"; then
    models_passed=$((models_passed + 1))
  fi
done <"$matrix"

printf 'modelMatrix:\n'
printf '  modelsRequested: %s\n' "$models_requested"
printf '  modelsPassed: %s\n' "$models_passed"
printf '  scenariosPerModel: %s\n' "$(wc -l <"$ROOT/tests/fixtures/worktree-decision-cases.tsv" | tr -d ' ')"
printf '  outputDir: "%s"\n' "$OUTPUT_DIR"

[ "$models_passed" -eq "$models_requested" ]
