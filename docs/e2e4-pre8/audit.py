"""Audit downloaded gate evidence offline; run from the harness repository root."""
from collections import Counter
import csv
import hashlib
import io
import json
from pathlib import Path
import subprocess


def git(*args):
    return subprocess.check_output(["git", *args])


destination = Path(__file__).parent
tested = git("rev-parse", "17e5df4").decode().strip()
audit = {"harness_tested": tested, "logs": [], "results": []}
for path in sorted(Path("/workspace/dsomop/design/astra-dev/contract-logs").glob("*-failed.log")):
    data = path.read_bytes()
    audit["logs"].append(dict(name=path.name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))

refs = git("for-each-ref", "--format=%(refname)", "refs/remotes/res").decode().splitlines()
latest_contract = []
failed_contract = []
for ref in refs:
    if not any(run in ref for run in ("43506711667", "43515122503", "43515127555")):
        continue
    commit = git("rev-parse", ref).decode().strip()
    entry = dict(ref=ref, commit=commit, verdicts={})
    paths = git("ls-tree", "-r", "--name-only", commit).decode().splitlines()
    for path in paths:
        if path == "workflow-status.json":
            entry["workflow"] = json.loads(git("show", commit + ":" + path))
        if path.endswith("verdicts.csv"):
            rows = list(csv.DictReader(io.StringIO(git("show", commit + ":" + path).decode())))
            entry["verdicts"][path] = dict(counts=dict(Counter(row["status"] for row in rows)), rows=rows)
        if path.endswith("O6-old-client.txt") or path in ("opal-version.txt", "opal-version.txt.http", "opal-clusters.json.http"):
            entry[path] = git("show", commit + ":" + path).decode()
    if "43515122503" in ref:
        workflow = entry["workflow"]
        assert workflow["GITHUB_SHA"] == tested
        assert workflow["JOB_STATUS"] == "success"
        assert all(step["outcome"] == "success" for step in workflow["steps"].values())
        path = workflow["E2E_PATH"]
        rows = entry["verdicts"][path + "-O-verdicts.csv"]["rows"]
        assert len(rows) == 12 and {row["id"] for row in rows} == {f"O{i}" for i in range(1, 13)}
        assert all(row["status"] == "PASS" for row in rows)
        assert entry[path + "-O6-old-client.txt"].startswith("PASS:")
        latest_contract.append((workflow["OPAL_VERSION"], path))
    elif "43506711667" in ref:
        workflow = entry["workflow"]
        assert workflow["JOB_STATUS"] == "failure"
        assert workflow["steps"]["stack"]["outcome"] == "success"
        assert workflow["steps"]["scenarios"]["outcome"] == "failure"
        failed_contract.append((workflow["OPAL_VERSION"], workflow["E2E_PATH"]))
    else:
        assert entry["verdicts"]
        assert all("FAIL" not in verdict["counts"] for verdict in entry["verdicts"].values())
    audit["results"].append(entry)
matrix = {(version, path) for version in ("5.7.6", "6.1.3") for path in ("fresh", "upgrade")}
assert len(latest_contract) == 4 and set(latest_contract) == matrix
assert len(failed_contract) == 4 and set(failed_contract) == matrix
(destination / "input-audit.json").write_text(json.dumps(audit, indent=2) + "\n")

comparison = {}
for package in ("dsOMOP", "dsOMOPClient"):
    product = Path("/workspace/dsomop/wt/int") / package
    files = git("-C", str(product), "ls-files").decode().splitlines()
    vendor = Path("pkgs") / package
    changed = [p for p in files if not (vendor / p).is_file() or (product / p).read_bytes() != (vendor / p).read_bytes()]
    # All R code is identical after removing comment-only lines. Preserve the
    # actual mismatches too: comments and release metadata are still differences.
    code_differences = []
    for path in sorted(set(p.relative_to(product).as_posix() for p in (product / "R").glob("*.R")) |
                       set(p.relative_to(vendor).as_posix() for p in (vendor / "R").glob("*.R"))):
        def code(root):
            source = root / path
            return [line for line in source.read_text().splitlines() if not line.lstrip().startswith("#")] if source.exists() else None
        if code(product) != code(vendor):
            code_differences.append(path)
    comparison[package] = dict(commit=git("-C", str(product), "rev-parse", "HEAD").decode().strip(),
        branch=git("-C", str(product), "branch", "--show-current").decode().strip(),
        tracked_files=len(files), mismatches=changed, noncomment_R_differences=code_differences,
        namespace_equal=(product / "NAMESPACE").read_bytes() == (vendor / "NAMESPACE").read_bytes())
(destination / "vendor-comparison.json").write_text(json.dumps(comparison, indent=2) + "\n")

sources = [".github/workflows/opal-contract.yml", "compose/opal-matrix.yml"]
sources += [str(p) for p in Path("scripts/o").glob("*") if p.is_file()]
sources += [f"scripts/tests/o-{name}.py" for name in ("stack", "results", "candidate")]
hashes = {}
for path in sorted(sources):
    data = Path(path).read_bytes()
    assert data == git("show", tested + ":" + path), path
    hashes[path] = hashlib.sha256(data).hexdigest()
(destination / "tested-sources.json").write_text(json.dumps(hashes, indent=2) + "\n")
print("PASS: four complete 12/12 contract verdicts and four independent old-client checks")
print("PASS: four earlier failed jobs preserved results branches")
print("PASS: companion e2e verdict files contain no FAIL rows (INFO is not PASS)")
print("PASS: current harness and targeted test sources match tested commit " + tested)
for package, entry in comparison.items():
    print(package, entry["commit"], "tracked differences:", len(entry["mismatches"]),
          "noncomment R differences:", entry["noncomment_R_differences"], "namespace equal:", entry["namespace_equal"])
