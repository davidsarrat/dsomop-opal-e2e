#!/usr/bin/env bash
set -euo pipefail
case "$OPAL_VERSION" in 6.1.3|5.7.6) ;; *) echo 'Unreviewed Opal pin' >&2; exit 1;; esac
docker compose -f compose/opal-matrix.yml up -d
ready=0
for i in $(seq 1 90); do
  if curl -fsS --connect-timeout 5 --max-time 15 -H 'Accept: text/plain' \
    -u "administrator:$OPAL_ADMIN_PW" "$OPAL_URL/ws/system/version" > "$OUT/opal-version.txt"; then
    ready=1
    break
  fi
  sleep 5
done
if [ "$ready" != 1 ]; then
  echo 'Opal version endpoint did not become ready after 90 attempts' >&2
  exit 1
fi
python3 - <<'PY'
import os
from pathlib import Path
# /system/version returns text/plain, not a JSON object or quoted string.
version = (Path(os.environ['OUT']) / 'opal-version.txt').read_text().strip()
expected = os.environ['OPAL_VERSION']
if version != expected:
    raise SystemExit(f'Unexpected Opal version: expected {expected!r}, received {version!r}')
print(f'Opal version: {version}')
PY
NET=$(docker inspect "$STACK-opal" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)
echo "STACK_NET=$NET" >> "$GITHUB_ENV"
echo "ROCK=$STACK-rock" >> "$GITHUB_ENV"
docker image inspect "obiba/opal:$OPAL_VERSION" obiba/rock:2.3.0-R4.6.1 --format '{{json .RepoDigests}}' > "$OUT/image-digests.jsonl"
