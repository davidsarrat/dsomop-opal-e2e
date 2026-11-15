#!/bin/bash
# Run only harness regressions and two historical-source installation probes.
set -euo pipefail
read -r pod_host pod_port < <(python3 /workspace/astra/runpod/deckpod.py ssh-target)
ssh_args=(-i "$HOME/.ssh/runpod_cover" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "$pod_port")
remote_root=$(ssh "${ssh_args[@]}" "root@$pod_host" 'mktemp -d /root/rt/r205-e2efix2.XXXXXXXX')
trap 'ssh "${ssh_args[@]}" "root@$pod_host" "rm -rf -- $remote_root"' EXIT
# Only scripts and two DESCRIPTION files, no product source copies.
tar -czf - scripts/*.R scripts/tests/g-contract.R scripts/tests/g-upgrade-root.R scripts/tests/historical-install.R scripts/tests/historical-installed.R scripts/o/*.R pkgs/dsOMOP/DESCRIPTION pkgs/dsOMOPClient/DESCRIPTION |
  ssh "${ssh_args[@]}" "root@$pod_host" "tar -xzf - -C $remote_root"
ssh "${ssh_args[@]}" "root@$pod_host" "cd $remote_root && Rscript scripts/tests/historical-install.R && Rscript scripts/tests/g-upgrade-root.R && Rscript scripts/tests/g-contract.R && timeout 240 Rscript scripts/tests/historical-installed.R"
