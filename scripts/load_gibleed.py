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
    if typ == "date":
        return (f"CASE WHEN {v} IS NULL THEN NULL WHEN {num} THEN (CASE WHEN abs({v}::numeric) > 100000 "
                f"THEN to_timestamp({v}::double precision)::date ELSE DATE '1970-01-01' + {v}::numeric::int END) "
                f"ELSE {v}::date END")
    if typ.startswith("timestamp"):
        return (f"CASE WHEN {v} IS NULL THEN NULL WHEN {num} THEN (CASE WHEN abs({v}::numeric) > 100000 "
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
        header = [h.strip().lower() for h in next(csv.reader(f))]
    psql(f"DROP TABLE IF EXISTS stage.{table}; CREATE UNLOGGED TABLE stage.{table} ("
         + ", ".join(f'"{h}" text' for h in header) + ")")
    psql(f"COPY stage.{table} FROM STDIN WITH (FORMAT csv, HEADER true)", data=open(path, "rb").read())
    target = [(c, ty) for c, ty in cols[table] if c in header]
    psql(f"INSERT INTO cdm.{table} ({', '.join(c for c, _ in target)}) SELECT "
         + ", ".join(cast(c, ty) for c, ty in target) + f" FROM stage.{table}")
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

# A second database with the CDM in its default schema.
psql("CREATE DATABASE omoppub TEMPLATE omop", db="postgres")
psql("DROP SCHEMA cdm2 CASCADE; DROP SCHEMA vocab CASCADE; DROP SCHEMA public CASCADE; ALTER SCHEMA cdm RENAME TO public;",
     db="omoppub")
for db, schema in (("omop", "cdm"), ("omop", "cdm2"), ("omop", "vocab"), ("omoppub", "public")):
    counts = psql("SELECT string_agg(t || '=' || n, ', ') FROM (VALUES " + ", ".join(
        f"('{t}', (SELECT count(*) FROM {schema}.{t}))" for t in ("person", "condition_occurrence", "drug_exposure", "concept")
        if (schema != "cdm2" or t not in VOCAB) and (schema != "vocab" or t in VOCAB)) + ") AS x(t, n)", db=db).strip()
    print(f"{db}.{schema}: {counts}")
print("loaded tables:", len(loaded))
