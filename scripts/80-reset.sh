#!/usr/bin/env bash
# Back to the baseline: removes the Database and the cluster (and their PVCs) from our
# namespace, then redeploys the baseline. The extension image and namespace are kept.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_env.sh"
source "$ROOT/scripts/_demo.sh"

announce_target
reset_demo_objects
"$ROOT/scripts/30-deploy-baseline.sh"
