# wt-axi repository instructions

- Keep implementation work that needs isolation in
  `.worktrees/wt-axi-wt-<task-slug>`. An in-place edit is allowed only when the
  change is small, localized, and reversible; the current worktree is the
  intended base; target files have no unrelated edits; there are no parallel
  writers; no independent branch, commit, PR, merge, or handoff is needed; and
  the task has no dependency changes, migrations, bulk generation, or
  persistent runtime resources. Explicit user requirements take precedence. If
  any condition is false or unknown, use a worktree.
- Maintain Bash 3.2 compatibility; macOS ships Bash 3.2.
- Keep stdout valid TOON. Diagnostics and wrapped-tool output belong on stderr.
- Reject unknown flags and missing required values before invoking Git, GTR, an
  adapter, or a provider CLI.
- Never add a `--force` retirement path. Never delete a remote branch without
  the exact `--delete-remote-branch` flag and already-proven merge.
- All read-only retirement gates must pass before `pre-retire` or `git gtr rm`.
- `bin/`, `contract/`, `scripts/`, `tests/fixtures/adapter.sh`, and
  `skills/wt-axi/` must remain product-agnostic.
- Run `./scripts/check.sh` before committing. Run
  `./scripts/generate-skill.sh --check` whenever the CLI contract or skill
  changes.
