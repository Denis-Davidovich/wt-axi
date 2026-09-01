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

The skill is project-agnostic. It does not create a worktree for read-only work.
For implementation, an in-place edit is allowed only when all of these are
true:

- neither the user nor repository instructions require a separate worktree;
- the change is small, localized, reversible, and does not include dependency
  changes, schema or data migrations, or bulk-generated output;
- the current worktree is the intended base and the files to be edited contain
  no unrelated changes;
- no other agent or task will write to the repository concurrently;
- the task needs no independent branch, commit, pull request, merge, or handoff;
- validation is bounded and does not require persistent services or scoped
  runtime resources.

If any condition is false or unknown, the skill creates a task-specific
worktree at the start. A typo, wording correction, or similarly local config
edit will normally qualify for in-place work; a feature, cross-cutting bug fix,
refactor, migration, dependency update, or parallel-agent task will not.

For tasks that use a worktree, `status` followed by safe local `retire` is the
normal terminal step after delivery and merge are proven. The skill does not
run retirement merely because a session started. Remote-branch deletion still
requires the explicit CLI flag and explicit user intent; terminal completion
alone is not consent.

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
./scripts/generate-model-eval-dataset.sh --check

# Paid model-in-the-loop conformance eval (requires authenticated CLIs)
./tests/model-decision-eval.sh --provider all
WT_AXI_RUN_MODEL_EVAL=1 ./scripts/check.sh

# Requested four-model matrix with preserved response artifacts
./evals/run-model-matrix.sh --output-dir /tmp/wt-axi-model-results
```

The model eval supplies the generated skill and a decision corpus to Codex,
Claude Code, and OpenCode, then requires every model to classify every scenario
as `in-place` or `worktree`. It is opt-in so the default checks remain
deterministic, credential-free, and free of model-token cost. A provider can be
tested alone with `--provider codex`, `claude`, or `opencode`; model overrides
are available through `WT_AXI_EVAL_CODEX_MODEL`,
`WT_AXI_EVAL_CLAUDE_MODEL`, and `WT_AXI_EVAL_OPENCODE_MODEL`.

The Langfuse-ready dataset is generated at
`evals/worktree-decision-dataset.jsonl`. The requested matrix runs Claude
Sonnet, Claude Opus, GPT-5.6 Terra, and GPT-5.6 Sol once each against all
scenarios and preserves per-model prompts, responses, and per-item exact-match
results for experiment ingestion.
The hypothesis, corpus distribution, acceptance gates, results, and limitations
are summarized in [evals/EXPERIMENT.md](evals/EXPERIMENT.md).

The target Langfuse instance currently runs v3, so experiment ingestion uses
the latest compatible Python SDK rather than the v4-only Experiments API:

```sh
LANGFUSE_BASE_URL=https://langfuse.example.com \
LANGFUSE_PUBLIC_KEY=pk-lf-example \
LANGFUSE_SECRET_KEY=sk-lf-example \
uv run --with 'langfuse==3.15.0' python evals/upload-langfuse.py \
  --dataset-file evals/worktree-decision-dataset.jsonl \
  --results-dir /tmp/wt-axi-model-results
```

Set real keys through the environment; never pass or commit them as command-line
arguments. The uploader creates a versioned dataset with input/output schemas,
uses stable item IDs for idempotent updates, creates one dataset run per model,
and records a boolean `exact_match` score for every scenario.

The decision record is [DEPENDENCIES.md](DEPENDENCIES.md). The research gate is
the production Planner goal
[`01a0550c-92bf-72b5-a777-bf44c2b2a901`](https://planner.monopoly-gold.com/app#project/wt-axi/goal/01a0550c-92bf-72b5-a777-bf44c2b2a901).
