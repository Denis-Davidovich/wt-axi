# Dependency decision

Research gate:
[`01a0550c-92bf-72b5-a777-bf44c2b2a901`](https://planner.monopoly-gold.com/app#project/wt-axi/goal/01a0550c-92bf-72b5-a777-bf44c2b2a901)
(accepted 2026-08-31).

Decision: **thin facade**.

Runtime engine:

- repository: <https://github.com/coderabbitai/git-worktree-runner>
- version: `v2.11.0`
- release: <https://github.com/coderabbitai/git-worktree-runner/releases/tag/v2.11.0>
- license: Apache-2.0

GTR owns worktree creation/removal primitives, registered inventory, provider
semantics, and its hook trust implementation. wt-axi owns only platform naming,
TOON, ordered safety preflight, active-agent/runtime adapter handling, and
explicit branch-deletion policy.

Known gaps are solvable by configuration, this wrapper, or a future upstream
structured-clean contribution. A fork, modified upstream copy, or new Git
engine is prohibited without a new evidence-backed decision record.
