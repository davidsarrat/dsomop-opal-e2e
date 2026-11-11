#!/usr/bin/env bash
# Vendor the 2.10.1 candidates from the committed branch of each working clone (never the working tree):
#   scripts/vendor.sh /workspace/dsomop
set -euo pipefail
src=${1:?clone root}
cd "$(dirname "$0")/.."
for pkg in dsOMOP dsOMOPClient; do
  rm -rf "pkgs/$pkg"
  mkdir -p "pkgs/$pkg"
  git -C "$src/$pkg" archive "${REF:-fix/2.10.1-legacy-resources}" | tar -x -C "pkgs/$pkg"
  echo "$pkg $(git -C "$src/$pkg" rev-parse --short "${REF:-fix/2.10.1-legacy-resources}") $(grep '^Version:' "pkgs/$pkg/DESCRIPTION")"
done
