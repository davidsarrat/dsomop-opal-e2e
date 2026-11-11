#!/usr/bin/env bash
# easy-opal stack (Opal + Rock "default" cluster + MongoDB + nginx with a self-signed certificate on :8443).
set -euo pipefail
curl -LsSf https://astral.sh/uv/install.sh | sh > /dev/null
export PATH="$HOME/.local/bin:$PATH"
uv tool install easy-opal > /dev/null
easy-opal --version || true
easy-opal --runtime docker setup --stack-name "$STACK" --host localhost --port 8443 \
  --ssl-strategy self-signed --password "$OPAL_ADMIN_PW" --yes
easy-opal --runtime docker up
easy-opal status || true
docker ps --format '{{.Names}}  {{.Image}}  {{.Status}}'
NET=$(docker inspect "$STACK-opal" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)
echo "STACK_NET=$NET" >> "$GITHUB_ENV"
echo "ROCK=$STACK-rock" >> "$GITHUB_ENV"
echo "network: $NET"
# Opal answers once Rock is registered; wait for the REST API and the R cluster.
for i in $(seq 1 90); do
  code=$(curl -ks -o /dev/null -w '%{http_code}' -u "administrator:$OPAL_ADMIN_PW" https://localhost:8443/ws/system/version || true)
  [ "$code" = "200" ] && break; sleep 5
done
echo "Opal version: $(curl -ks -u "administrator:$OPAL_ADMIN_PW" https://localhost:8443/ws/system/version)"
for i in $(seq 1 60); do
  resp=$(curl -ks -u "administrator:$OPAL_ADMIN_PW" -H 'Accept: application/json' -w '\n%{http_code}' https://localhost:8443/ws/service/r/clusters || true)
  code=$(echo "$resp" | tail -1)
  [ "$code" != "200" ] && { echo "clusters endpoint answered $code"; break; }
  n=$(echo "$resp" | head -n -1 | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(len(c.get("servers",[])) for c in d))' 2>/dev/null || echo 0)
  [ "${n:-0}" -ge 1 ] && break; sleep 5
done
curl -ks -u "administrator:$OPAL_ADMIN_PW" -H 'Accept: application/json' https://localhost:8443/ws/service/r/clusters | head -c 800; echo
docker exec "$STACK-rock" Rscript -e 'ip <- installed.packages(); p <- c("dsBase","resourcer","DBI","RPostgres","RPostgreSQL","RSQLite","R6","jsonlite","filelock","openssl","remotes","dsOMOP"); print(ip[intersect(rownames(ip), p), c("Version","LibPath"), drop = FALSE]); cat("missing:", setdiff(p, rownames(ip)), "\n"); print(getOption("repos")); print(R.version.string)' \
  | tee "$OUT/$E2E_PATH-rock-packages-initial.txt"
# Current Opal ships with R package management disabled (OpalGeneralConfig.allowRPackageManagement = false); the
# administrator enables it in admin_setup.R (PUT /system/conf/general/_rPackage, as the Opal UI does).
