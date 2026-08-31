# wt-axi

`wt-axi` is a small, agent-facing safety and machine-output layer for Git
worktree lifecycle. It does not replace Git or implement a second worktree
engine. Version 0.1.1 delegates creation/removal to
[`git-worktree-runner` v2.11.0](https://github.com/coderabbitai/git-worktree-runner/releases/tag/v2.11.0)
and owns only platform naming, TOON output, ordered retirement preflight, and a
generic project-adapter boundary.

## Why it exists

The 2026-08-31 live check found 14 registered worktrees in a mature product
repository. Four clean secondary worktrees were already ancestors of
`origin/main`; provider-aware GTR dry-run found seven merged candidates,
including squash/rebase merges. A disposable macOS fixture also proved that a
trusted GTR `preRemove` hook can run before Git rejects a dirty worktree.

That ordering is the problem wt-axi solves: it rejects primary, dirty,
detached, current, active-agent, untrusted-adapter, and unmerged cases before
any project teardown or upstream removal.

## MVP

```sh
wt-axi status
wt-axi create --task-slug auth-fix --branch fix/auth
wt-axi retire --path .worktrees/myapp-wt-auth-fix
wt-axi retire --path .worktrees/myapp-wt-auth-fix --delete-remote-branch
wt-axi doctor
```

Stdout is TOON only. Progress and dependency diagnostics go to stderr. Every
operation is non-interactive; unknown flags fail before dependency calls.

## CLI install, update, uninstall

```sh
git clone --depth 1 --branch main https://github.com/Denis-Davidovich/wt-axi.git
./wt-axi/scripts/install.sh --prefix "$HOME/.local"

# update: pull and rerun the idempotent installer
git -C ./wt-axi pull --ff-only
./wt-axi/scripts/install.sh --prefix "$HOME/.local"

./wt-axi/scripts/uninstall.sh --prefix "$HOME/.local"
```

The installer fetches the pinned GTR tag only when `git gtr` is unavailable.
`$HOME/.local/bin` must be on `PATH`.

## Agent Skill install, update, uninstall

One command installs the same skill for Codex, Claude Code, and OpenCode:

```sh
npx -y skills add Denis-Davidovich/wt-axi --skill wt-axi --agent codex claude-code opencode -g -y
npx -y skills update wt-axi -g -y
npx -y skills remove wt-axi -g --agent codex claude-code opencode -y
```

The skill is project-agnostic. For implementation tasks that already authorize
a task-specific worktree, it creates the worktree at the start and treats
`status` followed by safe local `retire` as the normal terminal step after
delivery and merge are proven. It does not run retirement merely because a
session started. Remote-branch deletion still requires the explicit CLI flag
and explicit user intent; terminal completion alone is not consent.

## Platform naming

`create` always chooses:

```text
<repo>/.worktrees/<project>-wt-<task-slug>
```

`<project>` defaults to the repository basename (or its first dot-separated
label) and can be overridden with local Git config `wt-axi.project`.

## Trusted project adapter

A product may report runtime/agent state and tear down scoped resources without
putting product logic in wt-axi. Configure one tracked executable and pin its
SHA-256 in local Git config:

```sh
git config --local wt-axi.adapter.path scripts/wt-axi-adapter
git config --local wt-axi.adapter.sha256 "$(shasum -a 256 scripts/wt-axi-adapter | awk '{print $1}')"
```

The core calls `status` during read-only preflight, then calls `pre-retire` only
after every Git and active-agent gate passes. See
[docs/adapter-protocol.md](docs/adapter-protocol.md).

## Ownership and non-goals

| Owner | Responsibility |
|---|---|
| Native Git + GTR v2.11.0 | registered inventory, create/remove primitives, provider semantics, hook trust |
| wt-axi | naming, TOON, preflight ordering, explicit branch semantics, adapter verification |
| Consumer repository | runtime status/teardown implementation and its integration evidence |

Version 0.1.1 has no TUI, daemon, database, background scanner, session
manager, product adapter, product runtime commands, `--force` path, fork, or
copied upstream source.

## Development

```sh
./scripts/check.sh
./scripts/generate-skill.sh --check
```

The decision record is [DEPENDENCIES.md](DEPENDENCIES.md). The research gate is
the production Planner goal
[`01a0550c-92bf-72b5-a777-bf44c2b2a901`](https://planner.monopoly-gold.com/app#project/wt-axi/goal/01a0550c-92bf-72b5-a777-bf44c2b2a901).
