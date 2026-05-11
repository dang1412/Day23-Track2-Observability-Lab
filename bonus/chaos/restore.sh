#!/usr/bin/env bash
# Restore containers stopped by chaos scripts.
# Usage: bash restore.sh [app|otel-collector|all]
set -euo pipefail

SERVICE="${1:-all}"

restart() {
  local name="$1"
  echo "[restore] Starting $name..."
  docker start "$name"
  echo "[restore] $name is back up."
}

case "$SERVICE" in
  app)            restart day23-app ;;
  otel-collector) restart day23-otel-collector ;;
  all)
    restart day23-app
    restart day23-otel-collector
    ;;
  *)
    echo "Usage: $0 [app|otel-collector|all]"
    exit 1
    ;;
esac
