# Platform worktree convention

- This convention controls naming and placement only after the user,
  repository instructions, or an applicable skill has determined that a
  separate worktree is needed. It does not itself require a worktree. For
  read-only work or a qualifying small in-place change, stay in the current
  worktree.
- When a task-specific Git worktree is needed, create it inside the current
  repository at `<repo-root>/.worktrees/<project>-wt-<task-slug>`.
- `<project>` is the current project/application identifier. By default use the
  basename of the repository root; when the repository defines an application
  name or local domain, use its first label (`planner.docker` -> `planner`).
- Use a short lowercase kebab-case `<task-slug>`. Do not copy a branch namespace
  such as `feat/`, `fix/`, or `codex/` into the directory name, and do not create
  agent-specific nesting such as `.worktrees/codex/` or `.claude/worktrees/`.
- When a repository-local instruction uses a generic placeholder such as
  `.worktrees/<slug>`, treat `<slug>` as `<project>-wt-<task-slug>` from this
  convention. A generic local placeholder does not replace the platform naming
  format; only an explicit, concrete repository-specific naming rule does.
- Before any creation, resolve the repository root and inspect
  `git worktree list`. Repository-local `AGENTS.md` instructions may add stricter
  placement, isolation, startup, and cleanup requirements.
