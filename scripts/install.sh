#!/usr/bin/env bash

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
PREFIX=${HOME}/.local
GTR_SOURCE=
GTR_VERSION=v2.11.0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -ge 2 ] || { printf 'error: --prefix requires a path\n'; exit 2; }
      PREFIX=$2; shift 2 ;;
    --gtr-source)
      [ "$#" -ge 2 ] || { printf 'error: --gtr-source requires a path\n'; exit 2; }
      GTR_SOURCE=$2; shift 2 ;;
    --help|-h)
      printf 'usage: scripts/install.sh [--prefix <absolute-path>] [--gtr-source <checkout>]\n'
      exit 0 ;;
    *) printf 'error: unknown flag: %s\n' "$1"; exit 2 ;;
  esac
done

case "$PREFIX" in /*) ;; *) printf 'error: --prefix must be absolute\n'; exit 2 ;; esac
[ "$PREFIX" != / ] || { printf 'error: refusing prefix /\n'; exit 2; }

VERSION=$(sed -n '1p' "$ROOT/VERSION")
INSTALL_ROOT="$PREFIX/lib/wt-axi/$VERSION"
BIN_DIR="$PREFIX/bin"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/wt-axi-install.XXXXXX")
trap 'rm -rf -- "$STAGE"' EXIT HUP INT TERM

mkdir -p "$STAGE/root" "$BIN_DIR" "$(dirname "$INSTALL_ROOT")"
for item in bin contract skills VERSION DEPENDENCIES.md LICENSE; do
  cp -R "$ROOT/$item" "$STAGE/root/"
done

if [ -e "$INSTALL_ROOT" ]; then
  rm -rf -- "$INSTALL_ROOT"
fi
mv "$STAGE/root" "$INSTALL_ROOT"

link_binary() {
  source_path=$1
  link_path=$2
  if [ -e "$link_path" ] && [ ! -L "$link_path" ]; then
    printf 'error: refusing to replace non-symlink %s\n' "$link_path"
    exit 1
  fi
  [ ! -L "$link_path" ] || rm -f -- "$link_path"
  ln -s "$source_path" "$link_path"
}

chmod +x "$INSTALL_ROOT/bin/wt-axi"
link_binary "$INSTALL_ROOT/bin/wt-axi" "$BIN_DIR/wt-axi"

GTR_RESULT=existing
if ! command -v git-gtr >/dev/null 2>&1; then
  GTR_DEST="$INSTALL_ROOT/vendor/git-worktree-runner"
  mkdir -p "$INSTALL_ROOT/vendor"
  if [ -n "$GTR_SOURCE" ]; then
    [ -x "$GTR_SOURCE/bin/git-gtr" ] || { printf 'error: invalid --gtr-source checkout\n'; exit 1; }
    cp -R "$GTR_SOURCE" "$GTR_DEST"
  else
    git clone --quiet --depth 1 --branch "$GTR_VERSION" https://github.com/coderabbitai/git-worktree-runner.git "$GTR_DEST"
  fi
  chmod +x "$GTR_DEST/bin/git-gtr"
  link_binary "$GTR_DEST/bin/git-gtr" "$BIN_DIR/git-gtr"
  GTR_RESULT=installed
fi

printf 'install:\n'
printf '  version: "%s"\n' "$VERSION"
printf '  prefix: "%s"\n' "$PREFIX"
printf '  binary: "%s"\n' "$BIN_DIR/wt-axi"
printf '  gtr: "%s"\n' "$GTR_RESULT"
