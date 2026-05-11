#!/usr/bin/env bash
# Incident 02: Error storm — forced-failure requests to burn SLO budget fast.
# Sends 200 concurrent fail=true requests so error rate spikes to ~100%.
# Expected detection: SLO fast-burn alert (5m + 1h windows) fires within 5-10 min.
set -euo pipefail

ENDPOINT="${APP_URL:-http://localhost:8000}"
BATCH=200

echo "[chaos 02] Firing $BATCH error requests to $ENDPOINT/predict ..."

for i in $(seq 1 "$BATCH"); do
  curl -s -o /dev/null -X POST "$ENDPOINT/predict" \
    -H "Content-Type: application/json" \
    -d '{"prompt":"chaos-error-storm","model":"llama3-mock","fail":true}' &
done
wait

echo "[chaos 02] Done — $BATCH forced errors injected."
echo "           Watch Prometheus at http://localhost:9090/alerts for SLOFastBurn."
echo "           Check burn rate: inference:fail_ratio:rate5m"
