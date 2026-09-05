#!/usr/bin/env python3
"""Upload the decision corpus and precomputed model matrix to Langfuse v4."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
import time
import uuid

from langfuse import Langfuse
from opentelemetry import trace
from typing import Any


@dataclass
class PublishedItem:
    item: Any
    trace_id: str


@dataclass
class PublishedExperiment:
    experiment_id: str
    experiment_name: str
    item_results: list[PublishedItem]


def experiment_attempt_name(run_prefix: str, model: str, started_at: datetime, experiment_id: str) -> str:
    stamp = started_at.strftime("%Y%m%dT%H%M%SZ")
    return f"{run_prefix}/{model}/{stamp}-{experiment_id[:8]}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", default="wt-axi/worktree-decision-v0")
    parser.add_argument("--dataset-file", type=Path, required=True)
    parser.add_argument("--results-dir", type=Path, required=True)
    parser.add_argument("--run-prefix", default="wt-axi-policy-v0-2026-09-01")
    parser.add_argument("--confirm-timeout", type=float, default=30.0)
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


def decode_io(value):
    if isinstance(value, str):
        try:
            return json.loads(value)
        except ValueError:
            pass
    return value


def confirm_publication(client, dataset_id, result, decisions, started_at, timeout=30.0) -> int:
    """Read-only polling: flush completion alone does not prove server acceptance."""
    expected = {row.item.id: row for row in result.item_results}
    deadline = time.monotonic() + timeout
    confirmed: set[str] = set()
    received = 0

    def unconfirmed() -> TimeoutError:
        missing = sorted(set(expected) - confirmed)
        return TimeoutError(
            f"Langfuse did not confirm {len(missing)} of {len(expected)} experiment items "
            f"for experiment {result.experiment_id} within {timeout:g}s "
            f"(last readback returned {received} rows); "
            f"unconfirmed dataset item ids: {', '.join(missing)}"
        )

    while True:
        rows = []
        cursor = None
        cursors = set()
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise unconfirmed()
            page = client.api.experiments.list_items(
                from_start_time=started_at, experiment_id=result.experiment_id,
                dataset_id=dataset_id, fields="core,dataset,io,scores", limit=100,
                cursor=cursor, request_options={"timeout_in_seconds": min(5, remaining), "max_retries": 0},
            )
            rows.extend(page.data)
            cursor = page.meta.cursor
            if not cursor:
                break
            if cursor in cursors:
                raise ValueError("experiment item pagination repeated a cursor")
            cursors.add(cursor)
        received = len(rows)
        confirmed = set()
        for row in rows:
            source = expected.get(row.experiment_item_id)
            if source is None or row.experiment_item_id in confirmed:
                raise ValueError("unexpected or duplicate experiment item in readback")
            output = {"decision": decisions[source.item.input["scenarioId"]]}
            if (row.experiment_id != result.experiment_id
                    or row.experiment_dataset_id != dataset_id
                    or row.trace_id != source.trace_id
                    or decode_io(row.input) != source.item.input
                    or decode_io(row.output) != output
                    or decode_io(row.expected_output) != source.item.expected_output):
                raise ValueError("experiment item readback does not match its source scenario")
            value = output["decision"] == source.item.expected_output["decision"]
            scores = [score for score in (row.scores or []) if score.name == "exact_match"]
            if len(scores) == 1:
                score = scores[0]
                subject = score.subject
                if (score.data_type != "BOOLEAN" or score.value != value
                        or subject is None or subject.kind != "observation"
                        or subject.id != row.id or subject.trace_id != row.trace_id):
                    raise ValueError("exact_match score does not match its source item/root")
                confirmed.add(row.experiment_item_id)
            elif len(scores) > 1:
                raise ValueError("duplicate exact_match score in readback")
        if confirmed == set(expected):
            return len(confirmed)
        if time.monotonic() >= deadline:
            raise unconfirmed()
        time.sleep(0.5)


def main() -> None:
    args = parse_args()
    require_credentials()
    source_items = load_dataset(args.dataset_file)
    model_results = load_results(args.results_dir)

    client = Langfuse(additional_headers={"x-langfuse-ingestion-version": "4"})
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
    experiments = []
    for model, decisions in model_results.items():
        if set(decisions) != expected_ids:
            raise ValueError(f"result scenarios do not match the corpus: {model}")
        started_at = datetime.now(timezone.utc)
        experiment_id = str(uuid.uuid4())
        run_name = experiment_attempt_name(args.run_prefix, model, started_at, experiment_id)

        result = PublishedExperiment(experiment_id, run_name, [])
        for item in remote_items.values():
            observed = decisions[item.input["scenarioId"]]
            expected = item.expected_output["decision"]
            with client.start_as_current_observation(
                name="worktree-decision", as_type="span", input=item.input,
                output={"decision": observed},
                metadata={"model": model, "expectedDecision": expected},
            ) as span:
                # SDK run_experiment still writes legacy dataset-run-items in 4.14.4.
                # Use the documented OTEL experiment contract on the active span.
                trace.get_current_span().set_attributes({
                    "langfuse.experiment.id": result.experiment_id,
                    "langfuse.experiment.name": run_name,
                    "langfuse.experiment.dataset.id": dataset.id,
                    "langfuse.experiment.item.id": item.id,
                    "langfuse.experiment.item.root_observation_id": span.id,
                    "langfuse.experiment.item.expected_output": json.dumps(item.expected_output),
                    "langfuse.experiment.description": "Precomputed output from one batch model call.",
                    "langfuse.experiment.metadata.model": model,
                    "langfuse.experiment.metadata.executionMode": "single-batch-call",
                    "langfuse.experiment.metadata.policy": "skills/wt-axi/SKILL.md",
                    "langfuse.environment": "experiment",
                })
                result.item_results.append(PublishedItem(item, span.trace_id))
            client.flush()
            client.api.scores.create(
                id=str(uuid.uuid4()), name="exact_match", value=float(observed == expected),
                data_type="BOOLEAN", trace_id=span.trace_id, observation_id=span.id,
                environment="experiment",
                comment=f"expected={expected}; observed={observed}",
                request_options={"timeout_in_seconds": 15, "max_retries": 0},
            )
        client.flush()
        scores_created += confirm_publication(
            client, dataset.id, result, decisions, started_at, timeout=args.confirm_timeout
        )
        experiments.append({"id": result.experiment_id, "name": result.experiment_name})

    print("langfuseUpload:")
    print(f'  dataset: "{args.dataset}"')
    print(f"  items: {len(source_items)}")
    print(f"  runs: {len(model_results)}")
    print(f"  scores: {scores_created}")
    print(f"  experiments: {json.dumps(experiments)}")


if __name__ == "__main__":
    main()
