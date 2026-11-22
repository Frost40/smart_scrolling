"""Provider regressions: py -3 -m unittest tools.content.pipeline.test_regressions."""

from contextlib import closing
import datetime as dt
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from tools.content.pipeline import llm, settings, store


SCHEMA = {
    "type": "object", "properties": {"ok": {"type": "boolean"}, "message": {"type": "string"}},
    "required": ["ok", "message"], "additionalProperties": False,
}
ANSWER = {"ok": True, "message": "hello"}


class ProviderRegressionTests(unittest.TestCase):
    def setUp(self):
        temporary = self.enterContext(tempfile.TemporaryDirectory())
        self.root = Path(temporary)
        self.enterContext(patch.dict(os.environ, {"PIPELINE_HOME": str(self.root / "home")}))
        self.enterContext(patch.object(settings, "ROOT", self.root))
        self.enterContext(patch("urllib.request.getproxies", return_value={}))
        self.options = {
            "quality": {"require_qualified": False}, "make": {"call_timeout_seconds": 1},
            "providers": {
                "regression-cli": {"driver": "cli", "preset": "claude", "model": "test", "max_calls_per_day": 100},
                "regression-http": {"driver": "openai", "base_url": "http://127.0.0.1:1", "model": "test"},
            },
            "roles": {"write": ["regression-cli"]},
        }
        self.save()

    def save(self):
        (settings.home() / "settings.json").write_text(json.dumps(self.options), encoding="utf-8")

    def invoke(self, name="regression-cli"):
        return llm.run_provider(name, "Return JSON.", "Say hello.", SCHEMA)

    def rows(self):
        with closing(store.connect()) as db:
            return [dict(row) for row in db.execute("SELECT * FROM calls")]

    def completed(self, envelope, code=0, stderr=""):
        output = envelope if isinstance(envelope, str) else json.dumps(envelope)
        return subprocess.CompletedProcess(["fake"], code, output, stderr)

    def http(self, respond):
        requests = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                requests.append((self.path, self.headers.get("Authorization"), body))
                try:
                    respond(self)
                except (OSError, ValueError):
                    pass  # Deadline tests deliberately close the client socket.

            do_GET = do_POST

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
        thread.start()

        def stop():
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        self.addCleanup(stop)
        address = f"http://127.0.0.1:{server.server_port}"
        self.options["providers"]["regression-http"]["base_url"] = address
        self.save()
        return address, requests

    @staticmethod
    def reply(handler, payload, status=200, headers=None):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        handler.send_response(status)
        handler.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            handler.send_header(key, value)
        handler.end_headers()
        handler.wfile.write(body)

    @staticmethod
    def api_answer(**extra):
        return {"choices": [{"message": {"content": json.dumps(ANSWER)}}], **extra}

    def test_cli_nonzero_exit_rejects_valid_answer(self):
        with patch.object(llm.subprocess, "run", return_value=self.completed({"structured_output": ANSWER}, 1)):
            result = self.invoke()
        self.assertFalse(result["ok"])
        self.assertEqual(result["error_kind"], "down")
        self.assertEqual(self.rows()[0]["error_kind"], "down")

    def test_cli_plain_auth_failure_is_down(self):
        with patch.object(llm.subprocess, "run", return_value=self.completed("Please log in", 1)):
            self.assertEqual(self.invoke()["error_kind"], "down")

    def test_claude_session_limit_rests_until_reset(self):
        message = "You've hit your session limit · resets 12:10am (Europe/Rome)"
        with patch.object(llm.subprocess, "run", return_value=self.completed(
                {"result": message, "subtype": "success"}, 1)) as run:
            result = self.invoke()
            self.assertEqual(result["error_kind"], "limit")
            until = dt.datetime.fromisoformat(llm.resting()["regression-cli"])
            self.assertEqual((until.hour, until.minute), (0, 10))
            self.assertGreater(until, dt.datetime.now().astimezone())
            self.assertEqual(self.invoke()["error_kind"], "limit")
            self.assertEqual(run.call_count, 1)

    def test_cli_failed_exit_does_not_read_quota_from_payload_or_usage(self):
        envelope = {"result": "Connection failed", "usage": {"input_tokens": 429},
                    "structured_output": {**ANSWER, "message": "usage limit rate limit 429"}}
        with patch.object(llm.subprocess, "run", return_value=self.completed(envelope, 1)):
            result = self.invoke()
        self.assertEqual(result["error_kind"], "down", result)
        self.assertNotIn("regression-cli", llm.resting())
        self.assertEqual(self.rows()[0]["error_kind"], "down")

    def test_cli_error_envelope_rejects_valid_answer(self):
        envelope = {"is_error": True, "result": "Request refused", "structured_output": ANSWER}
        with patch.object(llm.subprocess, "run", return_value=self.completed(envelope)):
            self.assertEqual(self.invoke()["error_kind"], "refused")

    def test_cli_success_quota_words_and_token_counts_are_not_limits(self):
        for message in ("429 participants", "usage limit", "rate limit", "quota"):
            with self.subTest(message=message):
                envelope = {"structured_output": {**ANSWER, "message": message},
                            "usage": {"input_tokens": 429, "output_tokens": 4}}
                with patch.object(llm.subprocess, "run", return_value=self.completed(envelope)):
                    result = self.invoke()
                self.assertTrue(result["ok"], result)
                self.assertEqual(result["tokens_in"], 429)
                self.assertNotIn("regression-cli", llm.resting())

    def test_cli_removes_subscription_api_key(self):
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "synthetic-secret", "CLAUDECODE": "1"}):
            with patch.object(llm.subprocess, "run", return_value=self.completed({"structured_output": ANSWER})) as run:
                self.assertTrue(self.invoke()["ok"])
        self.assertNotIn("ANTHROPIC_API_KEY", run.call_args.kwargs["env"])
        self.assertNotIn("CLAUDECODE", run.call_args.kwargs["env"])

    def test_stream_ignores_non_object_events_and_uses_terminal_result(self):
        self.options["providers"]["regression-cli"]["preset"] = "agy-stream"
        self.save()
        events = [[], None, {"event": "init"}, {"event": "result", "result": {
            "status": "SUCCESS", "structured_output": ANSWER,
            "usage": {"input_tokens": 429, "output_tokens": 2},
        }}]
        output = "\n".join(json.dumps(event) for event in events) + "\n"
        with patch.object(llm.subprocess, "run", return_value=self.completed(output)) as run:
            result = self.invoke()
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["tokens_in"], 429)
        event = json.loads(run.call_args.kwargs["input"])
        self.assertEqual(event["event"], "user")
        self.assertIn("Say hello.", event["message"]["content"])

    def test_http_success_reads_complete_body(self):
        self.http(lambda handler: self.reply(handler, self.api_answer()))
        result = self.invoke("regression-http")
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["data"], ANSWER)
        self.assertEqual(len(self.rows()), 1)

    def test_http_error_body_and_retry_after_are_read(self):
        self.http(lambda handler: self.reply(handler, b"quota exhausted", 429, {"Retry-After": "120"}))
        before = dt.datetime.now().astimezone()
        result = self.invoke("regression-http")
        self.assertEqual(result["error_kind"], "limit", result)
        self.assertIn("quota exhausted", result["error"])
        until = dt.datetime.fromisoformat(llm.resting()["regression-http"])
        self.assertGreaterEqual((until - before).total_seconds(), 120)
        self.assertLess((until - before).total_seconds(), 123)
        self.assertEqual(len(self.rows()), 1)

    def test_http_empty_error_body_is_down(self):
        self.http(lambda handler: self.reply(handler, b"", 500))
        self.assertEqual(self.invoke("regression-http")["error_kind"], "down")

    def test_redirect_does_not_forward_bearer_token(self):
        destination, leaked = self.http(lambda handler: self.reply(handler, self.api_answer()))
        _, original = self.http(lambda handler: self.reply(handler, b"", 302, {"Location": destination + "/collect"}))
        (self.root / ".env").write_text("TEST_KEY=synthetic-secret\n", encoding="utf-8")
        self.options["providers"]["regression-http"]["key_env"] = "TEST_KEY"
        self.save()
        result = self.invoke("regression-http")
        self.assertFalse(result["ok"])
        self.assertEqual(result["error_kind"], "down", result)
        self.assertEqual(original[0][1], "Bearer synthetic-secret")
        self.assertEqual(leaked, [])

    def test_malformed_http_envelopes_are_recorded(self):
        payload = [None]
        self.http(lambda handler: self.reply(handler, payload[0]))
        cases = [None, [], {"choices": []}, {"choices": [None]},
                 {"choices": [{"message": None}]}, self.api_answer(usage=None)]
        for index, envelope in enumerate(cases, 1):
            with self.subTest(envelope=envelope):
                payload[0] = envelope
                result = self.invoke("regression-http")
                self.assertEqual(result["error_kind"], "bad_json", result)
                self.assertEqual(len(self.rows()), index)

    def test_invalid_cli_token_counts_are_recorded(self):
        for index, count in enumerate(([], "abc", -1, True, None, 2**63), 1):
            with self.subTest(count=count):
                envelope = {"structured_output": ANSWER, "usage": {"input_tokens": count, "output_tokens": 1}}
                with patch.object(llm.subprocess, "run", return_value=self.completed(envelope)):
                    result = self.invoke()
                self.assertEqual(result["error_kind"], "bad_json", result)
                self.assertEqual(result["tokens_in"], 0)
                self.assertEqual(len(self.rows()), index)

    def test_http_chunked_success(self):
        def respond(handler):
            body = json.dumps(self.api_answer()).encode()
            handler.send_response(200)
            handler.send_header("Transfer-Encoding", "chunked")
            handler.end_headers()
            handler.wfile.write(f"{len(body):x}\r\n".encode() + body + b"\r\n0\r\n\r\n")
        self.http(respond)
        result = self.invoke("regression-http")
        self.assertTrue(result["ok"], result)

    def test_truncated_chunked_response_is_recorded_down(self):
        def respond(handler):
            handler.send_response(200)
            handler.send_header("Transfer-Encoding", "chunked")
            handler.end_headers()
            handler.wfile.write(b'40\r\n{"choices":[')
            handler.close_connection = True
        self.http(respond)
        result = self.invoke("regression-http")
        self.assertEqual(result["error_kind"], "down", result)
        self.assertEqual(self.rows()[0]["error_kind"], "down")

    def test_slow_body_obeys_total_deadline(self):
        stop = threading.Event()
        def respond(handler):
            body = json.dumps(self.api_answer()).encode()
            handler.send_response(200)
            handler.send_header("Content-Length", str(len(body)))
            handler.end_headers()
            for byte in body:
                handler.wfile.write(bytes([byte]))
                handler.wfile.flush()
                if stop.wait(0.04):
                    break
        self.http(respond)
        self.addCleanup(stop.set)
        started = time.monotonic()
        result = self.invoke("regression-http")
        self.assertEqual(result["error_kind"], "down", result)
        self.assertLess(time.monotonic() - started, 2)
        self.assertEqual(len(self.rows()), 1)

    def test_slow_chunk_header_obeys_total_deadline(self):
        stop = threading.Event()
        def respond(handler):
            handler.send_response(200)
            handler.send_header("Transfer-Encoding", "chunked")
            handler.end_headers()
            # read1 must parse this whole framing line before returning a body byte.
            for byte in b"0" * 60 + b"5\r\n":
                handler.wfile.write(bytes([byte]))
                handler.wfile.flush()
                if stop.wait(0.03):
                    return
            handler.wfile.write(b"hello\r\n0\r\n\r\n")
        self.http(respond)
        self.addCleanup(stop.set)
        started = time.monotonic()
        result = self.invoke("regression-http")
        elapsed = time.monotonic() - started
        self.assertEqual(result["error_kind"], "down", result)
        self.assertLess(elapsed, 1.6, f"one-second deadline took {elapsed:.3f}s")

    def test_bad_reset_timestamp_uses_fallback_and_is_recorded(self):
        output = self.completed("usage limit resets 2099-99-99T12:00:00Z", 1)
        before = dt.datetime.now().astimezone()
        with patch.object(llm.subprocess, "run", return_value=output):
            result = self.invoke()
        self.assertEqual(result["error_kind"], "limit")
        until = dt.datetime.fromisoformat(llm.resting()["regression-cli"])
        self.assertGreaterEqual((until - before).total_seconds(), 3600)
        self.assertLess((until - before).total_seconds(), 3603)
        self.assertEqual(len(self.rows()), 1)

    def test_direct_call_at_zero_cap_does_not_start_cli(self):
        self.options["providers"]["regression-cli"]["max_calls_per_day"] = 0
        self.save()
        with patch.object(llm.subprocess, "run") as run:
            self.assertEqual(self.invoke()["error_kind"], "limit")
        run.assert_not_called()
        self.assertEqual(self.rows(), [])
        until = dt.datetime.fromisoformat(llm.resting()["regression-cli"])
        self.assertEqual(until.date(), dt.date.today() + dt.timedelta(days=1))
        self.assertEqual((until.hour, until.minute, until.second), (0, 0, 0))

    def test_direct_resting_call_does_not_start_cli(self):
        until = dt.datetime.now().astimezone() + dt.timedelta(hours=1)
        llm._rest("regression-cli", until)
        with patch.object(llm.subprocess, "run") as run:
            self.assertEqual(self.invoke()["error_kind"], "limit")
        run.assert_not_called()
        self.assertEqual(self.rows(), [])

    def test_direct_provider_without_cap_uses_default_100(self):
        del self.options["providers"]["regression-cli"]["max_calls_per_day"]
        self.save()
        with patch.object(llm, "calls_today", return_value=100):
            with patch.object(llm.subprocess, "run") as run:
                self.assertEqual(self.invoke()["error_kind"], "limit")
        run.assert_not_called()
        self.assertIn("regression-cli", llm.resting())

    def test_direct_final_allowed_call_rests_until_midnight(self):
        self.options["providers"]["regression-cli"]["max_calls_per_day"] = 1
        self.save()
        with patch.object(llm.subprocess, "run", return_value=self.completed({"structured_output": ANSWER})) as run:
            self.assertTrue(self.invoke()["ok"])
            self.assertEqual(self.invoke()["error_kind"], "limit")
        self.assertEqual(run.call_count, 1)
        self.assertEqual(len(self.rows()), 1)
        self.assertIn("regression-cli", llm.resting())

    def test_cut_retries_both_halves_without_losing_odd_item(self):
        values = {key: "(none)" for key in ("title", "authors", "kind", "thesis", "glossary", "people", "repair_block")}
        values.update(idea_count=5, ideas_with_paragraphs=[{"ref": str(i)} for i in range(5)])
        batches = []
        def respond(cmd, **kwargs):
            batch = json.loads(kwargs["input"].split("Ideas to write (", 1)[1].split(":", 1)[1].strip())
            batches.append([item["ref"] for item in batch])
            if len(batches) == 1:
                return self.completed({"stop_reason": "max_tokens"})
            cards = [{"ref": item["ref"], "title": "T", "front": "F.", "back": "B."} for item in batch]
            return self.completed({"structured_output": {"cards": cards}, "usage": {"input_tokens": 5, "output_tokens": 2}})
        with patch.object(llm.subprocess, "run", side_effect=respond):
            result = llm.call("write", "write", values)
        self.assertTrue(result["ok"], result)
        self.assertEqual([card["ref"] for card in result["data"]["cards"]], [str(i) for i in range(5)])
        self.assertEqual(batches, [["0", "1", "2", "3", "4"], ["0", "1", "2"], ["3", "4"]])
        self.assertEqual((result["tokens_in"], result["tokens_out"]), (10, 4))
        self.assertEqual(len(self.rows()), 3)

    def test_cut_second_half_failure_never_returns_partial_success(self):
        values = {key: "(none)" for key in ("title", "authors", "kind", "thesis", "glossary", "people", "repair_block")}
        values.update(idea_count=2, ideas_with_paragraphs=[{"ref": "a"}, {"ref": "b"}])
        outputs = [self.completed({"stop_reason": "max_tokens"}),
                   self.completed({"structured_output": {"cards": [{"ref": "a", "title": "T", "front": "F.", "back": "B."}]}}),
                   self.completed("network down", 1)]
        with patch.object(llm.subprocess, "run", side_effect=outputs):
            result = llm.call("write", "write", values)
        self.assertFalse(result["ok"], result)
        self.assertIsNone(result["data"])
        self.assertEqual(len(self.rows()), 3)


if __name__ == "__main__":
    unittest.main()
