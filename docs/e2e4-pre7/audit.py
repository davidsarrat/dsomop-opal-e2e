"""Offline input/result audit; uses only the already-downloaded refs and logs."""
import csv
import hashlib
import io
import json
from pathlib import Path
import subprocess


def git(*args):
    return subprocess.check_output(['git', *args])


logs = Path('/workspace/dsomop/design/astra-dev/contract-logs')
audit = {'harness_base': git('rev-parse', 'e5322cb').decode().strip(), 'harness_tested': git('rev-parse', 'd784164').decode().strip(), 'logs': [], 'results': []}
for path in sorted(logs.glob('*-failed.log')):
    data = path.read_bytes()
    audit['logs'].append(dict(name=path.name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
for branch in git('for-each-ref', '--format=%(refname:short)', 'refs/remotes/res').decode().splitlines():
    if not any(run in branch for run in ('434728', '434836', '434932', '435067')):
        continue
    entry = dict(branch=branch, commit=git('rev-parse', branch).decode().strip(), verdicts={})
    paths = git('ls-tree', '-r', '--name-only', branch).decode().splitlines()
    for path in paths:
        if path == 'workflow-status.json':
            entry['workflow'] = json.loads(git('show', branch + ':' + path))
        if 'verdicts' in path and path.endswith('.csv'):
            rows = list(csv.DictReader(io.StringIO(git('show', branch + ':' + path).decode())))
            entry['verdicts'][path] = rows
    audit['results'].append(entry)
Path('docs/e2e4-pre7/input-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
comparison = {}
for name in ('dsOMOP', 'dsOMOPClient'):
    product = Path('/workspace/dsomop/wt/int') / name
    tracked = subprocess.check_output(['git', '-C', str(product), 'ls-files', '-z']).decode().split('\0')
    comparison[name] = dict(commit=subprocess.check_output(['git', '-C', str(product), 'rev-parse', 'HEAD']).decode().strip(),
        files=len([p for p in tracked if p]), mismatches=[p for p in tracked if p and
            (not (Path('pkgs') / name / p).exists() or (product / p).read_bytes() != (Path('pkgs') / name / p).read_bytes())])
Path('docs/e2e4-pre7/vendor-comparison.json').write_text(json.dumps(comparison, indent=2) + '\n')
print(json.dumps(comparison, indent=2))
