# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A 7-service Docker Compose observability lab (Day 23, AICB Track 2). The stack consists of:
- **FastAPI app** (`01-instrument-fastapi/app/`) — mock LLM inference service emitting Prometheus metrics, OTLP traces, and structured JSON logs
- **Prometheus + Alertmanager** (`02-prometheus-grafana/prometheus/`) — scrape config, SLO burn-rate rules, alert rules
- **Grafana** (`02-prometheus-grafana/grafana/`) — 3 provisioned dashboards (overview, SLO burn-rate, cost-and-tokens)
- **OTel Collector** (`03-tracing-and-logs/otel-collector/`) — tail-sampling (keep errors + slow + 1% healthy), exports traces to Jaeger
- **Loki** (`03-tracing-and-logs/loki/`) — log storage
- **Jaeger** — trace UI and storage
- **Drift detection** (`04-drift-detection/scripts/drift_detect.py`) — PSI, KL, KS tests on synthetic shifted dataset; outputs `04-drift-detection/reports/drift-summary.json`

## Common commands

```bash
make setup          # one-time: pull images + run verify-docker.py
make up             # start all 7 services (detached)
make smoke          # health-check all services (~30s after up)
make load           # 60s locust load test (concurrency=10) against localhost:8000
make alert          # kill app → wait for Alertmanager fire → restore → wait for resolve
make trace          # POST /predict and print the trace_id
make drift          # run PSI/KL/KS drift detection; writes drift-summary.json
make demo           # load + alert + trace + drift in sequence
make verify         # rubric gate — exit 0 = all checkpoints pass
make lint-dashboards # validate Grafana dashboard JSONs
make down           # stop stack (preserves volumes)
make clean          # stop + remove volumes (destructive)
```

## Service ports (all localhost-only)

| Service | Port |
|---|---|
| FastAPI app | 8000 |
| Prometheus | 9090 |
| Alertmanager | 9093 |
| Grafana | 3000 (admin/admin) |
| Loki | 3100 |
| Jaeger UI | 16686 |
| OTel Collector self-metrics | 8888 |

## Key files and their roles

- `instrumentation.py` — single source of truth for all metric/span/log names; defines the 6 Prometheus metric families: `inference_requests_total`, `inference_latency_seconds`, `inference_active_gauge`, `inference_tokens_total`, `inference_quality_score`, `gpu_utilization_percent`
- `scripts/verify.py` — the rubric gate; checks file existence, HTTP endpoints, dashboard count, and drift-summary content
- `.env` / `.env.example` — `SLACK_WEBHOOK_URL` must be set for alert fire/resolve tests
- `02-prometheus-grafana/prometheus/rules/` — SLO burn-rate and AI quality alert rules
- `submission/REFLECTION.md` — must be >500 chars and fill sections 1-5 to pass `make verify`

## Architecture flow

```
POST /predict
  → FastAPI (main.py)
      → Prometheus metrics (instrumentation.py)
      → OTLP spans → OTel Collector (:4317)
                        → tail_sampling processor
                        → Jaeger (:14250)
      → structlog JSON → stdout → (Loki via Promtail — not wired by default)
GET /metrics → Prometheus scrapes → Grafana dashboards
```

## Submission requirements

`make verify` checks (exit 0 required):
1. `00-setup/setup-report.json` exists
2. App `/healthz` and `/metrics` reachable with `inference_requests_total` present
3. Prometheus, Grafana, Alertmanager reachable
4. ≥3 dashboards matching "Day 23" in Grafana API
5. Jaeger, Loki, OTel Collector reachable
6. `04-drift-detection/reports/drift-summary.json` has ≥1 feature with `drift: yes`
7. `submission/REFLECTION.md` exists and is >500 chars

Screenshots go in `submission/screenshots/`; grader reads `submission/REFLECTION.md`.

## Python environment

Root `requirements.txt` covers lab scripts. The FastAPI app has its own `01-instrument-fastapi/app/requirements.txt` and is built via Docker. Run `pip install -r requirements.txt` for host-side scripts (verify.py, drift_detect.py, locustfile.py). Drift detection optionally uses `evidently` (install separately with `pip install evidently`).
