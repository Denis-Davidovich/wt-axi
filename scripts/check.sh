#!/usr/bin/env bash

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)

"$ROOT/scripts/generate-skill.sh" --check
"$ROOT/tests/run.sh"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT/bin/wt-axi" "$ROOT/scripts/"*.sh "$ROOT/tests/"*.sh "$ROOT/tests/fixtures/adapter.sh"
else
  printf 'diagnostic: shellcheck not installed; CI enforces it\n' >&2
fi

printf 'checks: ok\n'
