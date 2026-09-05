"""Execute the ordinary uploader with SDK v4 against an in-process HTTP server."""
import gzip
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import ExportTraceServiceRequest

STAMP = "2026-09-01T00:00:00Z"


class UploadTest(unittest.TestCase):
    def run_upload(self, readback=None, drop_score_for=None, confirm_timeout=None):
        items, roots, scores, requests = {}, {}, [], []
        dataset = {"id": "dataset-id", "name": "synthetic", "projectId": "project-id", "createdAt": STAMP, "updatedAt": STAMP, "description": None, "metadata": {}, "inputSchema": None, "expectedOutputSchema": None}

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def send(self, body, status=200):
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(body).encode())

            def do_POST(self):
                path = urlparse(self.path).path
                requests.append(("POST", path, self.headers.get("x-langfuse-ingestion-version")))
                raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                if self.headers.get("Content-Encoding") == "gzip":
                    raw = gzip.decompress(raw)
                if path == "/api/public/otel/v1/traces":
                    message = ExportTraceServiceRequest.FromString(raw)
                    for resource in message.resource_spans:
                        for scope in resource.scope_spans:
                            for span in scope.spans:
                                attrs = {a.key: getattr(a.value, a.value.WhichOneof("value")) for a in span.attributes}
                                root_id = attrs.get("langfuse.experiment.item.root_observation_id")
                                if root_id == span.span_id.hex():
                                    roots[root_id] = {"id": root_id, "traceId": span.trace_id.hex(), "startTime": STAMP, "endTime": STAMP, "level": "DEFAULT", "environment": attrs.get("langfuse.environment", "default"), "experimentId": attrs["langfuse.experiment.id"], "experimentName": attrs["langfuse.experiment.name"], "experimentItemId": attrs["langfuse.experiment.item.id"], "experimentDatasetId": attrs["langfuse.experiment.dataset.id"], "input": json.loads(attrs["langfuse.observation.input"]), "output": json.loads(attrs["langfuse.observation.output"]), "expectedOutput": json.loads(attrs["langfuse.experiment.item.expected_output"])}
                    return self.send({})
                body = json.loads(raw)
                if path == "/api/public/v2/datasets":
                    return self.send(dataset)
                if path == "/api/public/dataset-items":
                    item = {**body, "datasetId": dataset["id"], "datasetName": dataset["name"], "status": "ACTIVE", "mediaReferences": [], "sourceTraceId": None, "sourceObservationId": None, "createdAt": STAMP, "updatedAt": STAMP}
                    items[item["id"]] = item
                    return self.send(item)
                if path == "/api/public/scores":
                    if drop_score_for is not None and drop_score_for in body.get("comment", ""):
                        return self.send({"id": body.get("id", "score-id")})
                    scores.append(body)
                    return self.send({"id": body.get("id", "score-id")})
                return self.send({"message": "Unexpected endpoint"}, 400)

            def do_GET(self):
                path = urlparse(self.path).path
                requests.append(("GET", path, None))
                if path == "/api/public/v2/datasets/synthetic":
                    return self.send({**dataset, "items": list(items.values())})
                if path == "/api/public/dataset-items":
                    return self.send({"data": list(items.values()), "meta": {"page": 1, "limit": 100, "totalPages": 1, "totalItems": len(items)}})
                if path == "/api/public/experiment-items":
                    data = []
                    for root in roots.values():
                        other = next((r for r in roots.values() if r["id"] != root["id"]), root)
                        linked = []
                        for score in scores:
                            if score.get("observationId") != root["id"]:
                                continue
                            subject = {"kind": "observation", "id": root["id"], "traceId": root["traceId"]}
                            if readback == "swap-root-ids":
                                subject["id"] = other["id"]
                            elif readback == "omit-subject-trace-id":
                                del subject["traceId"]
                            elif readback == "wrong-subject-trace-id":
                                subject["traceId"] = other["traceId"]
                            score_environment = "default" if readback == "score-default-environment" else score.get("environment", "default")
                            linked.append({"id": score.get("id", "score-id"), "projectId": "project-id", "name": score["name"], "source": "API", "timestamp": STAMP, "createdAt": STAMP, "updatedAt": STAMP, "environment": score_environment, "dataType": "BOOLEAN", "value": bool(score["value"]), "subject": subject})
                        row = {**root, **{key: json.dumps(root[key]) for key in ("input", "output", "expectedOutput")}, "scores": linked}
                        if readback == "item-default-environment":
                            row["environment"] = "default"
                        data.append(row)
                    return self.send({"data": data, "meta": {}})
                return self.send({"message": "Unexpected endpoint"}, 400)

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(prefix="wt-axi-upload-test-") as tmp:
                folder = Path(tmp)
                corpus = [
                    {"input": {"scenarioId": "one", "scenario": "synthetic first"}, "expectedOutput": {"decision": "in-place"}, "metadata": {}},
                    {"input": {"scenarioId": "two", "scenario": "synthetic second"}, "expectedOutput": {"decision": "worktree"}, "metadata": {}},
                ]
                (folder / "dataset.jsonl").write_text("\n".join(json.dumps(item) for item in corpus))
                (folder / "model.results.tsv").write_text("scenario\tobserved\none\tin-place\ntwo\tin-place\n")
                env = {**os.environ, "LANGFUSE_PUBLIC_KEY": "pk-test", "LANGFUSE_SECRET_KEY": "sk-test", "LANGFUSE_BASE_URL": f"http://127.0.0.1:{server.server_port}"}
                command = [sys.executable, str(Path(__file__).with_name("upload-langfuse.py")), "--dataset", "synthetic", "--dataset-file", str(folder / "dataset.jsonl"), "--results-dir", str(folder), "--run-prefix", "prefix"]
                if confirm_timeout is not None:
                    command += ["--confirm-timeout", str(confirm_timeout)]
                result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=45)
                return result, roots, scores, requests
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_default_uploader_publishes_and_confirms_two_distinct_items(self):
        result, roots, scores, requests = self.run_upload()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("scores: 2", result.stdout)
        self.assertEqual(2, len(roots))
        self.assertEqual(1, len({r["experimentId"] for r in roots.values()}))
        experiment_id, = {r["experimentId"] for r in roots.values()}
        experiment_name, = {r["experimentName"] for r in roots.values()}
        self.assertTrue(experiment_name.startswith("prefix/model/"), experiment_name)
        self.assertNotEqual("prefix/model", experiment_name)
        self.assertTrue(experiment_name.endswith(experiment_id[:8]), experiment_name)
        self.assertIn(experiment_name, result.stdout)
        self.assertEqual(2, len(scores))
        for root in roots.values():
            score = next(s for s in scores if s["observationId"] == root["id"])
            self.assertEqual(root["traceId"], score["traceId"])
            self.assertEqual("experiment", root["environment"])
            self.assertEqual("experiment", score["environment"])
            self.assertEqual(root["input"]["scenarioId"] == "one", bool(score["value"]))
            self.assertEqual({"decision": "in-place"}, root["output"])
        for method, path, version in requests:
            self.assertNotIn("ingestion", path)
            self.assertNotIn("dataset-run", path)
            self.assertFalse(path.endswith("/runs"))
            if path == "/api/public/otel/v1/traces":
                self.assertEqual("4", version)

    def assert_rejected(self, result, message):
        self.assertNotEqual(0, result.returncode)
        self.assertIn(message, result.stderr)
        self.assertNotIn("langfuseUpload:", result.stdout)

    def test_swapped_real_root_ids_fail_without_success_summary(self):
        result, roots, scores, _ = self.run_upload(readback="swap-root-ids", confirm_timeout=2)
        self.assertEqual(2, len(roots))
        self.assertEqual(2, len(scores))
        self.assertEqual(2, len({r["id"] for r in roots.values()}))
        self.assert_rejected(result, "score does not match its source item/root")

    def test_missing_optional_subject_trace_id_is_confirmed_through_row_trace(self):
        result, roots, scores, _ = self.run_upload(readback="omit-subject-trace-id")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("scores: 2", result.stdout)
        for root in roots.values():
            score = next(s for s in scores if s["observationId"] == root["id"])
            self.assertEqual(root["traceId"], score["traceId"])

    def test_present_subject_trace_id_of_other_case_fails(self):
        result, _, _, _ = self.run_upload(readback="wrong-subject-trace-id", confirm_timeout=2)
        self.assert_rejected(result, "score does not match its source item/root")

    def test_score_outside_experiment_environment_fails(self):
        result, _, _, _ = self.run_upload(readback="score-default-environment", confirm_timeout=2)
        self.assert_rejected(result, "score is not in the experiment environment")

    def test_item_outside_experiment_environment_fails(self):
        result, _, _, _ = self.run_upload(readback="item-default-environment", confirm_timeout=2)
        self.assert_rejected(result, "experiment item readback is not in the experiment environment")

    def test_repeated_runs_are_separate_experiment_attempts_with_stable_item_ids(self):
        first, first_roots, _, _ = self.run_upload()
        second, second_roots, _, _ = self.run_upload()
        self.assertEqual(0, first.returncode, first.stderr)
        self.assertEqual(0, second.returncode, second.stderr)
        first_ids = {r["experimentId"] for r in first_roots.values()}
        second_ids = {r["experimentId"] for r in second_roots.values()}
        self.assertEqual(1, len(first_ids))
        self.assertEqual(1, len(second_ids))
        self.assertNotEqual(first_ids, second_ids)
        self.assertEqual({r["experimentItemId"] for r in first_roots.values()}, {r["experimentItemId"] for r in second_roots.values()})

    def test_unconfirmed_item_timeout_names_missing_item_ids_without_secrets(self):
        result, roots, scores, _ = self.run_upload(drop_score_for="expected=worktree;", confirm_timeout=2)
        self.assertNotEqual(0, result.returncode)
        self.assertNotIn("langfuseUpload:", result.stdout)
        self.assertEqual(2, len(roots))
        self.assertEqual(1, len(scores))
        missing_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "wt-axi:synthetic:two"))
        confirmed_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "wt-axi:synthetic:one"))
        self.assertIn("did not confirm 1 of 2 experiment items", result.stderr)
        self.assertIn("last readback returned 2 rows", result.stderr)
        self.assertIn(missing_id, result.stderr)
        self.assertNotIn(confirmed_id, result.stderr)
        self.assertNotIn("sk-test", result.stderr)
        self.assertNotIn("pk-test", result.stderr)


if __name__ == "__main__":
    unittest.main()
