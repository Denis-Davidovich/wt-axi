#!/usr/bin/env bash

set -eu

PREFIX=${HOME}/.local
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -ge 2 ] || { printf 'error: --prefix requires a path\n'; exit 2; }
      PREFIX=$2; shift 2 ;;
    --help|-h) printf 'usage: scripts/uninstall.sh [--prefix <absolute-path>]\n'; exit 0 ;;
    *) printf 'error: unknown flag: %s\n' "$1"; exit 2 ;;
  esac
done
case "$PREFIX" in /*) ;; *) printf 'error: --prefix must be absolute\n'; exit 2 ;; esac
[ "$PREFIX" != / ] || { printf 'error: refusing prefix /\n'; exit 2; }

WT_LINK="$PREFIX/bin/wt-axi"
GTR_LINK="$PREFIX/bin/git-gtr"
INSTALL_BASE="$PREFIX/lib/wt-axi"
WT_RESULT=absent
GTR_RESULT=preserved

if [ -L "$WT_LINK" ]; then
  wt_target=$(readlink "$WT_LINK")
  case "$wt_target" in "$INSTALL_BASE"/*/bin/wt-axi) rm -f -- "$WT_LINK"; WT_RESULT=removed ;; *) printf 'error: wt-axi symlink is not managed by this prefix\n'; exit 1 ;; esac
fi
if [ -L "$GTR_LINK" ]; then
  gtr_target=$(readlink "$GTR_LINK")
  case "$gtr_target" in "$INSTALL_BASE"/*/vendor/git-worktree-runner/bin/git-gtr) rm -f -- "$GTR_LINK"; GTR_RESULT=removed ;; esac
fi
if [ -d "$INSTALL_BASE" ]; then rm -rf -- "$INSTALL_BASE"; fi

printf 'uninstall:\n'
printf '  wtAxi: "%s"\n' "$WT_RESULT"
printf '  gtr: "%s"\n' "$GTR_RESULT"
printf '  prefix: "%s"\n' "$PREFIX"
