#!/usr/bin/env bash

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)

"$ROOT/scripts/generate-skill.sh" --check
"$ROOT/scripts/generate-model-eval-dataset.sh" --check
"$ROOT/tests/run.sh"

if [ "${WT_AXI_RUN_MODEL_EVAL:-0}" = 1 ]; then
  "$ROOT/tests/model-decision-eval.sh" --provider all
fi

if [ "${WT_AXI_RUN_BEHAVIOR_EVAL:-0}" = 1 ]; then
  "$ROOT/tests/model-behavior-eval.sh"
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT/bin/wt-axi" "$ROOT/scripts/"*.sh "$ROOT/tests/"*.sh "$ROOT/tests/fixtures/adapter.sh"
else
  printf 'diagnostic: shellcheck not installed; CI enforces it\n' >&2
fi

printf 'checks: ok\n'
