# Day 23 Lab Reflection

> Fill in each section. Grader reads the "What I'd change" paragraph closest.

**Student:** dang1412
**Submission date:** 2026-05-11
**Lab repo URL:** https://github.com/dang1412/Day23-Track2-Observability-Lab

---

## 1. Hardware + setup output

Paste output of `python3 00-setup/verify-docker.py`:

```
Docker:        OK  (29.1.4)
Compose v2:    OK  (5.0.1)
RAM available: 15.47 GB (OK)
Ports free:    OK
Report written: /home/dang/Projects/vinai/Day23-Track2-Observability-Lab/00-setup/setup-report.json
```

---

## 2. Track 02 — Dashboards & Alerts

### 6 essential panels (screenshot)

Drop `submission/screenshots/dashboard-overview.png`.

### Burn-rate panel

Drop `submission/screenshots/slo-burn-rate.png`.

### Alert fire + resolve

| Thời điểm | Sự kiện | Bằng chứng |
|---|---|---|
| T0 | Kill container `day23-app` | — |
| T0+80s | Alert `ServiceDown` fired | Alertmanager UI + Slack `#observability` |
| T1 | Restore app | — |
| T1+60s | Alert resolved | Slack `#observability` nhận tin resolved |

### One thing surprised me about Prometheus / Grafana

UID của datasource được provision phải khớp chính xác với trường `uid` hardcode trong dashboard JSON — nếu Grafana tự sinh UID ngẫu nhiên lúc khởi động, toàn bộ panel sẽ hiển thị "no data" mà không có thông báo lỗi rõ ràng. Cách fix là thêm `uid: prometheus` vào file provisioning YAML. Đây là một lỗi thầm lặng rất dễ bỏ sót trong môi trường production.

---

## 3. Track 03 — Tracing & Logs

### One trace screenshot from Jaeger

Drop `submission/screenshots/jaeger-trace.png` showing `embed-text → vector-search → generate-tokens` spans.

### Log line correlated to trace

Trace ID: `ad753b23105df5ba7ceca6c8feebbfad`

```json
{"model": "llama3-mock", "input_tokens": 4, "output_tokens": 54, "quality": 0.82, "duration_seconds": 0.1537, "trace_id": "ad753b23105df5ba7ceca6c8feebbfad", "event": "prediction served", "level": "info", "timestamp": "2026-05-11T11:40:50.499793Z"}
```

### Tail-sampling math

Load test sinh ra ~18 req/s trong 60s = ~1.080 requests.

Chính sách tail-sampling:
- `keep-errors`: giữ 100% error spans → 0 lỗi trong load test nên không giữ thêm trace nào
- `keep-slow`: giữ 100% spans > 500ms → P99 = 250ms, không có span nào vượt ngưỡng
- `probabilistic`: giữ 1% số trace còn lại → giữ ~10-11 traces

Tỉ lệ giữ ≈ 10/1080 ≈ **~1%**. Đúng với cấu hình probabilistic 1% — OTel Collector đã loại bỏ 99% traffic bình thường và giữ lại toàn bộ lỗi.

---

## 4. Track 04 — Drift Detection

### PSI scores

```json
{
  "prompt_length": {
    "psi": 3.461,
    "kl": 1.7982,
    "ks_stat": 0.702,
    "ks_pvalue": 0.0,
    "drift": "yes"
  },
  "embedding_norm": {
    "psi": 0.0187,
    "kl": 0.0324,
    "ks_stat": 0.052,
    "ks_pvalue": 0.133853,
    "drift": "no"
  },
  "response_length": {
    "psi": 0.0162,
    "kl": 0.0178,
    "ks_stat": 0.056,
    "ks_pvalue": 0.086899,
    "drift": "no"
  },
  "response_quality": {
    "psi": 8.8486,
    "kl": 13.5011,
    "ks_stat": 0.941,
    "ks_pvalue": 0.0,
    "drift": "yes"
  }
}
```

### Which test fits which feature?

- **prompt_length**: PSI — đây là feature đầu vào có phân bố theo nghiệp vụ (prompt ngắn/vừa/dài). PSI dễ diễn giải (>0.2 là dịch chuyển đáng kể) và phù hợp với monitoring theo bin.
- **embedding_norm**: KS — giá trị liên tục không có bin tự nhiên. KS test không yêu cầu giả định phân bố, nhạy với thay đổi hình dạng phân bố mà không cần chia bin trước.
- **response_length**: KS — lý do tương tự embedding_norm; phân bố liên tục và độ lệch nhỏ (PSI=0.016), KS nhạy hơn PSI trong trường hợp này.
- **response_quality**: KL divergence — quality score bị chặn trong [0,1] và phản ánh trực tiếp sự suy giảm chất lượng model. KL đo mức độ phân kỳ của phân bố hiện tại so với tham chiếu, lý tưởng để giám sát model regression (KL=13.5 là mức báo động nghiêm trọng).

---

## 5. Track 05 — Cross-Day Integration

### Which prior-day metric was hardest to expose? Why?

Metric khó expose nhất là `gpu_utilization_percent`, vì trong môi trường container mock không có GPU thật — metric được sinh tổng hợp. Trong deployment thực tế, để expose GPU metrics cần thêm DCGM exporter sidecar hoặc NVML bindings bên trong inference container, cùng với cgroup permissions phù hợp. Việc cấu hình đúng trên nhiều loại GPU khác nhau (NVIDIA vs AMD) và Kubernetes node selectors tạo ra độ phức tạp vận hành đáng kể so với các metrics ở application layer như request rate hay latency.

---

## 6. The single change that mattered most

Thay đổi có tác động lớn nhất là thêm **Promtail** vào stack và kết nối structured JSON logs từ FastAPI app vào Loki với `trace_id` làm label. Nếu không có điều này, logs và traces tồn tại hoàn toàn độc lập — có thể thấy một span chậm trong Jaeger nhưng không có cách nào liên kết với log line cho thấy model, token counts, và quality score cụ thể. Với `trace_id` là derived field trong Loki datasource, một click trong Grafana Explore sẽ nhảy thẳng từ log line sang trace tương ứng trong Jaeger.

Điều này liên kết trực tiếp với khái niệm "ba trụ cột" trong deck: metrics cho biết *có gì đó sai*, traces cho biết *sai ở đâu trong call graph*, còn logs cho biết *input và output thực sự là gì*. Giá trị chỉ xuất hiện khi cả ba được tương quan qua một định danh chung. `trace_id` chính là định danh đó — và pipeline trích xuất label của Promtail là thứ làm cho nó có thể query được. Không có nó, stack chỉ là ba dashboard rời rạc; có nó, stack trở thành một mặt phẳng điều tra thống nhất.
