#!/usr/bin/env python3
"""Index the complete retained run, including every archived server log."""
import csv, datetime, hashlib, json, pathlib, re, sys
base = pathlib.Path(sys.argv[1])
out = pathlib.Path(__file__).resolve().parent

def classification(text, file):
    if 'Cohort definition 1 not found' in text:
        return 'harness diagnostic', 'expected-refusal', 'explicit absent-definition negative control; correctly reported REFUSED'
    if 'achilles_results' in text or 'physical OHDSI result contract' in text:
        return 'harness diagnostic', 'expected-refusal', 'GiBleed deliberately has no physical result table; refusal is correct'
    if 'year_of_birth' in text:
        return 'harness diagnostic', 'expected-refusal', 'sensitive profiling negative control; no product repair'
    if any(t in text for t in ['G6:', 'Duplicate logical source', 'DP noise domain', 'S1:', 'server-owned', 'unknown parameter(s)', 'all-null', 'Disclosive:', 'S4 DP-only', 'no fixed-synopsis', 'S5:', 'disabled on this server', 'Reader handle 3:', 'G13 loads', 'generation could not be read', 'snapshot was lost', 'old client:', 'dsOMOPClient 2.10.2', 'omopDpStatusDS("dsomop-protected-release-v1")', 'omopDpStatusDS()']):
        return 'harness diagnostic', 'expected-refusal', 'intentional negative control; preserve product fail-closed behavior'
    if any(t in text for t in ['RSessionService - Error while connecting to R (127.0.0.1:7311)', 'RServerService - Error while connecting to R: Cannot connect: Connection refused', 'Cannot retrieve all Datashield packages properties', 'Error when reading installed DataSHIELD packages', 'Error when reading installed packages', 'AuthenticationFilter', 'initialize profile', 'Error when reading R server state', 'No R server is available', 'No active R server', 'sqldf', 'Pool size', 'Error while invoking all R servers', 'Error when reading R server resource providers']):
        return 'harness environment', 'stack-lifecycle', 'external stack startup or deliberate Rock restart; later readiness/replay passes'
    return 'UNCLASSIFIED', '', ''

# Correlate structured audit wrappers (which omit the R reason) with the
# nearest Opal ERROR at the same time. Keep the wrapper's original evidence.
server_errors = {}
for path in ('fresh', 'upgrade'):
    errors = []
    for line in (base / (path+'-opal-srv-logs') / 'opal.log').read_text().splitlines():
        if '] ERROR ' in line:
            try: errors.append((datetime.datetime.strptime(line[:23], '%Y-%m-%d %H:%M:%S,%f'), line))
            except ValueError: pass
    server_errors[path] = errors
rows=[]; manifest=[]
for p in sorted(base.rglob('*')):
    if not p.is_file(): continue
    data=p.read_bytes(); rel=str(p.relative_to(base))
    manifest.append(dict(file=rel, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
    if p.suffix not in ('.txt','.log'): continue
    lines=data.decode(errors='replace').splitlines()
    for i,l in enumerate(lines,1):
        if not (re.search(r'(^ERROR |^Error\b|^\d{4}-\d{2}-\d{2} .*?\b(?:ERROR|FATAL)\b|"level":"ERROR")',l) or re.search(r'\b(?:FAIL|ERROR):',l)): continue
        if l.startswith('SUMMARY ') or (l.startswith('[') and 'summary' not in rel): continue
        # The old-server refusal has its reason on the following log line.
        context=l+' '+(' '.join(lines[i:i+2]) if l.rstrip().endswith(':') else '')
        if l.startswith('Error : Disclosive:'):
            context += ' ' + ' '.join(lines[max(0,i-4):i-1])
        if l.startswith('{'):
            event = json.loads(l)
            stamp = datetime.datetime.strptime(event['@timestamp'][:23], '%Y-%m-%dT%H:%M:%S.%f')
            candidates = server_errors[rel.split('-')[0]]
            nearest = min(candidates, key=lambda item: abs((item[0]-stamp).total_seconds()))
            if abs((nearest[0]-stamp).total_seconds()) < 2:
                context += ' '+nearest[1]
        cat,code,why=classification(context,rel)
        rows.append(dict(file=rel,line=i,classification=cat,finding=code,reason=why,evidence=l.rstrip()))
with (out/'all-errors.csv').open('w') as f:
    w=csv.DictWriter(f,fieldnames=['file','line','classification','finding','reason','evidence'],lineterminator='\n');w.writeheader();w.writerows(rows)
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
unknown=[r for r in rows if r['classification']=='UNCLASSIFIED']
print('Indexed',len(rows),'error/failure headings;',len(unknown),'unclassified')
for r in unknown:print(r['file'],r['line'],r['evidence'][:500])

sys.exit(bool(unknown))
