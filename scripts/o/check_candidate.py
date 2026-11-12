"""Fail before provisioning if WS10 is run against an old vendored candidate."""
from pathlib import Path
import re

for package in ("dsOMOP", "dsOMOPClient"):
    version = re.search(r"^Version:\s*(\S+)", Path("pkgs", package, "DESCRIPTION").read_text(), re.M)[1]
    if version != "2.10.4":
        raise SystemExit(f"Vendor the integrated 2.10.4 first: {package} is {version}")
for filename in ("create_reach_db.R", "extend_reach_db.R", "load_reach_pg.R"):
    assert Path("pkgs/dsOMOP/tests/fixtures", filename).is_file(), filename
assert len(list(Path("pkgs/dsOMOP/inst/plans/acceptance").glob("*/plan.json"))) == 15
print("Matching 2.10.4 sources and frozen acceptance inputs present")
