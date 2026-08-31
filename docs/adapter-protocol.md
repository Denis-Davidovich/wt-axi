# Project adapter protocol v0

The optional adapter is a consumer-owned, tracked executable. Configure its
repository-relative path and exact SHA-256 in local Git config:

```sh
git config --local wt-axi.adapter.path scripts/wt-axi-adapter
git config --local wt-axi.adapter.sha256 "<lowercase sha256>"
```

wt-axi refuses the adapter when the path is absolute, leaves the repository,
is untracked, is not executable, or does not match the pinned digest.

## `status`

```sh
scripts/wt-axi-adapter status --worktree <absolute-path>
```

The command is read-only and writes exactly two tab-separated records:

```text
runtimeState	inactive
activeAgent	false
```

`runtimeState` is `inactive`, `active`, or `unknown`; `activeAgent` is `true` or
`false`. Invalid output, a non-zero exit, `active`, `unknown`, or `true` makes
retirement unsafe.

## `pre-retire`

After Git state, current-worktree, merge, and `status` gates all pass:

```sh
scripts/wt-axi-adapter pre-retire \
  --worktree <absolute-path> --branch <branch> --target <target-ref>
```

This operation may stop or remove only resources scoped to that worktree. A
non-zero exit aborts Git removal. stdout is ignored; diagnostics belong on
stderr. The adapter must be idempotent because a later Git removal failure can
leave the already-stopped runtime available for a safe retry.
