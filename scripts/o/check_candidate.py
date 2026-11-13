"""Require a coordinated native-language candidate before provisioning."""
from pathlib import Path
import re

def check_candidate(root=Path("pkgs")):
    versions = {}
    for package in ("dsOMOP", "dsOMOPClient"):
        match = re.search(r"^Version:\s*(\S+)", (root / package / "DESCRIPTION").read_text(), re.M)
        if not match:
            raise SystemExit(f"Missing Version in {package}")
        versions[package] = match[1]
    version = versions["dsOMOP"]
    if versions["dsOMOPClient"] != version:
        raise SystemExit(f"Candidate versions differ: {versions}")
    if not re.fullmatch(r"[0-9]+(?:[.-][0-9]+)*", version) or tuple(map(int, re.split(r"[.-]", version))) < (2, 10, 3):
        raise SystemExit(f"Vendor the integrated native-language candidate first: {version}")
    # Version equality alone must not admit the older 2.10.3 implementation.
    for package in versions:
        root_r = root / package / "R"
        for filename in ("plan_normalize_v2.R", "concept_labels.R"):
            if not (root_r / filename).is_file():
                raise SystemExit(f"Missing integrated source: {package}/R/{filename}")
    for filename in ("create_reach_db.R", "extend_reach_db.R", "load_reach_pg.R"):
        if not (root / "dsOMOP/tests/fixtures" / filename).is_file():
            raise SystemExit(f"Missing fixture: {filename}")
    if len(list((root / "dsOMOP/inst/plans/acceptance").glob("*/plan.json"))) != 15:
        raise SystemExit("Expected all 15 frozen acceptance plans")
    return version

if __name__ == "__main__":
    print(f"Matching integrated {check_candidate()} sources and frozen acceptance inputs present")
