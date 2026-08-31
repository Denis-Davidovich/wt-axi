# wt-axi repository instructions

- Keep implementation work in `.worktrees/wt-axi-wt-<task-slug>`.
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
