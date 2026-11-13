"""Failure-path workflow tests. Requires PyYAML for reading the actual workflow.

All git operations, including push, are intercepted by a disposable stand-in.
"""
import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


WORKFLOW = yaml.safe_load(Path('.github/workflows/opal-contract.yml').read_text())
JOB = WORKFLOW['jobs']['opal']
STEPS = JOB['steps']
EVIDENCE = next(s for s in STEPS if s.get('id') == 'evidence')
PUBLISH = next(s for s in STEPS if s.get('run') == 'bash scripts/o/publish-results.sh')
ARTIFACT = next(s for s in STEPS if s.get('uses', '').startswith('actions/upload-artifact@'))
SECRETS = dict(OPAL_ADMIN_PW='test/admin.$&[pw]', ANALYST_PW='test analyst secret',
               ANALYST2_PW='test second secret', OMOPDB_PW='test database secret',
               READER_PW='test reader secret', GITHUB_PAT='test token secret')


class ResultsTests(unittest.TestCase):
    def run_workflow_tail(self, version='6.1.3', path='fresh', attempt='1', failed_step='stack',
                          missing_out=False, no_passwords=False, push_fails=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out = root / 'out'
            if not missing_out:
                out.mkdir()
                (out / 'raw-response.last').write_bytes(b'\xff' + '|'.join(SECRETS.values()).encode())
            commands = {
                'docker': '''#!/bin/bash
printf '%s\\n' "${OPAL_ADMIN_PW:-}" "${GITHUB_PAT:-}"
echo 'container unavailable'
exit 1
''',
                'Rscript': '#!/bin/bash\necho "R fixture failure"\nexit 7\n',
                'git': '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['MOCK_ROOT'])
with (root / 'git-calls').open('a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1] == 'push' and os.environ['MOCK_PUSH_FAILS'] == '1':
    raise SystemExit(1)
''',
            }
            for name, body in commands.items():
                command = root / name
                command.write_text(body)
                command.chmod(0o755)
            env = dict(os.environ, **SECRETS)
            if no_passwords:
                for key in SECRETS:
                    if key.endswith('_PW'):
                        env.pop(key, None)
                env['ANALYST_PW'] = ''
            env.update(PATH=str(root) + os.pathsep + os.environ['PATH'], OUT=str(out),
                       MOCK_ROOT=str(root), MOCK_PUSH_FAILS=str(int(push_fails)), STACK='e2e',
                       OPAL_URL='http://127.0.0.1:1', OPAL_VERSION=version, E2E_PATH=path,
                       MODE='candidate', GITHUB_RUN_ID='123', GITHUB_RUN_ATTEMPT=attempt,
                       GITHUB_REPOSITORY='test/test', GITHUB_SHA='test-source-sha',
                       GITHUB_ENV=str(root / 'env'), JOB_STATUS='failure',
                       STEPS_JSON=json.dumps({failed_step: {'outcome': 'failure', 'conclusion': 'failure'},
                                             'scenarios': {'outcome': 'skipped'}}))
            def run(step):
                return subprocess.run(['bash', '--noprofile', '--norc', '-eo', 'pipefail', '-c', step['run']],
                                      env=env, capture_output=True, text=True, timeout=15)
            failed = None
            if not missing_out:
                failed = run(next(s for s in STEPS if s.get('id') == failed_step))
            collected = run(EVIDENCE)
            published = run(PUBLISH) if collected.returncode == 0 else None
            return dict(failed=failed, collected=collected, published=published,
                        calls=[json.loads(line) for line in (root / 'git-calls').read_text().splitlines()]
                              if (root / 'git-calls').exists() else [],
                        files={str(p.relative_to(out)): p.read_bytes() for p in out.rglob('*') if p.is_file()})

    def test_failed_startup_publishes_four_distinct_results(self):
        branches = set()
        for version, path in itertools.product(JOB['strategy']['matrix']['opal'],
                                               JOB['strategy']['matrix']['path']):
            with self.subTest(version=version, path=path):
                result = self.run_workflow_tail(version=version, path=path)
                self.assertNotEqual(result['failed'].returncode, 0)
                self.assertEqual(result['collected'].returncode, 0, result['collected'].stderr)
                self.assertEqual(result['published'].returncode, 0, result['published'].stderr)
                pushes = [call for call in result['calls'] if call[0] == 'push']
                self.assertEqual(len(pushes), 1)
                branches.add(pushes[0][-1])
                self.assertIn(f'HEAD:refs/heads/results/123-1-opal-{version}-{path}-candidate', branches)
                status = json.loads(result['files']['workflow-status.json'])
                self.assertEqual(status['JOB_STATUS'], 'failure')
                self.assertEqual(status['steps']['stack']['outcome'], 'failure')
                self.assertEqual(status['steps']['scenarios']['outcome'], 'skipped')
                self.assertEqual(status['GITHUB_SHA'], 'test-source-sha')
                self.assertIn(f'{path}-steps.log', result['files'])
                self.assertIn('[collector exit=1]', result['files']['opal.log'].decode())
                for content in result['files'].values():
                    for secret in SECRETS.values():
                        self.assertNotIn(secret.encode(), content)
                self.assertIn(b'\xff***', result['files']['raw-response.last'])
        self.assertEqual(len(branches), 4)

    def test_failed_r_install_still_publishes_with_failure_log(self):
        result = self.run_workflow_tail(failed_step='dependencies')
        self.assertEqual(result['failed'].returncode, 7)
        self.assertEqual(result['published'].returncode, 0)
        self.assertIn(b'R fixture failure', result['files']['fresh-steps.log'])

    def test_failure_before_output_and_password_setup(self):
        result = self.run_workflow_tail(missing_out=True, no_passwords=True, failed_step='candidate')
        self.assertEqual(result['collected'].returncode, 0, result['collected'].stderr)
        self.assertEqual(result['published'].returncode, 0)
        self.assertIn(b'container unavailable', result['files']['opal.log'])
        self.assertNotIn(SECRETS['GITHUB_PAT'].encode(), result['files']['opal.log'])

    def test_rerun_does_not_overwrite_previous_attempt(self):
        result = self.run_workflow_tail(attempt='2')
        push = next(call for call in result['calls'] if call[0] == 'push')
        self.assertEqual(push[-1], 'HEAD:refs/heads/results/123-2-opal-6.1.3-fresh-candidate')
        self.assertNotIn('--force', push)

    def test_push_failure_remains_failure_with_evidence_for_artifact(self):
        result = self.run_workflow_tail(push_fails=True)
        self.assertNotEqual(result['published'].returncode, 0)
        self.assertIn('workflow-status.json', result['files'])
        self.assertEqual(ARTIFACT['if'], "always() && steps.evidence.outcome == 'success'")

    def test_old_client_check_runs_after_scenario_failure_but_requires_setup(self):
        old_client = next(s for s in STEPS if s.get('id') == 'old_client')
        self.assertEqual(old_client['if'], "always() && steps.probes.outcome == 'success'")

    def test_workflow_finalizers_do_not_depend_on_product_success(self):
        self.assertEqual(WORKFLOW['permissions']['contents'], 'write')
        self.assertFalse(JOB['strategy']['fail-fast'])
        self.assertEqual(JOB['defaults']['run']['shell'], 'bash')
        self.assertEqual(EVIDENCE['if'], 'always()')
        self.assertEqual(PUBLISH['if'], "always() && steps.evidence.outcome == 'success'")
        self.assertEqual(EVIDENCE['env']['STEPS_JSON'], '${{ toJSON(steps) }}')
        self.assertEqual(EVIDENCE['env']['JOB_STATUS'], '${{ job.status }}')
        self.assertEqual(STEPS[-1]['if'], 'always()')
        self.assertLess(STEPS.index(PUBLISH), STEPS.index(ARTIFACT))
        self.assertTrue(ARTIFACT['continue-on-error'])
        for step in STEPS:
            if step is not ARTIFACT:
                self.assertFalse(step.get('continue-on-error', False))
            if 'run' in step:
                syntax = subprocess.run(['bash', '-n'], input=step['run'], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)


if __name__ == '__main__':
    unittest.main()
