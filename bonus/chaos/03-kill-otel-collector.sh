#!/usr/bin/env bash
# Incident 03: Kill OTel Collector — traces go dark, app keeps serving silently.
# This is a "silent failure": /healthz returns 200, metrics still scrape,
# but all trace spans are dropped. No existing alert catches this.
# ACTION ITEM from this postmortem: add OtelCollectorDown alert (see ai-quality.yml).
set -euo pipefail

echo "[chaos 03] Stopping day23-otel-collector..."
docker stop day23-otel-collector

echo "[chaos 03] OTel Collector is DOWN."
echo "           App continues to serve requests (fail-open OTLP export)."
echo "           Jaeger at http://localhost:16686 will show no new traces."
echo "           Prometheus scrape for otel-collector job will show up=0."
echo "           Without the new OtelCollectorDown alert, this goes unnoticed!"
echo "           Restore with: bash bonus/chaos/restore.sh otel-collector"
