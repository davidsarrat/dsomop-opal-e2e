#!/usr/bin/env bash
# CI only. The developer/coordinator does not invoke this script locally.
set -euo pipefail
: "${OUT:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_PAT:?}"
mkdir -p "$OUT"
cd "$OUT"
if [[ ! -f redaction-complete ]]; then
  # Even a setup/evidence failure gets a branch, without exposing raw output.
  cat > transcript.txt <<'EOF'
Book: Use the same two resources on Opal
Approved substitution: vendored pkgs/ dsOMOP and dsOMOPClient 2.10.5 instead of GitHub.
FAILED: transcript collection/redaction did not complete. Raw output was not published.
Inspect the workflow step failures; this is not successful walkthrough evidence.
EOF
  printf '{"evidence_collection":"failed"}\n' > result.json
fi
git init -q
git checkout -q -b results
git add -- transcript.txt result.json
git -c user.name=e2e -c user.email=e2e@users.noreply.github.com commit -qm \
  "book practice $GITHUB_RUN_ID attempt ${GITHUB_RUN_ATTEMPT:-1}" -- transcript.txt result.json
# Same per-run branch convention as e2e.yml; a rerun replaces that run's results.
git push -q --force "https://x-access-token:${GITHUB_PAT}@github.com/${GITHUB_REPOSITORY}.git" \
  "HEAD:refs/heads/results/${GITHUB_RUN_ID}-book-practice"
printf 'Results branch: results/%s-book-practice\n' "$GITHUB_RUN_ID"
