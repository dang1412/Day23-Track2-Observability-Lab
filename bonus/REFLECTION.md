# Bonus Reflection — Chaos Engineering & Postmortem

## Bạn ngạc nhiên cái gì?

Điều ngạc nhiên nhất là **incident 03 — OTel Collector chết im lặng hoàn toàn trong 13 phút mà không có alert nào bắt được**. Trước khi làm bài tập này, tôi nghĩ stack đã khá đầy đủ: có ServiceDown, SLO burn-rate, quality drop. Nhưng không ai "observe the observer" — bản thân hệ thống observability (Collector, Loki, Jaeger) lại không được monitor. Khi Collector chết, app vẫn serve request bình thường, metrics vẫn scrape được, error rate vẫn là 0% — không có gì báo động. Nếu không tình cờ mở Jaeger để debug một vấn đề khác, tôi sẽ không phát hiện ra.

Điều ngạc nhiên thứ hai là tốc độ của incident 01 vs 02. Kill app → alert fire trong 65 giây; nhưng error storm → alert fire cũng mất ~60 giây dù error rate nhảy lên 100% ngay lập tức. Lý do là `for: 2m` trên SLO alert — thiết kế đúng để tránh false positive, nhưng 2 phút với 100% error rate là khá dài. Cần cân bằng giữa noise và speed.

## Nếu có thêm 8 giờ nữa bạn sẽ build cái gì tiếp?

Tôi sẽ implement toàn bộ action items từ 3 postmortem thành code thật:

1. **"Observe the observer" dashboard row** — thêm stat panels cho `up{job=~"otel-collector|loki|jaeger"}` vào Grafana Overview dashboard, hiển thị đỏ/xanh theo real-time. Hiện tại không có panel nào cho thấy trạng thái của infrastructure phục vụ observability.

2. **JaegerDown + LokiDown alerts** — cùng pattern với `OtelCollectorDown` vừa thêm. Ba alerts này tạo thành "observability health check" — khi stack bị impaired, on-call biết trước khi users phát hiện traces/logs bị thiếu.

3. **Thứ ba là Lần chạy lại incident 03 để đo time-to-detect sau khi có alert** — postmortem tốt không chỉ liệt kê action items mà còn validate chúng. Với `OtelCollectorDown` alert đã thêm, lần inject thứ 2 phải detect trong 2 phút thay vì 13 phút. Muốn có số đo thật để so sánh.
