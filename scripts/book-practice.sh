#!/usr/bin/env bash
# Raw output stays in RUNNER_TEMP until the always-running evidence step redacts it.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 -u "$repo_dir/scripts/book-practice/run.py" "$@"
