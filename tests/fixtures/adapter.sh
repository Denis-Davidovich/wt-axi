#!/usr/bin/env bash

set -eu

operation=${1:-}
if [ "$#" -gt 0 ]; then shift; fi

case "$operation" in
  status)
    [ "${1:-}" = --worktree ] && [ "$#" -eq 2 ] || exit 2
    printf 'runtimeState\t%s\n' "${WT_AXI_FIXTURE_RUNTIME_STATE:-inactive}"
    printf 'activeAgent\t%s\n' "${WT_AXI_FIXTURE_ACTIVE_AGENT:-false}"
    ;;
  pre-retire)
    worktree=
    branch=
    target=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --worktree) worktree=$2; shift 2 ;;
        --branch) branch=$2; shift 2 ;;
        --target) target=$2; shift 2 ;;
        *) exit 2 ;;
      esac
    done
    [ -n "$worktree" ] && [ -n "$branch" ] && [ -n "$target" ] || exit 2
    if [ -n "${WT_AXI_FIXTURE_MARKER:-}" ]; then
      printf '%s\t%s\t%s\n' "$worktree" "$branch" "$target" >>"$WT_AXI_FIXTURE_MARKER"
    fi
    ;;
  *) exit 2 ;;
esac
