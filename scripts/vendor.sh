#!/usr/bin/env bash
# Vendor a candidate branch of dsOMOP and dsOMOPClient into pkgs/ for mode=candidate. The sources come from the
# committed branch of each working clone (git archive), never from a working tree:
#   REF=<branch or commit> scripts/vendor.sh <clone root holding dsOMOP/ and dsOMOPClient/>
#   e.g. REF=fix/2.10.3-ohdsi-p0 scripts/vendor.sh /workspace/dsomop
# The script prints each package's commit and version; commit pkgs/ with them in the message.
set -euo pipefail
src=${1:?clone root}
ref=${REF:?set REF to the candidate branch or commit}
cd "$(dirname "$0")/.."
for pkg in dsOMOP dsOMOPClient; do
  rm -rf "pkgs/$pkg"
  mkdir -p "pkgs/$pkg"
  git -C "$src/$pkg" archive "$ref" | tar -x -C "pkgs/$pkg"
  echo "$pkg $(git -C "$src/$pkg" rev-parse --short "$ref") $(grep '^Version:' "pkgs/$pkg/DESCRIPTION")"
done
