# Incident 03 — OTel Collector Silent Failure (Traces Dark)

**Severity:** Warning  
**Date:** 2026-05-11  
**Duration:** ~18 minutes (20:07 → 20:25) — undetected until manual check  
**On-call:** dttung1412  

---

## Timeline

| Time (UTC+7) | Event |
|---|---|
| 20:07:00 | `bash bonus/chaos/03-kill-otel-collector.sh` executed — `day23-otel-collector` stopped |
| 20:07:05 | App continues serving; `/healthz` and `/metrics` fully operational |
| 20:07:05 | OTLP export from app starts failing silently (SDK logs warn, does not crash) |
| 20:07:05 | Prometheus scrape for `job="otel-collector"` → `up=0` — **but no alert fires** |
| 20:07:10 | Jaeger receives no new spans |
| 20:07:30 | Load test continues; all requests succeed in metrics, zero traces in Jaeger |
| 20:20:00 | On-call opens Jaeger UI to investigate a latency question — **no traces for last 13 minutes** |
| 20:20:30 | On-call checks Prometheus: `up{job="otel-collector"}` → 0 (has been 0 for 13 minutes) |
| 20:21:00 | Root cause confirmed: collector container stopped |
| 20:21:10 | `bash bonus/chaos/restore.sh otel-collector` executed |
| 20:21:30 | Collector restarts; OTLP export resumes |
| 20:22:00 | New traces appear in Jaeger |
| 20:25:00 | **OtelCollectorDown alert added to ai-quality.yml** (action item implemented during incident) |

**Time-to-detect:** 13 minutes (manual discovery, no automated alert)  
**Time-to-mitigate:** 1 minute after detection  

---

## Detection

**No automated detection existed.** The collector failure was invisible to all existing alerts:

- `ServiceDown`: only watches `up{job="inference-api"}` — app was up
- `SLOFastBurn`: only watches error rate — errors stayed at 0%
- `HighInferenceLatency`: latency was normal
- `InferenceQualityDrop`: quality scores were fine

The only signal was `up{job="otel-collector"} == 0` in Prometheus — a metric that existed but had no alert rule watching it. On-call discovered the outage 13 minutes late, only because they opened Jaeger for an unrelated reason.

This is a **monitoring blind spot**: the observability system itself was not being observed.

---

## Mitigation

1. Ran `docker ps | grep otel-collector` → container status `Exited`  
2. `docker start day23-otel-collector`  
3. Verified traces resumed in Jaeger  
4. **Implemented action item immediately**: added `OtelCollectorDown` alert to `ai-quality.yml`  

---

## Root Cause

The OTel Collector container stopped (simulating a crash or OOM-kill). The FastAPI app's OTLP exporter is configured fail-open: it logs a warning and drops spans rather than propagating errors to the request path. This design is correct for availability, but it meant the outage was completely invisible to users and to existing alerts.

The underlying gap: the lab's alert rules only watch the *application* (`up{job="inference-api"}`) but not the *infrastructure* that makes observability work (Collector, Loki, Jaeger). "Observing the observer" was missing.

---

## Action Items

| # | Action | Owner | Status |
|---|---|---|---|
| 1 | **[IMPLEMENTED]** Add `OtelCollectorDown` alert to `ai-quality.yml` — fires when `up{job="otel-collector"} == 0` for 2 minutes | alerting | ✅ done |
| 2 | Add a Grafana panel showing `up` for all infrastructure jobs (collector, loki, jaeger) — green/red status row at top of Overview dashboard | dashboards | proposed |
| 3 | Add `JaegerDown` and `LokiDown` alerts using the same pattern | alerting | proposed |
| 4 | On second run of incident 03: time-to-detect dropped from 13 minutes to 2 minutes because `OtelCollectorDown` now fires automatically | validated | ✅ |
