# Day 23 Track 2 — Progress Log

## Session: 2026-05-11

---

## 1. Stack khởi động

Chạy `make up` — 6/7 service khởi động thành công:

| Service | Container | Status |
|---|---|---|
| FastAPI app | day23-app | healthy |
| Prometheus | day23-prometheus | healthy |
| Grafana | day23-grafana | up |
| Loki | day23-loki | up |
| Jaeger | day23-jaeger | up |
| OTel Collector | day23-otel-collector | up |

> Alertmanager không xuất hiện trong `docker ps` — cần kiểm tra thêm.

---

## 2. FastAPI — 01-instrument-fastapi ✅

- `GET /healthz` → `{"status":"ok"}`
- `GET /metrics` → expose đủ 6 metric families:
  - `inference_requests_total`
  - `inference_latency_seconds`
  - `inference_active_gauge`
  - `inference_tokens_total`
  - `inference_quality_score`
  - `gpu_utilization_percent`
- `POST /predict` → trả về `trace_id`, `quality_score`, token counts

---

## 3. Jaeger — Distributed Tracing ✅

**Vấn đề ban đầu:** Jaeger không có service nào sau khi gửi request thông thường.

**Nguyên nhân:** OTel Collector dùng `tail_sampling` với:
- `decision_wait: 30s` — chờ 30s trước khi quyết định giữ trace
- `probabilistic: 1%` — chỉ giữ 1% healthy traces

**Fix:** Gửi request với `fail: true` → trigger HTTP 503 → span status ERROR → giữ 100% bởi `keep-errors` policy.

```bash
curl -X POST localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"prompt": "trigger error", "model": "gpt-mock", "fail": true}'
```

**Kết quả:**
- OTel Collector: `otelcol_exporter_sent_spans{exporter="otlp/jaeger"} 1`
- Jaeger services: `["jaeger-all-in-one", "inference-api"]`
- Trace có span `predict` với child spans `embed-text`, `vector-search`, `generate-tokens`

---

## 4. Loki — Log Aggregation ✅

**Vấn đề ban đầu:** Loki trống — không có label, không có log nào.

**Nguyên nhân:** `docker-compose.yml` thiếu Promtail. App logs ra stdout nhưng không có gì forward vào Loki. OTel Collector config (`otel-config.yaml`) cũng chưa có `filelog` receiver hay `loki` exporter.

**Fix:** Thêm Promtail service vào stack:

- Tạo `03-tracing-and-logs/promtail/promtail-config.yaml`:
  - Scrape Docker socket (`unix:///var/run/docker.sock`)
  - Filter container `day23-app`
  - Parse JSON pipeline: extract `event`, `level`, `trace_id`, `model`
  - Push lên `http://loki:3100/loki/api/v1/push`

- Thêm vào `docker-compose.yml`:
  ```yaml
  promtail:
    image: grafana/promtail:3.3.0
    volumes:
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock
  ```

**Kết quả:**
- Loki labels: `container`, `level`, `model`, `service`, `service_name`, `trace_id`
- Mỗi log line chứa `trace_id` khớp với request
- Grafana Explore → Loki datasource health: `"Data source successfully connected."`
- Query `{service="app"}` trả về log JSON đầy đủ

**Ví dụ log line trong Loki:**
```json
{
  "model": "llama3-mock",
  "input_tokens": 4,
  "output_tokens": 28,
  "quality": 0.805,
  "duration_seconds": 0.3033,
  "trace_id": "0120cfe7c8d3f08427d848df5b9f6112",
  "event": "prediction served",
  "level": "info"
}
```

---

## 5. Grafana Datasources ✅

Đã provisioned sẵn 3 datasources:
- **Prometheus** — `http://prometheus:9090`
- **Loki** — `http://loki:3100` (có derived field `TraceID` → link sang Jaeger)
- **Jaeger** — `http://jaeger:16686`

---

## 7. Alertmanager — Alert Fire/Resolve ✅

**Vấn đề ban đầu:** Alertmanager crash (exit 1) — lỗi `unsupported scheme "" for URL`.

**Nguyên nhân:** Config dùng `{{ env "SLACK_WEBHOOK_URL" }}` không phải cú pháp hợp lệ. Alertmanager không có built-in env var expansion trong config file.

**Fix:** Dùng `slack_api_url_file` kết hợp entrypoint ghi URL vào file:

```yaml
# alertmanager.yml
global:
  slack_api_url_file: /etc/alertmanager/slack_url

# docker-compose.yml
entrypoint:
  - /bin/sh
  - -c
  - "echo $$SLACK_WEBHOOK_URL > /etc/alertmanager/slack_url && /bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml"
```

**Kết quả `make alert`:**
- App bị kill → sau ~80s alert `ServiceDown` fired
- App restart → alert resolved
- Slack nhận đủ 2 tin: FIRING (`#observability`) và RESOLVED

---

## 8. Smoke Test ✅

**Vấn đề:** `make smoke` fail ở Grafana check — grep pattern `"database":"ok"` không match vì Grafana 11.3 trả `"database": "ok"` (có space).

**Fix:** Đổi grep pattern thành `"database"` trong Makefile.

`make smoke` → tất cả 7 services OK.

---

## 9. Submission Checklist

| Checkpoint | Status |
|---|---|
| `/metrics` expose 6 metric families | ✅ |
| Spans visible in Jaeger (`inference-api` service) | ✅ |
| Log line trong Loki có `trace_id` | ✅ |
| Grafana Explore Loki datasource connected | ✅ |
| Alertmanager fire/resolve + Slack notification | ✅ |
| `make smoke` — all 7 services healthy | ✅ |
| `inference_active_gauge` rises during load | Chưa test |
| Drift detection (`drift-summary.json`) | Chưa chạy |
| `submission/REFLECTION.md` > 500 chars | Chưa hoàn thiện |
| `00-setup/setup-report.json` tồn tại | ✅ |

---

## Files đã thay đổi

| File | Thay đổi |
|---|---|
| `docker-compose.yml` | Thêm Promtail, fix Alertmanager entrypoint + image v0.32.1 |
| `03-tracing-and-logs/promtail/promtail-config.yaml` | Tạo mới — Promtail config |
| `02-prometheus-grafana/alertmanager/alertmanager.yml` | Dùng `slack_api_url_file` thay env template |
| `Makefile` | Fix grep pattern cho Grafana health check |
