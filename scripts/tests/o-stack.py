"""Run the real bootstrap and curl against a disposable local HTTP server."""
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import unittest


READY = json.dumps([{"name": "default", "servers": [{"running": True}]}])


class StackTests(unittest.TestCase):
    def run_stack(self, version="6.1.3", versions=None, clusters=None, network="e2e_default",
                  docker_failure="", attempts=4):
        responses = {
            "/ws/system/version": versions or [(200, version)],
            "/ws/service/r/clusters": clusters or [(200, READY)],
        }
        requests = []
        counts = Counter()

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                requests.append((self.path, self.headers.get("Accept")))
                sequence = responses[self.path]
                status, body = sequence[min(counts[self.path], len(sequence) - 1)]
                counts[self.path] += 1
                if status == "reset":
                    self.connection.shutdown(socket.SHUT_RDWR)
                    self.connection.close()
                    return
                self.send_response(200 if status == "partial" else status)
                data = body.encode()
                self.send_header("Content-Length", len(data) + (10 if status == "partial" else 0))
                self.end_headers()
                self.wfile.write(data)

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01})
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                docker = root / "docker"
                docker.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$MOCK_ROOT/docker-calls"
[ "$1" != "$MOCK_DOCKER_FAILURE" ] || exit 1
case "$1" in
  inspect) printf '%s\\n' "$MOCK_NETWORK" ;;
  image) echo '["sha256:test"]' ;;
esac
''')
                docker.chmod(0o755)
                env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                           MOCK_ROOT=str(root), MOCK_NETWORK=network, MOCK_DOCKER_FAILURE=docker_failure,
                           OPAL_VERSION=version, OPAL_ADMIN_PW="test-only", STACK="e2e",
                           OPAL_URL=f"http://127.0.0.1:{server.server_port}", OUT=str(root / "out"),
                           OPAL_READY_ATTEMPTS=str(attempts), OPAL_READY_INTERVAL="0",
                           GITHUB_ENV=str(root / "github-env"))
                result = subprocess.run(["bash", "scripts/o/stack.sh"], env=env,
                                        capture_output=True, text=True, timeout=15)
                return dict(result=result, requests=requests, counts=counts,
                            exports=(root / "github-env").read_text() if (root / "github-env").exists() else "",
                            calls=(root / "docker-calls").read_text() if (root / "docker-calls").exists() else "",
                            files={p.name: p.read_text() for p in (root / "out").glob("*")})
        finally:
            server.shutdown()
            thread.join()
            server.server_close()

    def test_plain_text_versions_for_both_pins(self):
        for version in ("6.1.3", "5.7.6"):
            with self.subTest(version=version):
                run = self.run_stack(version, versions=[(200, f" {version}\n")])
                self.assertEqual(run['result'].returncode, 0, run['result'].stderr)
                self.assertEqual(run['exports'], "STACK_NET=e2e_default\nROCK=e2e-rock\n")
                self.assertEqual(run['files']['opal-version.txt'].strip(), version)
                self.assertEqual(run['files']['opal-clusters.json'], READY)
                self.assertIn('image-digests.jsonl', run['files'])
                self.assertEqual(run['requests'], [("/ws/system/version", "text/plain"),
                                                  ("/ws/service/r/clusters", "application/json")])

    def test_transient_http_and_transport_failures_then_ready(self):
        run = self.run_stack(versions=[("reset", ""), (400, "400 Bad Request"), (200, "6.1.3")],
                             clusters=[("partial", READY), (503, "starting"), (200, READY)])
        self.assertEqual(run['result'].returncode, 0, run['result'].stderr)
        self.assertEqual(list(run['counts'].values()), [3, 3])
        self.assertEqual(run['files']['opal-clusters.json'], READY)

    def test_malformed_successful_responses_then_ready(self):
        run = self.run_stack(versions=[(200, "<html>starting</html>"), (200, ""), (200, "6.1.3")],
                             clusters=[(200, "6.1.3"), (200, '{"error":"starting"}'), (200, READY)])
        self.assertEqual(run['result'].returncode, 0, run['result'].stderr)
        self.assertEqual(list(run['counts'].values()), [3, 3])

    def test_redirect_is_not_readiness_even_with_expected_body(self):
        run = self.run_stack(versions=[(302, "6.1.3")])
        self.assertNotEqual(run['result'].returncode, 0)
        self.assertEqual(run['exports'], "")
        self.assertIn("http_status=302", run['files']['opal-version.txt.http'])

    def test_exhausted_readiness_does_not_export_a_stack(self):
        for kind in ("version", "clusters"):
            with self.subTest(kind=kind):
                kwargs = {"versions" if kind == "version" else "clusters": [(400, "not ready")]}
                run = self.run_stack(**kwargs, attempts=90)
                self.assertNotEqual(run['result'].returncode, 0)
                endpoint = "/ws/system/version" if kind == "version" else "/ws/service/r/clusters"
                self.assertEqual(run['counts'][endpoint], 90)
                self.assertIn(f"Opal {kind} endpoint did not become ready after 90 attempts", run['result'].stderr)
                self.assertEqual(run['exports'], "")
                self.assertNotIn("image inspect", run['calls'])

    def test_wrong_version_fails_immediately(self):
        for response in ("6.2.1", "16.1.3", "6.1.30", "6.1.3-SNAPSHOT"):
            with self.subTest(response=response):
                run = self.run_stack(versions=[(200, response)])
                self.assertNotEqual(run['result'].returncode, 0)
                self.assertIn("Unexpected Opal version", run['result'].stderr)
                self.assertEqual(sum(run['counts'].values()), 1)
                self.assertEqual(run['exports'], "")

    def test_invalid_body_is_never_accepted(self):
        for response in ("", "<html>Login</html>", "error: expected 6.1.3", '"6.1.3"'):
            with self.subTest(response=response):
                run = self.run_stack(versions=[(200, response)])
                self.assertNotEqual(run['result'].returncode, 0)
                self.assertEqual(run['exports'], "")
                self.assertNotIn("Traceback", run['result'].stderr)
                self.assertNotIn("opal-version.txt", run['files'])

    def test_cluster_requires_running_default_server(self):
        invalid = ["", "<html>not ready</html>", "null", "{}", "[]", '[null]',
                   '[{"name":"default","servers":null}]',
                   '[{"name":"default","servers":[null]}]',
                   '[{"name":"default","servers":[{"running":false}]}]',
                   '[{"name":"default","servers":[{"running":"true"}]}]',
                   '[{"name":"other","servers":[{"running":true}]}]']
        for response in invalid:
            with self.subTest(response=response):
                run = self.run_stack(clusters=[(200, response)])
                self.assertNotEqual(run['result'].returncode, 0)
                self.assertIn("Opal clusters endpoint did not become ready", run['result'].stderr)
                self.assertEqual(run['exports'], "")
                self.assertNotIn("opal-clusters.json", run['files'])
                self.assertEqual(run['files']['opal-clusters.json.last'], response)

    def test_docker_failures_do_not_export_stack(self):
        for kwargs in ({"network": ""}, {"docker_failure": "compose"}, {"docker_failure": "image"}):
            with self.subTest(kwargs=kwargs):
                run = self.run_stack(**kwargs)
                self.assertNotEqual(run['result'].returncode, 0)
                self.assertEqual(run['exports'], "")

    def test_unreviewed_pin_fails_before_provisioning(self):
        run = self.run_stack(version="6.2.1")
        self.assertNotEqual(run['result'].returncode, 0)
        self.assertEqual(run['calls'], "")
        self.assertEqual(sum(run['counts'].values()), 0)


if __name__ == "__main__":
    unittest.main()
