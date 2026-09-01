---
name: wt-axi
description: Safely create, inspect, and retire Git worktrees across an agent task lifecycle with platform naming, machine-readable preflight, merge proof, and guarded terminal cleanup. Use when implementation needs a task worktree, when auditing worktrees, or when completed work should retire its local worktree; do not use for ordinary branch-only Git operations.
---

# wt-axi

Use `wt-axi` as the project-agnostic lifecycle boundary. It delegates Git worktree primitives to the pinned upstream engine and adds platform naming, TOON output, and retirement safety gates.

Do not create a worktree for read-only work. For implementation, decide whether isolation is needed before invoking `wt-axi create`. When a task uses a task-specific worktree, a successfully completed terminal workflow should retire it after delivery and merge are proven, unless the user asked to preserve it. This terminal cleanup does not authorize remote-branch deletion. Never bypass wt-axi with raw removal commands.

## Worktree decision

A separate worktree is optional only when every condition below is true:

- Neither the user nor repository instructions require a separate worktree.
- The change is small, localized, and reversible; it does not include dependency changes, schema or data migrations, or bulk-generated output.
- The current worktree is the intended base, and the files to edit contain no unrelated changes.
- No other agent or task will write to the repository concurrently.
- The task needs no independent branch, commit, pull request, merge, or handoff.
- Validation is bounded and does not require persistent services or scoped runtime resources.

If any condition is false or unknown, use a task-specific worktree. Typical in-place tasks are a typo, wording correction, or similarly local config edit. Use a worktree for a feature, cross-cutting bug fix, refactor, migration, dependency update, bulk generation, parallel-agent work, or any task requiring independent delivery.

## Commands

- `wt-axi create --task-slug <slug> --branch <branch> [--from <ref>]` — Create a platform-named secondary worktree through GTR. Flags: --task-slug <slug> (required); --branch <branch> (required); --from <ref> (default origin/main).
- `wt-axi status [--target <ref>]` — Inspect all registered worktrees and emit the retirement decision fields. Flags: --target <ref> (default origin/main).
- `wt-axi retire --path <path> [--target <ref>] [--delete-remote-branch]` — Safely retire one merged secondary worktree after complete preflight. Flags: --path <path> (required); --target <ref> (default origin/main); --delete-remote-branch (explicit opt-in).
- `wt-axi doctor` — Check Git, pinned GTR, TOON contract, repository layout, and adapter trust. Flags: (no flags).
- `wt-axi version` — Print the wt-axi version. Flags: (no flags).

## Workflow

1. Classify the task with the worktree decision above. For read-only or qualifying in-place work, stay in the current worktree and do not invoke create or retirement.
2. When isolation is needed, run `wt-axi status`, derive a short lowercase kebab-case task slug, and create the task worktree with `wt-axi create --task-slug <slug> --branch <branch>`. Work only in the returned `<repo>/.worktrees/<project>-wt-<task-slug>` path.
3. Do not run retirement merely because a session started or while implementation, review, delivery, or merge work remains active.
4. At successful terminal completion, leave the task worktree, return to the primary worktree, and run `wt-axi status --target <ref>`. Read `retireSafe`; do not infer safety from a clean-looking folder.
5. When `retireSafe` is true, run `wt-axi retire --path <path> --target <ref>` as the normal final local cleanup. When it is false, preserve the worktree and report the exact blocker.
6. Preserve the remote branch by default. Add `--delete-remote-branch` only when the user explicitly asked to delete that remote branch; terminal completion alone is not consent.
7. On any non-zero result, report the structured error and follow its help field. Never retry with force or run upstream hooks directly.

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
