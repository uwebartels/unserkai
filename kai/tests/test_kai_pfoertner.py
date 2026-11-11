import http.client
import importlib.machinery
import importlib.util
import json
import os
import socket
import tempfile
import threading
import time
import unittest
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PROGRAM_PATH = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "bin", "kai-pfoertner")
)

loader = importlib.machinery.SourceFileLoader("kai_pfoertner", PROGRAM_PATH)
spec = importlib.util.spec_from_loader("kai_pfoertner", loader)
kai_pfoertner = importlib.util.module_from_spec(spec)
loader.exec_module(kai_pfoertner)


def free_port():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


class FakeBackend:
    def __init__(self, load_delay=0.5):
        self.load_delay = load_delay
        self.lock = threading.Lock()
        self.loaded = set()
        self.request_count = 0
        self.slow = False
        self.health_ok = True
        self.api_key = ""  # when set, every request must carry it (llama-swap apiKeys)

        self.port = free_port()
        self.url = "http://127.0.0.1:%d" % self.port

        backend = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, fmt, *args):
                pass

            def _send_json(self, status, obj):
                body = json.dumps(obj).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(body)

            def _send_text(self, status, text):
                body = text.encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(body)

            def _authorized(self):
                if not backend.api_key:
                    return True
                if self.headers.get("Authorization") == "Bearer " + backend.api_key:
                    return True
                self._send_json(401, {"error": "unauthorized"})
                return False

            def do_GET(self):
                if not self._authorized():
                    return
                parsed = urllib.parse.urlsplit(self.path)
                path = parsed.path

                if path == "/health":
                    if backend.health_ok:
                        self._send_text(200, "OK")
                    else:
                        self._send_text(503, "unavailable")
                    return

                if path == "/running":
                    with backend.lock:
                        models = sorted(backend.loaded)
                    obj = {
                        "running": [
                            {"model": model, "state": "ready"} for model in models
                        ]
                    }
                    self._send_json(200, obj)
                    return

                if path.startswith("/upstream/"):
                    parts = path.split("/")
                    if len(parts) >= 4 and parts[3] == "health":
                        model = urllib.parse.unquote(parts[2])
                        time.sleep(backend.load_delay)
                        with backend.lock:
                            backend.loaded = {model}
                        self._send_text(200, "OK")
                        return

                self._send_json(404, {"error": "not found"})

            def do_POST(self):
                if not self._authorized():
                    return
                parsed = urllib.parse.urlsplit(self.path)
                path = parsed.path

                if path != "/v1/chat/completions":
                    self._send_json(404, {"error": "not found"})
                    return

                length = int(self.headers.get("Content-Length", "0") or 0)
                raw = self.rfile.read(length) if length else b""
                try:
                    data = json.loads(raw.decode("utf-8", "replace"))
                except Exception:
                    data = {}

                model = data.get("model", "unknown")
                stream = bool(data.get("stream", False))

                with backend.lock:
                    backend.request_count += 1

                if not stream:
                    obj = {
                        "model": model,
                        "choices": [
                            {
                                "index": 0,
                                "message": {"role": "assistant", "content": "ok"},
                                "finish_reason": "stop",
                            }
                        ],
                    }
                    self._send_json(200, obj)
                    return

                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers()

                for i in range(3):
                    if backend.slow:
                        time.sleep(0.65)
                    else:
                        time.sleep(0.05)

                    chunk = {
                        "id": "chatcmpl-fake",
                        "object": "chat.completion.chunk",
                        "model": model,
                        "choices": [
                            {
                                "index": 0,
                                "delta": {"content": "c%d" % i},
                                "finish_reason": None,
                            }
                        ],
                    }
                    self.wfile.write(b"data: " + json.dumps(chunk).encode("utf-8") + b"\n\n")
                    self.wfile.flush()

                self.wfile.write(b"data: [DONE]\n\n")
                self.wfile.flush()

        self.server = ThreadingHTTPServer(("127.0.0.1", self.port), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def shutdown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def loaded_models(self):
        with self.lock:
            return set(self.loaded)

    def request_count_value(self):
        with self.lock:
            return self.request_count


class KaiPfoertnerEndToEndTest(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.backend = FakeBackend(load_delay=0.5)
        self.pfoertner_port = free_port()
        self.app = None
        self.server = None
        self.loop_thread = None

    def tearDown(self):
        if self.server is not None:
            self.server.shutdown()
            self.server.server_close()
        if self.loop_thread is not None:
            self.loop_thread.join(timeout=2)
        if self.backend is not None:
            self.backend.shutdown()
        self.tmpdir.cleanup()

    def make_config(self, **machine_overrides):
        sim_overrides = machine_overrides.pop("sim", {})
        app_overrides = machine_overrides.pop("app", {})

        machine_cfg = {
            "instance_id": "sim-1",
            "endpoint": self.backend.url,
            "models": ["a", "b"],
            "default_model": "a",
            "poll_seconds": 0.1,
            "check_seconds": 0.3,
            "observe_seconds": 0.2,
            "idle_minutes": 30,
            "min_runtime_minutes": 10,
            "start_timeout_seconds": 10,
            "capacity_wait_seconds": 1,
        }
        machine_cfg.update(machine_overrides)

        sim_cfg = {
            "boot_seconds": 1,
            "stop_seconds": 1,
        }
        sim_cfg.update(sim_overrides)

        cfg = {
            "provider": "sim",
            "sim": sim_cfg,
            "listen": "127.0.0.1",
            "port": self.pfoertner_port,
            "state_file": os.path.join(self.tmpdir.name, "state.json"),
            "check_seconds": 0.3,
            "observe_seconds": 0.2,
            "request_wait_seconds": 30,
            "login_log_service": "",
            "machines": {"kai1": machine_cfg},
        }
        cfg.update(app_overrides)
        return cfg

    def start_app(self, cfg):
        self.app = kai_pfoertner.KaiPfoertner(cfg)

        handler = kai_pfoertner.make_handler(self.app)
        self.server = ThreadingHTTPServer((self.app.listen, self.app.port), handler)
        self.server.daemon_threads = True

        self.loop_thread = threading.Thread(target=self.app.loop, daemon=True)
        self.loop_thread.start()

        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def base_url(self):
        return "http://127.0.0.1:%d" % self.pfoertner_port

    def http_json(self, method, path, body=None, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.pfoertner_port, timeout=15)
        try:
            headers = dict(headers or {})
            data = None
            if body is not None:
                data = json.dumps(body).encode("utf-8")
                headers["Content-Type"] = "application/json"
                headers["Content-Length"] = str(len(data))

            conn.request(method, path, body=data, headers=headers)
            resp = conn.getresponse()
            raw = resp.read()
            try:
                parsed = json.loads(raw.decode("utf-8", "replace"))
            except Exception:
                parsed = {"raw": raw.decode("utf-8", "replace")}
            return resp.status, parsed
        finally:
            conn.close()

    def http_raw(self, method, path, body=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.pfoertner_port, timeout=15)
        try:
            headers = {}
            data = None
            if body is not None:
                data = json.dumps(body).encode("utf-8")
                headers["Content-Type"] = "application/json"
                headers["Content-Length"] = str(len(data))

            conn.request(method, path, body=data, headers=headers)
            resp = conn.getresponse()
            raw = resp.read()
            return resp.status, raw
        finally:
            conn.close()

    def raw_http(self, method, path, body=None):
        sock = socket.create_connection(("127.0.0.1", self.pfoertner_port), timeout=15)
        try:
            lines = ["%s %s HTTP/1.1" % (method, path), "Host: 127.0.0.1"]
            data = None
            if body is not None:
                data = json.dumps(body).encode("utf-8")
                lines.append("Content-Type: application/json")
                lines.append("Content-Length: %d" % len(data))
            lines.append("Connection: close")
            request = ("\r\n".join(lines) + "\r\n\r\n").encode("ascii")
            if data:
                request += data

            sock.sendall(request)

            chunks = []
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
            return b"".join(chunks)
        finally:
            sock.close()

    def wait_for(self, predicate, timeout=10, interval=0.05):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return True
            time.sleep(interval)
        return False

    def status_snapshot(self, model=None):
        path = "/status"
        if model:
            path += "?model=" + urllib.parse.quote(model, safe="")
        status, obj = self.http_json("GET", path)
        self.assertEqual(status, 200)
        return obj

    def machine_phase(self):
        return self.status_snapshot()["machines"]["kai1"]["phase"]

    def provider_state(self):
        return self.app.provider.state("sim-1")

    def test_backend_api_key_from_file(self):
        # Backend requires a key; the pfoertner reads it from a dotenv file for its own probes
        # and the proxied request carries the client's header.
        self.backend.api_key = "sk-test"
        key_file = os.path.join(self.tmpdir.name, "env")
        with open(key_file, "w", encoding="utf-8") as f:
            f.write("OTHER=x\nLLAMA_SWAP_KEY=sk-test\n")
        cfg = self.make_config(api_key_file=key_file)
        self.start_app(cfg)
        machine = self.app.machines["kai1"]
        self.assertEqual(machine.api_key, "sk-test")
        self.assertTrue(machine._health_ok())
        status, body = self.http_json(
            "POST", "/kai1/v1/chat/completions", {"model": "b", "messages": []},
            headers={"Authorization": "Bearer sk-test"})
        self.assertEqual(status, 200, body)
        self.assertEqual(self.backend.loaded_models(), {"b"})

    def test_models_endpoint_does_not_wake(self):
        self.start_app(self.make_config())

        status, obj = self.http_json("GET", "/kai1/v1/models")
        self.assertEqual(status, 200)
        ids = sorted(item["id"] for item in obj["data"])
        self.assertEqual(ids, ["a", "b"])

        snap = self.status_snapshot()
        self.assertEqual(snap["machines"]["kai1"]["phase"], "off")
        self.assertEqual(self.provider_state(), "stopped")

    def test_non_stream_post_loads_requested_model(self):
        self.start_app(self.make_config())

        status, obj = self.http_json(
            "POST",
            "/kai1/v1/chat/completions",
            {"model": "b", "messages": [{"role": "user", "content": "hi"}]},
        )
        self.assertEqual(status, 200)
        self.assertEqual(obj["model"], "b")

        self.assertEqual(self.backend.loaded_models(), {"b"})

        snap = self.status_snapshot(model="b")
        self.assertEqual(snap["phase"], "ready")
        self.assertEqual(snap["percent"], 100)

    def test_stream_post_while_stopped(self):
        self.start_app(self.make_config())

        raw = self.raw_http(
            "POST",
            "/kai1/v1/chat/completions",
            {"model": "a", "stream": True, "messages": [{"role": "user", "content": "hi"}]},
        )

        header_end = raw.find(b"\r\n\r\n")
        self.assertGreater(header_end, 0)
        body = raw[header_end + 4 :]

        self.assertTrue(body.startswith(b": kai-pfoertner keep-alive"))
        self.assertIn(b"data: {", body)
        self.assertIn(b"data: [DONE]", body)
        self.assertEqual(body.count(b"HTTP/1.1"), 0)

    def test_two_concurrent_first_posts_start_once(self):
        self.start_app(self.make_config())

        original_start = self.app.provider.start
        start_calls = [0]
        lock = threading.Lock()

        def counted_start(iid):
            with lock:
                start_calls[0] += 1
            return original_start(iid)

        self.app.provider.start = counted_start

        results = []

        def request(model):
            status, _ = self.http_json(
                "POST",
                "/kai1/v1/chat/completions",
                {"model": model, "messages": [{"role": "user", "content": "hi"}]},
            )
            results.append(status)

        t1 = threading.Thread(target=request, args=("a",), daemon=True)
        t2 = threading.Thread(target=request, args=("b",), daemon=True)
        t1.start()
        t2.start()
        t1.join(timeout=20)
        t2.join(timeout=20)

        self.assertEqual(results, [200, 200])
        self.assertEqual(start_calls[0], 1)

    def test_idle_stop(self):
        self.start_app(
            self.make_config(
                idle_minutes=0.03,
                min_runtime_minutes=0,
            )
        )

        status, _ = self.http_json(
            "POST",
            "/kai1/v1/chat/completions",
            {"model": "a", "messages": [{"role": "user", "content": "hi"}]},
        )
        self.assertEqual(status, 200)

        self.assertTrue(
            self.wait_for(lambda: self.provider_state() == "stopped", timeout=6),
            "sim provider did not stop after idle timeout",
        )

    def test_hold_prevents_and_release_allows_stop(self):
        self.start_app(
            self.make_config(
                idle_minutes=0.03,
                min_runtime_minutes=0,
            )
        )

        status, _ = self.http_json(
            "POST",
            "/kai1/v1/chat/completions",
            {"model": "a", "messages": [{"role": "user", "content": "hi"}]},
        )
        self.assertEqual(status, 200)

        status, snap = self.http_json("POST", "/hold/kai1?minutes=1")
        self.assertEqual(status, 200)
        self.assertGreater(snap["hold_seconds"], 0)

        time.sleep(2.5)
        self.assertNotEqual(self.provider_state(), "stopped")

        status, snap = self.http_json("POST", "/hold/kai1?minutes=0")
        self.assertEqual(status, 200)
        self.assertEqual(snap["hold_seconds"], 0)

        self.assertTrue(
            self.wait_for(lambda: self.provider_state() == "stopped", timeout=6),
            "sim provider did not stop after hold release",
        )

    def test_capacity_retry(self):
        self.start_app(
            self.make_config(
                sim={"capacity_failures": 1},
                capacity_wait_seconds=1,
            )
        )

        status, obj = self.http_json(
            "POST",
            "/kai1/v1/chat/completions",
            {"model": "a", "messages": [{"role": "user", "content": "hi"}]},
        )
        self.assertEqual(status, 200)
        self.assertEqual(obj["model"], "a")

    def test_start_failure_returns_unavailable(self):
        self.start_app(
            self.make_config(
                start_timeout_seconds=2,
            )
        )

        self.backend.health_ok = False

        status, obj = self.http_json(
            "POST",
            "/kai1/v1/chat/completions",
            {"model": "a", "messages": [{"role": "user", "content": "hi"}]},
        )
        self.assertEqual(status, 503)
        self.assertEqual(obj["error"]["type"], "kai_pfoertner_unavailable")

        status, raw = self.http_raw(
            "POST",
            "/kai1/v1/chat/completions",
            {"model": "a", "stream": True, "messages": [{"role": "user", "content": "hi"}]},
        )
        self.assertEqual(status, 200)
        self.assertIn(b"kai_pfoertner_unavailable", raw)
        self.assertIn(b"data: [DONE]", raw)

    def test_inflight_blocks_idle_stop(self):
        self.start_app(
            self.make_config(
                idle_minutes=0.02,
                min_runtime_minutes=0,
            )
        )

        self.backend.slow = True

        conn = http.client.HTTPConnection("127.0.0.1", self.pfoertner_port, timeout=20)
        body = json.dumps(
            {
                "model": "a",
                "stream": True,
                "messages": [{"role": "user", "content": "hi"}],
            }
        ).encode("utf-8")
        conn.request(
            "POST",
            "/kai1/v1/chat/completions",
            body=body,
            headers={
                "Content-Type": "application/json",
                "Content-Length": str(len(body)),
            },
        )

        resp = conn.getresponse()
        self.assertEqual(resp.status, 200)

        first = resp.read1(4096)
        self.assertIn(b": kai-pfoertner keep-alive", first)

        self.assertTrue(
            self.wait_for(lambda: self.backend.request_count_value() > 0, timeout=10),
            "backend did not receive the slow request",
        )

        self.assertEqual(self.provider_state(), "running")

        rest = resp.read()
        self.assertIn(b"data: [DONE]", rest)
        conn.close()

        self.assertTrue(
            self.wait_for(lambda: self.provider_state() == "stopped", timeout=6),
            "sim provider did not stop after slow stream ended",
        )

    def test_status_by_model_and_boot_progress(self):
        self.start_app(self.make_config())

        status, obj = self.http_json("GET", "/status?model=b")
        self.assertEqual(status, 200)
        self.assertEqual(obj["machine"], "kai1")

        status, obj = self.http_json("GET", "/status?model=unknown")
        self.assertEqual(status, 404)

        status, snap = self.http_json("POST", "/wake/kai1?model=b")
        self.assertEqual(status, 200)

        seen_boot = False
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            snap = self.status_snapshot(model="b")
            if snap["phase"] in ("start", "boot", "service", "model"):
                self.assertGreaterEqual(snap["percent"], 0)
                self.assertLess(snap["percent"], 100)
                self.assertGreater(snap["eta_seconds"], 0)
                seen_boot = True
                break
            time.sleep(0.05)

        self.assertTrue(seen_boot, "did not observe a non-ready boot phase")

    def test_wake_api_returns_immediately(self):
        self.start_app(self.make_config())

        started = time.monotonic()
        status, snap = self.http_json("POST", "/wake/kai1?model=b")
        elapsed = time.monotonic() - started

        self.assertEqual(status, 200)
        self.assertLess(elapsed, 1.0)

        self.assertTrue(
            self.wait_for(lambda: self.status_snapshot(model="b")["phase"] == "ready", timeout=10),
            "machine did not become ready after wake",
        )
        self.assertEqual(self.backend.loaded_models(), {"b"})

    def test_proxied_response_has_no_duplicate_headers(self):
        # strict clients (aiohttp, used by LiteLLM) reject a duplicate Server or Date header
        self.start_app(self.make_config())
        conn = http.client.HTTPConnection("127.0.0.1", self.pfoertner_port, timeout=30)
        body = json.dumps({"model": "a", "messages": [{"role": "user", "content": "hi"}]}).encode("utf-8")
        conn.request("POST", "/kai1/v1/chat/completions", body=body,
                     headers={"Content-Type": "application/json", "Content-Length": str(len(body))})
        resp = conn.getresponse()
        resp.read()
        names = [k.lower() for k, _ in resp.getheaders()]
        conn.close()
        self.assertEqual(resp.status, 200)
        for name in ("server", "date", "content-type"):
            self.assertLessEqual(names.count(name), 1, name)



if __name__ == "__main__":
    unittest.main()
