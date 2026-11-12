#!/usr/bin/env bash
set -euo pipefail
case "$OPAL_VERSION" in 6.1.3|5.7.6) ;; *) echo 'Unreviewed Opal pin' >&2; exit 1;; esac
docker compose -f compose/opal-matrix.yml up -d
for i in $(seq 1 90); do
  if curl -fsS -u "administrator:$OPAL_ADMIN_PW" "$OPAL_URL/ws/system/version" > "$OUT/opal-version.json"; then break; fi
  sleep 5
done
python3 - <<'PY'
import json,os
v=json.load(open(os.environ['OUT']+'/opal-version.json'))
assert os.environ['OPAL_VERSION'] in str(v), ('unexpected Opal version',v)
PY
NET=$(docker inspect "$STACK-opal" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)
echo "STACK_NET=$NET" >> "$GITHUB_ENV"
echo "ROCK=$STACK-rock" >> "$GITHUB_ENV"
docker image inspect "obiba/opal:$OPAL_VERSION" obiba/rock:2.3.0-R4.6.1 --format '{{json .RepoDigests}}' > "$OUT/image-digests.jsonl"
