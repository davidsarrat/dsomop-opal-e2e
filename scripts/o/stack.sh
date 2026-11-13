#!/usr/bin/env bash
set -euo pipefail
case "$OPAL_VERSION" in 6.1.3|5.7.6) ;; *) echo 'Unreviewed Opal pin' >&2; exit 1;; esac
mkdir -p "$OUT"
docker compose -f compose/opal-matrix.yml up -d
python3 "$(dirname "$0")/readiness.py"
NET=$(docker inspect "$STACK-opal" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)
[ -n "$NET" ] || { echo 'Opal has no Docker network' >&2; exit 1; }
docker image inspect "obiba/opal:$OPAL_VERSION" obiba/rock:2.3.0-R4.6.1 --format '{{json .RepoDigests}}' > "$OUT/image-digests.jsonl"
echo "STACK_NET=$NET" >> "$GITHUB_ENV"
echo "ROCK=$STACK-rock" >> "$GITHUB_ENV"
