"""Exercise the real bootstrap script with disposable Docker/HTTP stand-ins."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class StackTests(unittest.TestCase):
    def run_stack(self, version="6.1.3", response=None, fail_first=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "out").mkdir()
            commands = {
                "docker": """#!/bin/bash
printf '%s\\n' "$*" >> "$MOCK_ROOT/docker-calls"
case "$1" in
  inspect) echo e2e_default ;;
  image) echo '["sha256:test"]' ;;
esac
""",
                "curl": """#!/usr/bin/env python3
import os
from pathlib import Path
root = Path(os.environ['MOCK_ROOT'])
counter = root / 'attempts'
n = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(n))
if n <= int(os.environ['MOCK_FAIL_FIRST']):
    print('partial failed response')
    raise SystemExit(22)
print(os.environ['MOCK_RESPONSE'])
""",
                "sleep": "#!/bin/bash\nexit 0\n",
            }
            for name, body in commands.items():
                path = root / name
                path.write_text(body)
                path.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       MOCK_ROOT=str(root), MOCK_FAIL_FIRST=str(fail_first),
                       MOCK_RESPONSE=version if response is None else response,
                       OPAL_VERSION=version, OPAL_ADMIN_PW="test-only", STACK="e2e",
                       OPAL_URL="http://localhost:8880", OUT=str(root / "out"),
                       GITHUB_ENV=str(root / "github-env"))
            result = subprocess.run(["bash", os.environ.get("O_STACK_SCRIPT", "scripts/o/stack.sh")],
                                    env=env, capture_output=True, text=True, timeout=15)
            return dict(result=result,
                        exports=(root / "github-env").read_text() if (root / "github-env").exists() else "",
                        calls=(root / "docker-calls").read_text() if (root / "docker-calls").exists() else "",
                        attempts=int((root / "attempts").read_text()) if (root / "attempts").exists() else 0,
                        files={p.name: p.read_text() for p in (root / "out").iterdir()})

    def test_plain_text_versions_for_both_pins(self):
        for version in ("6.1.3", "5.7.6"):
            with self.subTest(version=version):
                run = self.run_stack(version)
                self.assertEqual(run['result'].returncode, 0, run['result'].stderr)
                self.assertIn("ROCK=e2e-rock\n", run['exports'])
                self.assertIn("STACK_NET=e2e_default\n", run['exports'])
                self.assertEqual(run['files']['opal-version.txt'].strip(), version)
                self.assertIn('image-digests.jsonl', run['files'])

    def test_transient_http_failure_then_ready(self):
        run = self.run_stack(fail_first=2)
        self.assertEqual(run['result'].returncode, 0, run['result'].stderr)
        self.assertEqual(run['attempts'], 3)
        self.assertEqual(run['files']['opal-version.txt'].strip(), "6.1.3")

    def test_exhausted_readiness_does_not_export_a_stack(self):
        run = self.run_stack(fail_first=90)
        self.assertNotEqual(run['result'].returncode, 0)
        self.assertEqual(run['attempts'], 90)
        self.assertIn("Opal version endpoint did not become ready", run['result'].stderr)
        self.assertEqual(run['exports'], "")
        self.assertNotIn("image inspect", run['calls'])

    def test_invalid_or_wrong_response_is_never_accepted(self):
        for response in ("", "<html>Login</html>", "6.2.1", "16.1.3", "6.1.30",
                         "6.1.3-SNAPSHOT", "error: expected 6.1.3", '"6.1.3"'):
            with self.subTest(response=response):
                run = self.run_stack(response=response)
                self.assertNotEqual(run['result'].returncode, 0)
                self.assertIn("Unexpected Opal version", run['result'].stderr)
                self.assertEqual(run['exports'], "")

    def test_unreviewed_pin_fails_before_provisioning(self):
        run = self.run_stack(version="6.2.1")
        self.assertNotEqual(run['result'].returncode, 0)
        self.assertEqual(run['calls'], "")
        self.assertEqual(run['attempts'], 0)


if __name__ == "__main__":
    unittest.main()
