# Worktree decision conformance experiment

## Thesis

- **Problem:** mandatory worktree creation adds setup, token, and merge cost to
  changes where isolation has no practical value.
- **Policy under test:** allow in-place work only when every low-risk criterion
  is true; use a worktree when any criterion is false or unknown.
- **Hypothesis:** Sonnet, Opus, Terra, and Sol can apply the written policy with
  100% exact decision accuracy and zero unsafe `in-place` decisions.
- **Decision:** adopt the policy only while the zero-unsafe-error condition
  holds; expand the corpus when a real ambiguous case is found.

## Dataset v0

- Name: `wt-axi/worktree-decision-v0`.
- Size: 12 hand-authored, reviewable scenarios.
- Distribution: 3 expected `in-place`, 9 expected `worktree`.
- In-place coverage: read-only review, documentation typo, localized code fix.
- Isolation coverage: unrelated target edits, parallel writer, dependency
  update, schema migration, bulk generation, independent PR, persistent
  runtime, explicit worktree requirement, and unknown concurrency state.
- Schema:
  - `input`: `scenarioId`, `scenario`;
  - `expectedOutput`: `decision` (`in-place` or `worktree`);
  - `metadata`: suite and source identifiers.
- Source: `evals/worktree-decision-dataset.jsonl`, generated from
  `tests/fixtures/worktree-decision-cases.tsv`.

## Method

- Each model receives the generated `skills/wt-axi/SKILL.md` and all scenarios.
- One batch call per model avoids 48 agent startups and repeated policy tokens.
- Models return one decision per scenario; no tools or file mutation are
  allowed in this comprehension phase.
- Runner versions: Claude Code `2.1.251`, Codex CLI `0.151.0`.
- Model matrix: `sonnet`, `opus`, `gpt-5.6-terra`, `gpt-5.6-sol`.
- Run date: 2026-09-01.

## Metrics and acceptance

- `exact_match`: observed decision equals expected decision.
- `unsafe_false_negative`: expected `worktree`, observed `in-place`.
- `over_isolation_false_positive`: expected `in-place`, observed `worktree`.
- Required per model: 12/12 exact matches and zero unsafe false negatives.

## Result

| Model | Exact match | Unsafe false negatives | Over-isolation false positives | Status |
|---|---:|---:|---:|---|
| Sonnet | 12/12 | 0 | 0 | pass |
| Opus | 12/12 | 0 | 0 | pass |
| GPT-5.6 Terra | 12/12 | 0 | 0 | pass |
| GPT-5.6 Sol | 12/12 | 0 | 0 | pass |
| **Total** | **48/48** | **0** | **0** | **pass** |

The v0 wording is understandable to all four tested models on the current
corpus. This supports the decision policy itself; it does not yet prove that a
tool-enabled agent will perform or skip the corresponding Git operations.

## Langfuse representation

- Project: `wt-axi-evals`.
- Dataset: `wt-axi/worktree-decision-v0`.
- Runs: `wt-axi-policy-v0-2026-09-01/<provider-model>`.
- Item score: boolean `exact_match`.
- Run metadata records the model, policy path, and
  `executionMode=single-batch-call`.
- Project: [`wt-axi-evals`](https://langfuse.monopoly-gold.com/project/cmtiaawgz01wrml06y08602db).
- Dataset: [`wt-axi/worktree-decision-v0`](https://langfuse.monopoly-gold.com/project/cmtiaawgz01wrml06y08602db/datasets/cmtiar4cn01x5ml06mkoa3hd8/items).
- Experiments: [four model runs](https://langfuse.monopoly-gold.com/project/cmtiaawgz01wrml06y08602db/datasets/cmtiar4cn01x5ml06mkoa3hd8/experiments).
- Upload verified on 2026-09-01: 12 dataset items, 4 runs with 12 items each,
  and 48 boolean `exact_match` scores, all `true`.
- The ephemeral project API key used for upload was revoked after verification;
  the project has no active API keys left by this experiment.

## Limitations and next gate

- The ground truth follows the authored policy and still needs human review.
- One batch per model measures comprehension efficiently but does not estimate
  per-item latency or token cost.
- Sonnet and Opus are moving aliases; repeat runs should record the resolved
  provider model ID when the CLI exposes it.
- There are no paraphrase repetitions or confidence intervals in v0.
- The next gate is a tool-enabled behavioral sandbox: give each agent an
  isolated Git fixture, intercept `wt-axi create`, and verify actual tool calls
  and filesystem placement for both decision classes.

## Reproduce

```sh
./scripts/generate-model-eval-dataset.sh --check
./evals/run-model-matrix.sh --output-dir /tmp/wt-axi-model-results
```

After Langfuse project credentials are available through the environment:

```sh
uv run --with 'langfuse==3.15.0' python evals/upload-langfuse.py \
  --dataset-file evals/worktree-decision-dataset.jsonl \
  --results-dir /tmp/wt-axi-model-results
```
