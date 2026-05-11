#!/usr/bin/env bash
# Incident 01: Hard-kill inference API
# Simulates OOM-kill, bad deploy rollout, or container crash.
# Expected detection: ServiceDown alert fires within ~60s.
set -euo pipefail

echo "[chaos 01] Stopping day23-app container..."
docker stop day23-app

echo "[chaos 01] App is DOWN."
echo "           Watch Alertmanager at http://localhost:9093 for ServiceDown (fires in ~60s)."
echo "           Restore with: bash bonus/chaos/restore.sh app"
