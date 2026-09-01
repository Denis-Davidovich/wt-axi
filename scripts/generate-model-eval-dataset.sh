#!/usr/bin/env bash

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
SOURCE="$ROOT/tests/fixtures/worktree-decision-cases.tsv"
TARGET="$ROOT/evals/worktree-decision-dataset.jsonl"
MODE='write'

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE='check'; shift ;;
    --output)
      [ "$#" -ge 2 ] || { printf 'error: --output requires a path\n' >&2; exit 2; }
      TARGET=$2
      shift 2
      ;;
    --help|-h)
      printf '%s\n' 'usage: scripts/generate-model-eval-dataset.sh [--check] [--output <path>]'
      exit 0
      ;;
    *) printf 'error: unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

generated=$(mktemp "${TMPDIR:-/tmp}/wt-axi-eval-dataset.XXXXXX")
trap 'rm -f -- "$generated"' EXIT HUP INT TERM

while IFS="$(printf '\t')" read -r case_id expected scenario; do
  escaped_id=$(json_escape "$case_id")
  escaped_expected=$(json_escape "$expected")
  escaped_scenario=$(json_escape "$scenario")
  printf '{"input":{"scenarioId":"%s","scenario":"%s"},"expectedOutput":{"decision":"%s"},"metadata":{"suite":"wt-axi-worktree-decision","source":"tests/fixtures/worktree-decision-cases.tsv"}}\n' \
    "$escaped_id" "$escaped_scenario" "$escaped_expected" >>"$generated"
done <"$SOURCE"

if [ "$MODE" = check ]; then
  if ! cmp -s "$generated" "$TARGET"; then
    printf 'error: generated model eval dataset is stale: %s\n' "$TARGET" >&2
    diff -u "$TARGET" "$generated" >&2 || true
    exit 1
  fi
  printf 'model_eval_dataset_sync: ok\n'
  exit 0
fi

mkdir -p "$(dirname -- "$TARGET")"
cp "$generated" "$TARGET"
printf 'generated: %s\n' "$TARGET"
