# Incident 01 — Inference API Hard Kill

**Severity:** Critical  
**Date:** 2026-05-11  
**Duration:** ~4 minutes (19:23 → 19:27)  
**On-call:** dttung1412  

---

## Timeline

| Time (UTC+7) | Event |
|---|---|
| 19:23:00 | `bash bonus/chaos/01-kill-app.sh` executed — `day23-app` container stopped |
| 19:23:05 | `/healthz` returns `connection refused` |
| 19:23:05 | Prometheus scrape fails; `up{job="inference-api"}` → 0 |
| 19:24:05 | **ServiceDown alert fires** (1m `for:` window elapsed) |
| 19:24:08 | Alertmanager routes to `#day23-alert` Slack channel |
| 19:24:10 | On-call opens Grafana — Day 23 Overview dashboard shows flat request rate |
| 19:24:30 | On-call runs `docker ps` — `day23-app` status is `Exited` |
| 19:24:35 | `bash bonus/chaos/restore.sh app` executed |
| 19:24:50 | Container restarts, `/healthz` returns `{"status":"ok"}` |
| 19:25:00 | `up{job="inference-api"}` → 1; Prometheus scrape recovers |
| 19:27:05 | ServiceDown alert resolves; `✅` notification sent to Slack |

**Time-to-detect:** 65 seconds  
**Time-to-mitigate:** 95 seconds  

---

## Detection

**Signal:** `ServiceDown` alert rule in `ai-quality.yml`  
```promql
up{job="inference-api"} == 0
```
Alert fired correctly within the expected `for: 1m` window. The Grafana overview dashboard also showed a flat line on `inference_requests_total` and a 0-value on `INFERENCE_ACTIVE`.

---

## Mitigation

1. Confirmed container was stopped (not OOM-killed): `docker inspect day23-app --format '{{.State.ExitCode}}'` → `0` (clean stop, not crash)  
2. Restarted container: `docker start day23-app`  
3. Verified health: `curl http://localhost:8000/healthz`  
4. Confirmed alert resolved in Alertmanager UI  

---

## Root Cause

Manual `docker stop` simulating a scenario where a CI/CD pipeline rolls out a bad image tag and the container fails to start (exit 0 = stopped gracefully, not crashed). In production this would be an accidental `docker stop` during a deploy or an OOM-kill with exit code 137.

---

## Action Items

| # | Action | Owner | Status |
|---|---|---|---|
| 1 | Add Docker restart policy `unless-stopped` to `docker-compose.yml` so container auto-recovers from clean stops without on-call intervention | infra | proposed |
| 2 | Add readiness probe to Grafana dashboard: show `up{job="inference-api"}` as a stat panel with red threshold at 0 | on-call | proposed |
| 3 | Reduce `for: 1m` to `for: 30s` on ServiceDown — 60s is already slow for a hard kill | alerting | proposed |
