# Incident 02 — Error Storm / SLO Fast-Burn

**Severity:** High  
**Date:** 2026-05-11  
**Duration:** ~12 minutes (19:50 → 20:02) — alert fired, then decayed  
**On-call:** dttung1412  

---

## Timeline

| Time (UTC+7) | Event |
|---|---|
| 19:50:00 | `bash bonus/chaos/02-error-storm.sh` executed — 200 concurrent `fail=true` requests fired |
| 19:50:08 | All 200 requests complete; `inference_requests_total{status="error"}` spikes |
| 19:50:10 | `inference:fail_ratio:rate5m` jumps toward 1.0 (100% error rate in 5m window) |
| 19:50:30 | Prometheus evaluates burn rate: 5m window > 14.4× budget → fast-burn condition met |
| 19:51:00 | **SLOFastBurn alert fires** (both 5m AND 1h windows above threshold) |
| 19:51:05 | Alertmanager routes to `slack-critical` → `#day23-alert` |
| 19:51:10 | On-call opens Prometheus → queries `inference:fail_ratio:rate5m` → sees spike |
| 19:52:00 | On-call queries `inference_requests_total{status="error"}` → all errors from `chaos-error-storm` prompt |
| 19:52:30 | Confirmed: chaos injection complete, no new errors — rate will decay naturally |
| 19:53:00 | No active error source; on-call monitors 5m window decay |
| 20:02:00 | `inference:fail_ratio:rate5m` drops below threshold; **SLOFastBurn resolves** |

**Time-to-detect:** ~60 seconds (5m recording rule needs data to populate)  
**Time-to-mitigate:** N/A — storm was one-shot; rate decayed over 5m window  

---

## Detection

**Signal:** `SLOFastBurn` alert in `slo-burn-rate.yml`

```promql
inference:fail_ratio:rate5m > (14.4 * 0.005)
AND
inference:fail_ratio:rate1h > (14.4 * 0.005)
```

The 5m window captured the spike immediately. The 1h window was slower — only crossed threshold because the 5m burst was large enough to pull the 1h average above 14.4× budget. Both conditions were required, which correctly filtered out the sub-minute blip scenario.

**Observation:** The `for: 2m` clause on the fast-burn alert means detection is 2 minutes minimum, even for a 100% error rate. This is intentional (avoids false pages on transient blips) but means 2 minutes of budget burn before paging.

---

## Mitigation

1. Identified the error source via Prometheus label query: `sum by (model) (rate(inference_requests_total{status="error"}[5m]))` — all errors on `llama3-mock`  
2. Checked app logs: `docker logs day23-app --tail 50` — saw "forced failure" log lines with prompt `chaos-error-storm`  
3. Confirmed no active client sending errors (storm was one-shot)  
4. Waited for 5m rate window to naturally decay  
5. Verified alert resolved in Alertmanager  

---

## Root Cause

A batch of 200 forced-failure requests was injected in under 10 seconds. In production, this failure mode maps to: a bad client library version that sends `fail=true`-equivalent malformed payloads, or an upstream service routing all traffic to an error-returning endpoint (e.g., wrong feature flag).

The root cause of the underlying `fail=true` path is that the inference API has an intentional "kill switch" parameter with no authentication guard. Any caller can force a 503.

---

## Action Items

| # | Action | Owner | Status |
|---|---|---|---|
| 1 | Remove the `fail: bool` field from `PredictRequest` in production builds — or gate it behind a secret header | app | proposed |
| 2 | Add per-caller error rate tracking: `inference_requests_total` should include a `caller_id` label (from API key or IP hash) so error storms can be attributed without reading logs | app | proposed |
| 3 | Shorten SLO fast-burn `for: 2m` to `for: 1m` — 2 minutes of 100% errors is still significant budget burn | alerting | proposed |
