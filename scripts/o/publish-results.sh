#!/usr/bin/env bash
# Invoked only by CI after successful evidence collection/redaction.
set -euo pipefail
: "${GITHUB_PAT:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}"
: "${OPAL_VERSION:?}" "${E2E_PATH:?}" "${MODE:?}" "${OUT:?}"
branch="results/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-opal-${OPAL_VERSION}-${E2E_PATH}-${MODE}"
cd "$OUT"
git init -q
git checkout -q -b results
git add -A
git -c user.name=e2e -c user.email=e2e@users.noreply.github.com commit -qm \
  "opal contract $GITHUB_RUN_ID attempt $GITHUB_RUN_ATTEMPT $OPAL_VERSION $E2E_PATH $MODE" -- .
git push -q "https://x-access-token:${GITHUB_PAT}@github.com/${GITHUB_REPOSITORY}.git" \
  "HEAD:refs/heads/$branch"
echo "Results branch: $branch"
