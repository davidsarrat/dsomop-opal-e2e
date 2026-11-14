#!/usr/bin/env bash
# Companion to omopdb.sh: load the pinned second public CDM without changing GiBleed.
set -euo pipefail
: "${OMOPDB_PW:?OMOP database password required}"
: "${STACK_NET:?stack network required}"
: "${OUT:?evidence directory required}"
NUMERIC_CACHE=${NUMERIC_CACHE:-/tmp/dsomop-numeric-cdm}
PGHOST=$(docker inspect --format "{{(index .NetworkSettings.Networks \"$STACK_NET\").IPAddress}}" omopdb)
export PGHOST
PGDATABASE=omop PGUSER=omop PGPASSWORD="$OMOPDB_PW" NUMERIC_DUCKDB=0 \
  Rscript scripts/numeric/load.R "$NUMERIC_CACHE" | tee "$OUT/$E2E_PATH-numeric-load.txt"
cp "$NUMERIC_CACHE/manifest.json" "$OUT/$E2E_PATH-numeric-manifest.json"
