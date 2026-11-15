"""Rebuild the review inventory from the seven supplied result refs."""
import collections, csv, hashlib, io, json, pathlib, subprocess
out = pathlib.Path(__file__).parent

def git(*args):
    return subprocess.check_output(['git', *args])

refs = [r for r in git('for-each-ref', '--format=%(refname:short)').decode().splitlines()
        if r.startswith(('res/43656622522-', 'res/43656625337-'))]
manifest = {'harness_start': '7eb1461f1a0c7bd057731c45b02351ed59b4355e',
            'harness_fix': 'e0d7dd8c342ede845b026e0dd815ac6e3bf4f228', 'branches': [], 'failed_logs': []}
errors, failures, causes, infrastructure = [], [], [], []
for ref in refs:
    files = git('ls-tree', '-r', '--name-only', ref).decode().splitlines()
    record = {'ref': ref, 'commit': git('rev-parse', ref).decode().strip(), 'verdict_files': {}, 'files': {}}
    for name in files:
        raw = git('show', ref + ':' + name)
        record['files'][name] = {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
        if name == 'workflow-status.json':
            record['workflow_status'] = json.loads(raw)
        if name.endswith('verdicts.csv'):
            rows = list(csv.DictReader(io.StringIO(raw.decode())))
            record['verdict_files'][name] = dict(collections.Counter(r['status'] for r in rows))
            for row in rows:
                if row['status'] in ('FAIL', 'ERROR'):
                    failures.append(dict(ref=ref, file=name, classification='harness', **row))
        # Each captured error once, excluding duplicate steps/summary/Java stacks.
        if name.endswith('.txt') and any(k in name for k in ('scenario-', '-path.', '-O-install.', '-O-run.', '-O-old')):
            lines = raw.decode(errors='replace').splitlines()
            for i, line in enumerate(lines, 1):
                if not line.startswith('ERROR '):
                    continue
                if '-path.' in name:
                    classification, disposition = 'harness', 'H2: absent old installation left no published profile; A/A4 are not a valid upgrade experiment'
                else:
                    classification = 'expected product refusal (no defect)'
                    if 'O6 native request' in line: disposition = 'O6: old server cannot execute native language-2 plans'
                    elif 'scenario-D' in name: disposition = 'D: no registered physical achilles_results fixture'
                    elif 'G-old' in name: disposition = 'O2/O3: old client must upgrade its protected-release protocol'
                    elif 'ERROR G6:' in line: disposition = 'G6: duplicate logical source/noise domain cannot be pooled'
                    elif 'ERROR S1:' in line: disposition = 'G3d3: analyst-supplied generation/epoch fields refused'
                    elif 'all-null' in line: disposition = 'G10: all-null numeric population refused by final support gate'
                    elif 'ERROR S4' in line: disposition = 'G3a4/G3a6: DP-only mode refuses realised-sticky routes'
                    elif 'ERROR S5' in line: disposition = 'G9: disabled community tools refuse before argument access'
                    elif 'ERROR Reader handle 3:' in line: disposition = 'G20c: intentionally failed generation read; same handle later recovers'
                    elif 'ERROR G13' in line: disposition = 'G13b: deliberately killed connections fail whole request; recovery checked by G13 after'
                    else: raise AssertionError((ref, name, i, line))
                errors.append(dict(ref=ref, file=name, line=i, classification=classification,
                                   disposition=disposition, message=line))
        if name.endswith('opal.log'):
            for i, line in enumerate(raw.decode(errors='replace').splitlines(), 1):
                if 'ERROR ' in line and 'consuming R command' not in line:
                    installation = 'Error when installing a package' in line
                    infrastructure.append(dict(ref=ref, file=name, line=i, classification='harness',
                        disposition='H1: GitHub API 403 prevents old-server install' if installation else
                        'Opal service startup/restart exception; later scenario/service checks recover; no dsOMOP defect',
                        message=line))
                if 'API rate limit exceeded' in line:
                    causes.append(f'{ref}:{name}:{i}\n{line}\n')
    manifest['branches'].append(record)
for run in ('43656622522', '43656625337'):
    p = pathlib.Path('/workspace/dsomop/design/astra-dev/contract-logs') / (run + '-failed.log')
    raw = p.read_bytes()
    manifest['failed_logs'].append(dict(path=str(p), bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))
for package in ('dsOMOP', 'dsOMOPClient'):
    manifest[package] = subprocess.check_output(['git', '-C', '/workspace/dsomop/wt/r205/' + package, 'rev-parse', 'HEAD']).decode().strip()
(out / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
for name, rows in [('captured-errors.csv', errors), ('failing-verdicts.csv', failures), ('infrastructure-errors.csv', infrastructure)]:
    with (out / name).open('w') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n"); w.writeheader(); w.writerows(rows)
(out / 'root-causes.txt').write_text('\n'.join(causes))
ref = 'res/43656622522-1-opal-5.7.6-upgrade-candidate'
(out / 'contract-install-failure.txt').write_bytes(git('show', ref + ':upgrade-O-install.txt') +
    b'\nLast workflow step lines:\n' + b'\n'.join(git('show', ref + ':upgrade-steps.log').splitlines()[-12:]) + b'\n')
ref = 'res/43656625337-upgrade-candidate'
(out / 'e2e-absent-old-install.txt').write_bytes(b'\n'.join(git('show', ref + ':upgrade-path.txt').splitlines()[:11]) + b'\n')
print('Branches:', len(refs), 'failing verdicts:', len(failures), 'GitHub 403 evidence:', len(causes))
print('Captured errors:', dict(collections.Counter(r['classification'] for r in errors)))
for rec in manifest['branches']:
    print(rec['ref'], rec['verdict_files'], rec.get('workflow_status', {}).get('JOB_STATUS', ''))

# Normalize presentation-only whitespace; original artifact hashes are above.
for path in out.iterdir():
    if path.suffix in (".txt", ".log"):
        path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
