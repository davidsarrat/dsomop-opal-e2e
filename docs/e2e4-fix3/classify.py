"""Reproduce the contract failure and scenario verdict inventory from saved inputs."""
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path

out = Path(__file__).resolve().parent
log = out / "43472800948-failed.log"
jobs = {}
for number, line in enumerate(log.read_text().splitlines(), 1):
    job, step, text = line.split("\t", 2)
    record = jobs.setdefault(job, dict(steps=set(), exceptions=[], exits=[]))
    record['steps'].add(step)
    if "json.decoder.JSONDecodeError: Extra data" in text:
        record['exceptions'].append(number)
    if "##[error]Process completed with exit code 1." in text:
        record['exits'].append(number)
assert set(jobs) == {f"opal ({version}, {path})"
                     for version in ("5.7.6", "6.1.3") for path in ("fresh", "upgrade")}
findings = []
coverage = []
for job, record in sorted(jobs.items()):
    assert record['steps'] == {"Pinned Opal and Rock"}
    assert len(record['exceptions']) == len(record['exits']) == 1
    findings.append(dict(run="43472800948", job=job, classification="harness",
                         finding="H-version-text", evidence=f"{log.name}:{record['exceptions'][0]}",
                         fix="29901ea", test="scripts/tests/o-stack.py",
                         reason="Version endpoint is plain text; json.load aborts before package installation"))
    coverage.extend(dict(run="43472800948", job=job, scenario=f"O{n}",
                         outcome="NOT-EXERCISED", reason="bootstrap failed before scenarios")
                    for n in range(1, 13))

def write_csv(name, rows):
    with (out / name).open('w') as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)

write_csv('classification.csv', findings)
write_csv('contract-coverage.csv', coverage)
verdicts = {}
for file in sorted(out.glob('*-verdicts.csv')):
    rows = list(csv.DictReader(file.open()))
    counts = dict(Counter(row['status'] for row in rows))
    assert counts.get('FAIL', 0) == counts.get('ERROR', 0) == 0, file
    verdicts[file.name] = counts
summary = dict(contract_failed_jobs=len(findings), contract_scenarios_unexercised=len(coverage),
               contract_log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(),
               e2e_verdicts=verdicts,
               e2e_workflow_conclusion="unverified; captured checks have no failures; API inaccessible")
(out / 'classification-summary.json').write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps(summary, indent=2))
