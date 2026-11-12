#!/usr/bin/env python3
"""Load OHDSI Eunomia GiBleed CSVs into PostgreSQL (container omopdb) with the official CDM 5.3 DDL.

Each CSV goes into an all-text staging table first, then into the typed CDM table with explicit casts, so date columns
stored as numbers (days or seconds since 1970) and integer columns written as "1.0" load as well.
"""
import csv
import glob
import os
import subprocess
import sys

SRC, DDL = sys.argv[1], sys.argv[2]
VOCAB = {"concept", "vocabulary", "domain", "concept_class", "concept_relationship", "relationship",
         "concept_synonym", "concept_ancestor", "source_to_concept_map", "drug_strength"}


def psql(sql, db="omop", data=None):
    cmd = ["docker", "exec", "-i", "omopdb", "psql", "-v", "ON_ERROR_STOP=1", "-U", "omop", "-d", db, "-qAt"]
    cmd += ["-f", "-"] if data is None and len(sql) > 4000 else ["-c", sql]
    stdin = sql.encode() if data is None and len(sql) > 4000 else data
    r = subprocess.run(cmd, input=stdin, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(f"psql failed on: {sql[:300]}\n{r.stderr.decode()[:3000]}")
    return r.stdout.decode()


def cast(col, typ):
    v = f'NULLIF(trim("{col}"), \'\')'
    num = f"{v} ~ '^-?[0-9]+(\\.[0-9]+)?([eE][-+]?[0-9]+)?$'"
    if typ in ("integer", "bigint", "smallint"):
        return f"{v}::numeric::{typ}"
    if typ in ("numeric", "double precision", "real"):
        return f"{v}::{typ}"
    ymd = f"{v} ~ '^[12][0-9]{{3}}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])$'"
    if typ == "date":
        return (f"CASE WHEN {v} IS NULL THEN NULL WHEN {ymd} THEN to_date({v}, 'YYYYMMDD') WHEN {num} THEN (CASE WHEN abs({v}::numeric) > 100000 "
                f"THEN to_timestamp({v}::double precision)::date ELSE DATE '1970-01-01' + {v}::numeric::int END) "
                f"ELSE {v}::date END")
    if typ.startswith("timestamp"):
        return (f"CASE WHEN {v} IS NULL THEN NULL WHEN {ymd} THEN to_date({v}, 'YYYYMMDD')::timestamp WHEN {num} THEN (CASE WHEN abs({v}::numeric) > 100000 "
                f"THEN to_timestamp({v}::double precision)::timestamp ELSE (DATE '1970-01-01' + {v}::numeric::int)::timestamp END) "
                f"ELSE {v}::timestamp END")
    return f'"{col}"'


ddl = open(DDL).read().replace("@cdmDatabaseSchema", "cdm")
psql("CREATE SCHEMA cdm; CREATE SCHEMA stage;")
psql(ddl)
cols = {}
for line in psql("SELECT table_name, column_name, data_type FROM information_schema.columns "
                 "WHERE table_schema = 'cdm' ORDER BY table_name, ordinal_position").splitlines():
    t, c, ty = line.split("|")
    cols.setdefault(t, []).append((c, ty))

loaded = []
for path in sorted(glob.glob(os.path.join(SRC, "**", "*.csv"), recursive=True)):
    table = os.path.splitext(os.path.basename(path))[0].lower()
    if table not in cols:
        print(f"skip {os.path.basename(path)}: no such CDM 5.3 table")
        continue
    with open(path, newline="", encoding="utf-8") as f:
        rd = csv.reader(f)
        header = [h.strip().lower() for h in next(rd)]
        sample = next(rd, [])
    if table in ("person", "concept", "condition_occurrence", "drug_exposure", "observation_period"):
        print(f"sample {table}: " + ", ".join(f"{h}={x}" for h, x in zip(header, sample)))
    try:
        psql(f"DROP TABLE IF EXISTS stage.{table}; CREATE UNLOGGED TABLE stage.{table} ("
             + ", ".join(f'"{h}" text' for h in header) + ")")
        psql(f"COPY stage.{table} FROM STDIN WITH (FORMAT csv, HEADER true)", data=open(path, "rb").read())
        target = [(c, ty) for c, ty in cols[table] if c in header]
        psql(f"INSERT INTO cdm.{table} ({', '.join(chr(34) + c + chr(34) for c, _ in target)}) SELECT "
             + ", ".join(cast(c, ty) for c, ty in target) + f" FROM stage.{table}")
    except RuntimeError as e:
        print(f"LOAD ERROR {table}: {e}")
        if table == "person":
            raise
        continue
    n = psql(f"SELECT count(*) FROM cdm.{table}").strip()
    unknown = sorted(set(header) - {c for c, _ in cols[table]})
    print(f"{table}: {n} rows ({len(target)} of {len(header)} CSV columns{'; not in DDL: ' + ', '.join(unknown) if unknown else ''})")
    loaded.append(table)
psql("DROP SCHEMA stage CASCADE")

# The vocabulary in its own schema (cdm2 = clinical tables, vocab = vocabulary tables).
psql("CREATE SCHEMA cdm2; CREATE SCHEMA vocab;")
for table in sorted(cols):
    psql(f"CREATE TABLE {'vocab' if table in VOCAB else 'cdm2'}.{table} AS TABLE cdm.{table}")
print("split copy: vocab =", sorted(t for t in cols if t in VOCAB))

# GiBleed ships cdm_source.cdm_version = "v5.3.1". omop53 is the same data with "5.3", so the rest of the checks are
# not all blocked by how a server reads that string; resource gibleed_asshipped keeps the original.
psql("CREATE DATABASE omop53 TEMPLATE omop", db="postgres")
psql("UPDATE cdm.cdm_source SET cdm_version = '5.3'; UPDATE cdm2.cdm_source SET cdm_version = '5.3';", db="omop53")
# One schema only (cdm): what CDM schema discovery should find when a 2.x resource names none.
psql("CREATE DATABASE omopone TEMPLATE omop", db="postgres")
psql("DROP SCHEMA cdm2 CASCADE; DROP SCHEMA vocab CASCADE;", db="omopone")
# A third database with the CDM in its default schema.
psql("CREATE DATABASE omoppub TEMPLATE omop53", db="postgres")
psql("DROP SCHEMA cdm2 CASCADE; DROP SCHEMA vocab CASCADE; DROP SCHEMA public CASCADE; ALTER SCHEMA cdm RENAME TO public;",
     db="omoppub")
# A small site (scenario G: NA pooling policies over two independent sites): GiBleed's first 150 persons only.
psql("CREATE DATABASE omopsmall TEMPLATE omop", db="postgres")
psql("DROP SCHEMA cdm2 CASCADE; DROP SCHEMA vocab CASCADE;", db="omopsmall")
psql("""DO $$ DECLARE t text; BEGIN
  FOR t IN SELECT c.table_name FROM information_schema.columns c
           JOIN information_schema.tables x ON x.table_schema = c.table_schema AND x.table_name = c.table_name
                                           AND x.table_type = 'BASE TABLE'
           WHERE c.table_schema = 'cdm' AND c.column_name = 'person_id' AND c.table_name <> 'person' LOOP
    EXECUTE format('DELETE FROM cdm.%I WHERE person_id NOT IN (SELECT person_id FROM cdm.person ORDER BY person_id LIMIT 150)', t);
  END LOOP;
  DELETE FROM cdm.person WHERE person_id NOT IN (SELECT person_id FROM cdm.person ORDER BY person_id LIMIT 150);
END $$""", db="omopsmall")
print("omopsmall.cdm: persons=" + psql("SELECT count(*) FROM cdm.person", db="omopsmall").strip())
# A second database user with read access only (scenario G20: corpus alias, source visibility, read failures).
reader_pw = os.environ.get("READER_PW", "")
if reader_pw:
    psql("CREATE ROLE e2e_reader LOGIN PASSWORD '" + reader_pw.replace("'", "''") + "'", db="postgres")
    for db in ("omop", "omop53"):
        psql(f"GRANT CONNECT ON DATABASE {db} TO e2e_reader", db="postgres")
        psql("GRANT USAGE ON SCHEMA cdm TO e2e_reader; GRANT SELECT ON ALL TABLES IN SCHEMA cdm TO e2e_reader", db=db)
    print("role e2e_reader: SELECT on omop.cdm and omop53.cdm")
for db, schema in (("omop", "cdm"), ("omop53", "cdm"), ("omoppub", "public")):
    print(f"{db}.{schema}.cdm_source: " + psql(f"SELECT cdm_source_name, cdm_version, vocabulary_version FROM {schema}.cdm_source", db=db).strip())
for db, schema in (("omop", "cdm"), ("omop", "cdm2"), ("omop", "vocab"), ("omop53", "cdm"), ("omoppub", "public")):
    counts = psql("SELECT string_agg(t || '=' || n, ', ') FROM (VALUES " + ", ".join(
        f"('{t}', (SELECT count(*) FROM {schema}.{t}))" for t in ("person", "condition_occurrence", "drug_exposure", "concept")
        if (schema != "cdm2" or t not in VOCAB) and (schema != "vocab" or t in VOCAB)) + ") AS x(t, n)", db=db).strip()
    print(f"{db}.{schema}: {counts}")
print("loaded tables:", len(loaded))
