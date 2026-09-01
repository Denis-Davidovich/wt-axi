#!/usr/bin/env python3
"""Upload the decision corpus and precomputed model matrix to Langfuse v3."""

from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path
import sys
import uuid

from langfuse import Langfuse


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", default="wt-axi/worktree-decision-v0")
    parser.add_argument("--dataset-file", type=Path, required=True)
    parser.add_argument("--results-dir", type=Path, required=True)
    parser.add_argument("--run-prefix", default="wt-axi-policy-v0-2026-09-01")
    return parser.parse_args()


def require_credentials() -> None:
    missing = [
        name
        for name in (
            "LANGFUSE_PUBLIC_KEY",
            "LANGFUSE_SECRET_KEY",
            "LANGFUSE_BASE_URL",
        )
        if not os.environ.get(name)
    ]
    if missing:
        print(
            f"error: missing Langfuse environment: {', '.join(missing)}",
            file=sys.stderr,
        )
        raise SystemExit(2)


def load_dataset(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as stream:
        items = [json.loads(line) for line in stream if line.strip()]
    if not items:
        raise ValueError("dataset is empty")
    return items


def load_results(results_dir: Path) -> dict[str, dict[str, str]]:
    matrix: dict[str, dict[str, str]] = {}
    for path in sorted(results_dir.glob("*.results.tsv")):
        model = path.name.removesuffix(".results.tsv")
        decisions: dict[str, str] = {}
        with path.open(encoding="utf-8", newline="") as stream:
            for row in csv.DictReader(stream, delimiter="\t"):
                decisions[row["scenario"]] = row["observed"]
        matrix[model] = decisions
    if not matrix:
        raise ValueError(f"no model result files found in {results_dir}")
    return matrix


def main() -> None:
    args = parse_args()
    require_credentials()
    source_items = load_dataset(args.dataset_file)
    model_results = load_results(args.results_dir)

    client = Langfuse()
    client.create_dataset(
        name=args.dataset,
        description=(
            "Conformance corpus for deciding whether an agent may edit in-place "
            "or must create a task-specific Git worktree."
        ),
        metadata={
            "suite": "wt-axi-worktree-decision",
            "version": "v0",
            "executionMode": "single-batch-call-per-model",
        },
        input_schema={
            "type": "object",
            "properties": {
                "scenarioId": {"type": "string"},
                "scenario": {"type": "string"},
            },
            "required": ["scenarioId", "scenario"],
            "additionalProperties": False,
        },
        expected_output_schema={
            "type": "object",
            "properties": {
                "decision": {"type": "string", "enum": ["in-place", "worktree"]}
            },
            "required": ["decision"],
            "additionalProperties": False,
        },
    )

    expected_by_id: dict[str, str] = {}
    for item in source_items:
        scenario_id = item["input"]["scenarioId"]
        expected_by_id[scenario_id] = item["expectedOutput"]["decision"]
        stable_id = str(
            uuid.uuid5(uuid.NAMESPACE_URL, f"wt-axi:{args.dataset}:{scenario_id}")
        )
        client.create_dataset_item(
            dataset_name=args.dataset,
            id=stable_id,
            input=item["input"],
            expected_output=item["expectedOutput"],
            metadata=item["metadata"],
        )

    dataset = client.get_dataset(args.dataset)
    remote_items = {item.input["scenarioId"]: item for item in dataset.items}
    expected_ids = set(expected_by_id)
    if set(remote_items) != expected_ids:
        raise ValueError("remote dataset scenarios do not match the local corpus")

    scores_created = 0
    for model, decisions in model_results.items():
        if set(decisions) != expected_ids:
            raise ValueError(f"result scenarios do not match the corpus: {model}")
        run_name = f"{args.run_prefix}/{model}"
        for scenario_id, item in remote_items.items():
            observed = decisions[scenario_id]
            expected = expected_by_id[scenario_id]
            with item.run(
                run_name=run_name,
                run_description="Precomputed output from one cost-efficient batch model call.",
                run_metadata={
                    "model": model,
                    "executionMode": "single-batch-call",
                    "policy": "skills/wt-axi/SKILL.md",
                },
            ) as span:
                span.update(
                    name="worktree-decision",
                    input=item.input,
                    output={"decision": observed},
                    model=model,
                    metadata={"expectedDecision": expected},
                )
                span.score(
                    name="exact_match",
                    value=observed == expected,
                    data_type="BOOLEAN",
                    comment=f"expected={expected}; observed={observed}",
                )
                scores_created += 1

    client.flush()
    print("langfuseUpload:")
    print(f'  dataset: "{args.dataset}"')
    print(f"  items: {len(source_items)}")
    print(f"  runs: {len(model_results)}")
    print(f"  scores: {scores_created}")


if __name__ == "__main__":
    main()
