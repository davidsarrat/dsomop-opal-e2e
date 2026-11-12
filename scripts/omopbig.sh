#!/usr/bin/env bash
# A large synthetic CDM for scenario G16 (first-release latency at a realistic size): database omopbig with GiBleed's
# cdm schema (vocabulary included) plus BIG_PERSONS synthetic persons, one observation period each, three conditions
# and two drug exposures per person on average, with the primary keys and person_id indexes of a deployed CDM.
set -euo pipefail
N=${BIG_PERSONS:-1000000}
[ "$N" -gt 0 ] || { echo "BIG_PERSONS=0: no large CDM"; exit 0; }
t0=$(date +%s)
docker exec omopdb createdb -U omop omopbig
docker exec omopdb bash -c "pg_dump -U omop -d ${CDM_DB:-omop} --schema=cdm | psql -q -U omop -d omopbig" > /dev/null
docker exec -i omopdb psql -v ON_ERROR_STOP=1 -v N="$N" -U omop -d omopbig -q <<'SQL'
\timing on
INSERT INTO cdm.person (person_id, gender_concept_id, year_of_birth, month_of_birth, day_of_birth, race_concept_id,
                        ethnicity_concept_id)
SELECT 10000000 + g, CASE WHEN g % 2 = 0 THEN 8532 ELSE 8507 END, 1930 + (g % 70), 1 + (g % 12), 1 + (g % 28), 8527,
       38003564
FROM generate_series(1, :N) g;
INSERT INTO cdm.observation_period (observation_period_id, person_id, observation_period_start_date,
                                    observation_period_end_date, period_type_concept_id)
SELECT 10000000 + g, 10000000 + g, DATE '1995-01-01' + (g % 3650), DATE '2008-01-01' + (g % 3650), 44814724
FROM generate_series(1, :N) g;
INSERT INTO cdm.condition_occurrence (condition_occurrence_id, person_id, condition_concept_id, condition_start_date,
                                      condition_type_concept_id)
SELECT 100000000 + g, 10000001 + (g % :N), (ARRAY[192671, 4112343, 260139, 80180, 372328])[1 + (g % 5)],
       DATE '1996-01-01' + (g % 4000), 32020
FROM generate_series(1, 3 * :N) g;
INSERT INTO cdm.drug_exposure (drug_exposure_id, person_id, drug_concept_id, drug_exposure_start_date,
                               drug_exposure_end_date, drug_type_concept_id)
SELECT 100000000 + g, 10000001 + (g % :N), (ARRAY[1118084, 1124300, 40213227, 1127433])[1 + (g % 4)],
       DATE '1996-02-01' + (g % 4000), DATE '1996-03-01' + (g % 4000), 38000177
FROM generate_series(1, 2 * :N) g;
ALTER TABLE cdm.person ADD PRIMARY KEY (person_id);
ALTER TABLE cdm.observation_period ADD PRIMARY KEY (observation_period_id);
ALTER TABLE cdm.condition_occurrence ADD PRIMARY KEY (condition_occurrence_id);
ALTER TABLE cdm.drug_exposure ADD PRIMARY KEY (drug_exposure_id);
CREATE INDEX ON cdm.observation_period (person_id);
CREATE INDEX ON cdm.condition_occurrence (person_id);
CREATE INDEX ON cdm.condition_occurrence (condition_concept_id);
CREATE INDEX ON cdm.drug_exposure (person_id);
CREATE INDEX ON cdm.drug_exposure (drug_concept_id);
VACUUM ANALYZE;
SQL
docker exec omopdb psql -U omop -d omopbig -qAt -c "SELECT string_agg(relname || '=' || n_live_tup, ', ' ORDER BY n_live_tup DESC) FROM pg_stat_user_tables WHERE schemaname = 'cdm' AND n_live_tup > 0" | tee "$OUT/$E2E_PATH-omopbig.txt"
docker exec omopdb psql -U omop -d omopbig -qAt -c "SELECT pg_size_pretty(pg_database_size('omopbig'))" | sed 's/^/size: /' | tee -a "$OUT/$E2E_PATH-omopbig.txt"
echo "built in $(( $(date +%s) - t0 )) s" | tee -a "$OUT/$E2E_PATH-omopbig.txt"
df -h / | tail -1
