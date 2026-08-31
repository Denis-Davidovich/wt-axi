---
name: wt-axi
description: Safely create, inspect, or retire Git worktrees for agent tasks with platform naming, machine-readable preflight, merge proof, and guarded cleanup. Use for worktree lifecycle requests; do not use for ordinary branch-only Git operations.
---

# wt-axi

Use `wt-axi` as the project-agnostic lifecycle boundary. It delegates Git worktree primitives to the pinned upstream engine and adds platform naming, TOON output, and retirement safety gates.

This skill does not grant cleanup authority. Create a worktree only within an implementation task. Retire one only after explicit cleanup intent or a terminal workflow with proven merge. Never bypass wt-axi with raw removal commands.

## Commands

- `wt-axi create --task-slug <slug> --branch <branch> [--from <ref>]` — Create a platform-named secondary worktree through GTR. Flags: --task-slug <slug> (required); --branch <branch> (required); --from <ref> (default origin/main).
- `wt-axi status [--target <ref>]` — Inspect all registered worktrees and emit the retirement decision fields. Flags: --target <ref> (default origin/main).
- `wt-axi retire --path <path> [--target <ref>] [--delete-remote-branch]` — Safely retire one merged secondary worktree after complete preflight. Flags: --path <path> (required); --target <ref> (default origin/main); --delete-remote-branch (explicit opt-in).
- `wt-axi doctor` — Check Git, pinned GTR, TOON contract, repository layout, and adapter trust. Flags: (no flags).
- `wt-axi version` — Print the wt-axi version. Flags: (no flags).

## Workflow

1. Run `wt-axi status` before creating or retiring anything. Read `retireSafe`; do not infer safety from a clean-looking folder.
2. For creation, derive a short lowercase kebab-case task slug and run `wt-axi create --task-slug <slug> --branch <branch>`. Work only in the returned `<repo>/.worktrees/<project>-wt-<task-slug>` path.
3. For retirement, leave the target worktree first. Run `wt-axi retire --path <path>` and preserve the remote branch by default.
4. Add `--delete-remote-branch` only when the user explicitly asked to delete that remote branch. Do not treat a general cleanup request as remote deletion consent.
5. On any non-zero result, report the structured error and follow its help field. Never retry with force or run upstream hooks directly.

## Safety contract

- `primary`: Never retire the primary worktree.
- `dirty`: Never retire a worktree with staged, unstaged, or untracked changes.
- `detached`: Never retire a detached worktree.
- `current`: Never retire the worktree containing the caller's current directory.
- `active-agent`: Never retire while the trusted adapter reports an active agent or active/unknown runtime.
- `unmerged`: Refresh the target ref and require ancestry or a merged provider record before mutation.
- `adapter-order`: Run trusted pre-retire only after all read-only safety gates pass.
- `remote-branch`: Delete a remote branch only with explicit --delete-remote-branch opt-in.
- `force`: Do not expose or use a force-retirement path.

## Exit codes

- `0` — success, including idempotent no-op.
- `1` — operational or safety error.
- `2` — usage error; dependency calls have not started.

## Missing installation

If `wt-axi` is unavailable, report that installation is required and point to the repository README. Do not install software or alter global agent configuration unless the user requested setup.
