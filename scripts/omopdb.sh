#!/usr/bin/env bash
# PostgreSQL 16 on the stack's network ("omopdb"), database omop:
#   schema cdm        : the whole OHDSI Eunomia GiBleed CDM 5.3 (clinical + vocabulary)
#   schemas cdm2/vocab: the same data split, clinical tables in cdm2 and vocabulary tables in vocab
# and database omoppub with the CDM in its default schema (public), for the 1.x resource without a schema.
set -euo pipefail
echo "stack network: ${STACK_NET:-<empty>}"
docker run -d --name omopdb --network "$STACK_NET" -e POSTGRES_USER=omop -e POSTGRES_PASSWORD="$OMOPDB_PW" \
  -e POSTGRES_DB=omop postgres:16 > /dev/null
for i in $(seq 1 60); do docker exec omopdb pg_isready -U omop -d omop > /dev/null 2>&1 && break; sleep 2; done
sleep 3
mkdir -p /tmp/gibleed
curl -fsSL -o /tmp/gibleed.zip https://github.com/OHDSI/EunomiaDatasets/raw/main/datasets/GiBleed/GiBleed_5.3.zip
unzip -o -q /tmp/gibleed.zip -d /tmp/gibleed
unzip -l /tmp/gibleed.zip | sed -n '1,60p'
curl -fsSL -o /tmp/ddl.sql https://raw.githubusercontent.com/OHDSI/CommonDataModel/main/inst/ddl/5.3/postgresql/OMOPCDM_postgresql_5.3_ddl.sql
python3 scripts/load_gibleed.py /tmp/gibleed /tmp/ddl.sql | tee "$OUT/$E2E_PATH-omopdb-load.txt"
