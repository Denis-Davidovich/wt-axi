#!/usr/bin/env bash
# shellcheck disable=SC2016

set -eu
CDPATH=''

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wt-axi-tests.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT HUP INT TERM
PASS_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s - %s\n' "$PASS_COUNT" "$1"
}

fail() {
  printf 'not ok %s - %s\n' "$((PASS_COUNT + 1))" "$1" >&2
  exit 1
}

assert_contains() {
  file=$1
  pattern=$2
  label=$3
  grep -Eq -- "$pattern" "$file" || fail "$label"
}

assert_not_contains() {
  file=$1
  pattern=$2
  label=$3
  if grep -Eq -- "$pattern" "$file"; then fail "$label"; fi
}

run_expect() {
  expected=$1
  out=$2
  err=$3
  shift 3
  set +e
  "$@" >"$out" 2>"$err"
  actual=$?
  set -e
  [ "$actual" -eq "$expected" ] || fail "expected exit $expected, got $actual: $*"
}

validate_toon() {
  toon_file=$1
  if command -v npx >/dev/null 2>&1; then
    npx -y @toon-format/cli "$toon_file" >/dev/null 2>"$TEST_ROOT/toon.err" || {
      sed -n '1,120p' "$TEST_ROOT/toon.err" >&2
      fail "invalid TOON: $toon_file"
    }
  fi
}

chmod +x "$ROOT/bin/wt-axi" "$ROOT/scripts/"*.sh "$ROOT/tests/fixtures/adapter.sh"

"$ROOT/scripts/generate-skill.sh" --check >/dev/null
pass "generated skill matches CLI contract"

if "$ROOT/scripts/generate-skill.sh" --check --skill-file "$ROOT/tests/fixtures/stale/SKILL.md" >/dev/null 2>&1; then
  fail "stale skill fixture must fail"
fi
pass "stale skill fixture is rejected"

unknown_out="$TEST_ROOT/unknown.toon"
unknown_err="$TEST_ROOT/unknown.err"
run_expect 2 "$unknown_out" "$unknown_err" "$ROOT/bin/wt-axi" status --bogus
assert_contains "$unknown_out" 'code: "usage"' "unknown flag has structured usage error"
validate_toon "$unknown_out"
pass "unknown flags fail before dependency work"

help_out="$TEST_ROOT/help.toon"
"$ROOT/bin/wt-axi" --help >"$help_out"
validate_toon "$help_out"
assert_contains "$help_out" 'commands\[5\]' "top-level help lists all MVP commands"
pass "help is concise valid TOON"

if grep -ERn -i 'planner|docker[[:space:]-]*compose|volume[[:space:]_-]*names?' \
  "$ROOT/bin" "$ROOT/contract" "$ROOT/scripts" "$ROOT/tests/fixtures/adapter.sh" "$ROOT/skills/wt-axi" >/dev/null; then
  fail "core, fixture, or skill contains consumer-specific terms"
fi
pass "core and skill are consumer-agnostic"

if [ -n "${GTR_SOURCE:-}" ]; then
  gtr_source=$GTR_SOURCE
elif command -v git-gtr >/dev/null 2>&1; then
  gtr_source=$(cd -- "$(dirname -- "$(command -v git-gtr)")/.." && pwd -P)
else
  gtr_source="$TEST_ROOT/git-worktree-runner"
  git clone --quiet --depth 1 --branch v2.11.0 https://github.com/coderabbitai/git-worktree-runner.git "$gtr_source"
fi
[ -x "$gtr_source/bin/git-gtr" ] || fail "pinned GTR source not executable"

fixture="$TEST_ROOT/fixture"
origin="$TEST_ROOT/origin.git"
git init --bare "$origin" >/dev/null
git clone --quiet "$origin" "$fixture"
git -C "$fixture" config user.name 'wt-axi tests'
git -C "$fixture" config user.email 'wt-axi@example.invalid'
mkdir -p "$fixture/scripts"
cp "$ROOT/tests/fixtures/adapter.sh" "$fixture/scripts/wt-axi-adapter"
chmod +x "$fixture/scripts/wt-axi-adapter"
printf '/.worktrees/\n' >"$fixture/.gitignore"
git -C "$fixture" add .gitignore scripts/wt-axi-adapter
git -C "$fixture" commit -m init >/dev/null
git -C "$fixture" branch -M main
git -C "$fixture" push --quiet -u origin main
adapter_sha=$(shasum -a 256 "$fixture/scripts/wt-axi-adapter" | awk '{print $1}')
git -C "$fixture" config --local wt-axi.project sample
git -C "$fixture" config --local wt-axi.adapter.path scripts/wt-axi-adapter
git -C "$fixture" config --local wt-axi.adapter.sha256 "$adapter_sha"
export PATH="$ROOT/bin:$gtr_source/bin:$PATH"

make_branch() {
  branch_name=$1
  folder_name=$2
  merge_it=$3
  git -C "$fixture" worktree add -q -b "$branch_name" "$fixture/.worktrees/$folder_name" main
  git -C "$fixture/.worktrees/$folder_name" commit --allow-empty -m "$branch_name" >/dev/null
  git -C "$fixture/.worktrees/$folder_name" push --quiet -u origin "$branch_name"
  if [ "$merge_it" = true ]; then
    git -C "$fixture" merge --no-ff -m "merge $branch_name" "$branch_name" >/dev/null
    git -C "$fixture" push --quiet origin main
  fi
}

create_out="$TEST_ROOT/create.toon"
create_err="$TEST_ROOT/create.err"
(cd "$fixture" && wt-axi create --task-slug created --branch feat/created) >"$create_out" 2>"$create_err"
validate_toon "$create_out"
assert_contains "$create_out" 'sample-wt-created' "create uses platform folder"
[ -d "$fixture/.worktrees/sample-wt-created" ] || fail "create worktree path missing"
pass "create delegates to GTR with platform naming"

make_branch feat/merged-default sample-wt-merged-default true
status_out="$TEST_ROOT/status.toon"
(cd "$fixture" && wt-axi status) >"$status_out" 2>"$TEST_ROOT/status.err"
validate_toon "$status_out"
assert_contains "$status_out" 'worktrees\[[0-9]+\]\{path,branch,dirty,merged,runtimeState,retireSafe\}' "status schema"
assert_contains "$status_out" 'feat/merged-default.*,false,true,"inactive",true' "merged worktree is safe"
assert_not_contains "$status_out" 'Fetching|Checking|diagnostic' "stdout contains no progress"
pass "status emits required TOON fields only"

primary_out="$TEST_ROOT/primary.toon"
run_expect 1 "$primary_out" "$TEST_ROOT/primary.err" bash -c 'cd "$1" && wt-axi retire --path "$1"' _ "$fixture"
assert_contains "$primary_out" 'unsafe_primary' "primary refusal"
pass "primary worktree is rejected"

make_branch feat/current sample-wt-current true
current_path="$fixture/.worktrees/sample-wt-current"
current_out="$TEST_ROOT/current.toon"
run_expect 1 "$current_out" "$TEST_ROOT/current.err" bash -c 'cd "$1" && wt-axi retire --path "$1"' _ "$current_path"
assert_contains "$current_out" 'unsafe_current' "current refusal"
pass "current worktree is rejected"

make_branch feat/dirty sample-wt-dirty true
dirty_path="$fixture/.worktrees/sample-wt-dirty"
touch "$dirty_path/untracked.txt"
dirty_out="$TEST_ROOT/dirty.toon"
run_expect 1 "$dirty_out" "$TEST_ROOT/dirty.err" bash -c 'cd "$1" && wt-axi retire --path "$2"' _ "$fixture" "$dirty_path"
assert_contains "$dirty_out" 'unsafe_dirty' "dirty refusal"
rm -f -- "$dirty_path/untracked.txt"
pass "dirty worktree is rejected before adapter"

detached_path="$fixture/.worktrees/sample-wt-detached"
git -C "$fixture" worktree add -q --detach "$detached_path" main
detached_out="$TEST_ROOT/detached.toon"
run_expect 1 "$detached_out" "$TEST_ROOT/detached.err" bash -c 'cd "$1" && wt-axi retire --path "$2"' _ "$fixture" "$detached_path"
assert_contains "$detached_out" 'unsafe_detached' "detached refusal"
pass "detached worktree is rejected"

make_branch feat/unmerged sample-wt-unmerged false
unmerged_path="$fixture/.worktrees/sample-wt-unmerged"
unmerged_out="$TEST_ROOT/unmerged.toon"
run_expect 1 "$unmerged_out" "$TEST_ROOT/unmerged.err" bash -c 'cd "$1" && wt-axi retire --path "$2"' _ "$fixture" "$unmerged_path"
assert_contains "$unmerged_out" 'unsafe_unmerged' "unmerged refusal"
pass "unmerged worktree is rejected"

make_branch feat/active sample-wt-active true
active_path="$fixture/.worktrees/sample-wt-active"
active_marker="$TEST_ROOT/active-marker"
active_out="$TEST_ROOT/active.toon"
run_expect 1 "$active_out" "$TEST_ROOT/active.err" env WT_AXI_FIXTURE_ACTIVE_AGENT=true WT_AXI_FIXTURE_MARKER="$active_marker" bash -c 'cd "$1" && wt-axi retire --path "$2"' _ "$fixture" "$active_path"
assert_contains "$active_out" 'unsafe_active_agent' "active-agent refusal"
[ ! -e "$active_marker" ] || fail "adapter mutated before active-agent refusal"
pass "active agent is rejected before pre-retire"

default_marker="$TEST_ROOT/default-marker"
retire_out="$TEST_ROOT/retire.toon"
WT_AXI_FIXTURE_MARKER="$default_marker" bash -c 'cd "$1" && wt-axi retire --path "$2"' _ "$fixture" "$fixture/.worktrees/sample-wt-merged-default" >"$retire_out" 2>"$TEST_ROOT/retire.err"
validate_toon "$retire_out"
[ -s "$default_marker" ] || fail "trusted pre-retire adapter did not run"
[ ! -d "$fixture/.worktrees/sample-wt-merged-default" ] || fail "merged worktree remains"
git --git-dir="$origin" show-ref --verify --quiet refs/heads/feat/merged-default || fail "remote branch should be preserved"
pass "safe retire runs adapter and preserves remote branch by default"

make_branch feat/remote-delete sample-wt-remote-delete true
remote_marker="$TEST_ROOT/remote-marker"
WT_AXI_FIXTURE_MARKER="$remote_marker" bash -c 'cd "$1" && wt-axi retire --path "$2" --delete-remote-branch' _ "$fixture" "$fixture/.worktrees/sample-wt-remote-delete" >"$TEST_ROOT/remote.toon" 2>"$TEST_ROOT/remote.err"
if git --git-dir="$origin" show-ref --verify --quiet refs/heads/feat/remote-delete; then fail "remote branch was not deleted with explicit flag"; fi
pass "explicit remote branch deletion works"

install_prefix="$TEST_ROOT/prefix"
PATH="/usr/bin:/bin" "$ROOT/scripts/install.sh" --prefix "$install_prefix" --gtr-source "$gtr_source" >"$TEST_ROOT/install.toon"
[ -x "$install_prefix/bin/wt-axi" ] || fail "installed wt-axi missing"
PATH="$install_prefix/bin:/usr/bin:/bin" bash -c 'cd "$1" && wt-axi doctor' _ "$fixture" >"$TEST_ROOT/doctor.toon"
validate_toon "$TEST_ROOT/doctor.toon"
PATH="/usr/bin:/bin" "$ROOT/scripts/uninstall.sh" --prefix "$install_prefix" >"$TEST_ROOT/uninstall.toon"
[ ! -e "$install_prefix/bin/wt-axi" ] || fail "uninstall left wt-axi link"
pass "install, doctor, and uninstall smoke passes"

printf '1..%s\n' "$PASS_COUNT"
