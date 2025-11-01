-- seed_sample_data_idempotent.sql
-- Idempotent sample data for exam-cheating-detection (safe to run multiple times)
-- Run in DB examdb (pgAdmin Query Tool or psql)

-- 0) Ensure pgcrypto available for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1) Insert sample users (do nothing if username already exists)
INSERT INTO users (id, username, email, password_hash, role)
VALUES
  (gen_random_uuid(), 'admin',    'admin@example.com',    'pw-hash-admin',    'ADMIN')
ON CONFLICT (username) DO UPDATE SET email = EXCLUDED.email
RETURNING id, username
;

INSERT INTO users (id, username, email, password_hash, role)
VALUES (gen_random_uuid(), 'reviewer', 'reviewer@example.com', 'pw-hash-reviewer', 'REVIEWER')
ON CONFLICT (username) DO NOTHING;

INSERT INTO users (id, username, email, password_hash, role)
VALUES (gen_random_uuid(), 'proctor', 'proctor@example.com', 'pw-hash-proctor', 'PROCTOR')
ON CONFLICT (username) DO NOTHING;

INSERT INTO users (id, username, email, password_hash, role)
VALUES (gen_random_uuid(), 'student', 'student@example.com', 'pw-hash-student', 'CANDIDATE')
ON CONFLICT (username) DO NOTHING;

-- 2) Create a sample exam if not exists (identified by name)
WITH admin_u AS (
  SELECT id AS admin_id FROM users WHERE username = 'admin' LIMIT 1
)
INSERT INTO exams (id, name, description, start_time, end_time, retention_days, created_by)
SELECT gen_random_uuid(), 'Kỳ thi mẫu', 'Exam demo seed', now() - interval '30 minutes', now() + interval '2 hours', 30, admin_id
FROM admin_u
WHERE NOT EXISTS (SELECT 1 FROM exams WHERE name = 'Kỳ thi mẫu');

-- 3) Create a session for student for the latest "Kỳ thi mẫu" if none recent
WITH s AS (
  SELECT u.id AS user_id, e.id AS exam_id
  FROM users u, exams e
  WHERE u.username = 'student' AND e.name = 'Kỳ thi mẫu'
  LIMIT 1
)
INSERT INTO sessions (id, user_id, exam_id, started_at, status, ip_address, user_agent)
SELECT gen_random_uuid(), s.user_id, s.exam_id, now() - interval '10 minutes', 'ACTIVE', '127.0.0.1', 'Chrome/Windows'
FROM s
WHERE NOT EXISTS (
  SELECT 1 FROM sessions ss
  WHERE ss.user_id = s.user_id AND ss.exam_id = s.exam_id AND ss.started_at > now() - interval '1 day'
)
RETURNING id;

-- 4) Insert telemetry events for the latest session (tab switch, paste)
WITH latest_session AS (
  SELECT id AS session_id FROM sessions ORDER BY started_at DESC LIMIT 1
)
INSERT INTO events (id, session_id, ts, event_type, details, idempotency_key)
SELECT gen_random_uuid(),
       ls.session_id,
       (EXTRACT(EPOCH FROM NOW())*1000)::bigint,
       'TAB_SWITCH',
       '{"count":1}'::jsonb,
       gen_random_uuid()::text
FROM latest_session ls
-- avoid inserting the same event repeatedly in a short window
WHERE NOT EXISTS (
  SELECT 1 FROM events e
  WHERE e.session_id = ls.session_id AND e.event_type = 'TAB_SWITCH' AND e.created_at > now() - interval '5 minutes'
);

WITH latest_session AS (
  SELECT id AS session_id FROM sessions ORDER BY started_at DESC LIMIT 1
)
INSERT INTO events (id, session_id, ts, event_type, details, idempotency_key)
SELECT gen_random_uuid(),
       ls.session_id,
       (EXTRACT(EPOCH FROM NOW())*1000)::bigint,
       'PASTE',
       '{"field":"answer1"}'::jsonb,
       gen_random_uuid()::text
FROM latest_session ls
WHERE NOT EXISTS (
  SELECT 1 FROM events e
  WHERE e.session_id = ls.session_id AND e.event_type = 'PASTE' AND e.created_at > now() - interval '5 minutes'
);

-- 5) Insert sample media_snapshot (webcam image metadata) for latest session
WITH latest_session AS (
  SELECT id AS session_id FROM sessions ORDER BY started_at DESC LIMIT 1
)
INSERT INTO media_snapshots (id, session_id, ts, object_key, file_size, mime_type, uploaded_at, face_count, idempotency_key)
SELECT gen_random_uuid(),
       ls.session_id,
       (EXTRACT(EPOCH FROM NOW())*1000)::bigint,
       concat('samples/', ls.session_id::text, '/img-1.jpg')::text,
       12345,
       'image/jpeg',
       now(),
       1,
       gen_random_uuid()::text
FROM latest_session ls
WHERE NOT EXISTS (
  SELECT 1 FROM media_snapshots m WHERE m.session_id = ls.session_id AND m.object_key LIKE concat('samples/', ls.session_id::text, '/img-1.jpg')
);

-- 6) Insert two incidents (OPEN) for that session if not exists (TAB_ABUSE and PASTE)
WITH latest_session AS (
  SELECT id AS session_id FROM sessions ORDER BY started_at DESC LIMIT 1
)
INSERT INTO incidents (id, session_id, ts, type, score, reason, evidence_url, status)
SELECT gen_random_uuid(),
       ls.session_id,
       (EXTRACT(EPOCH FROM NOW())*1000)::bigint,
       'TAB_ABUSE',
       0.50,
       'Tab abuse demo',
       concat('samples/', ls.session_id::text, '/img-1.jpg'),
       'OPEN'
FROM latest_session ls
WHERE NOT EXISTS (
  SELECT 1 FROM incidents i WHERE i.session_id = ls.session_id AND i.type = 'TAB_ABUSE' AND i.created_at > now() - interval '1 day'
);

WITH latest_session AS (
  SELECT id AS session_id FROM sessions ORDER BY started_at DESC LIMIT 1
)
INSERT INTO incidents (id, session_id, ts, type, score, reason, evidence_url, status)
SELECT gen_random_uuid(),
       ls.session_id,
       (EXTRACT(EPOCH FROM NOW())*1000)::bigint,
       'PASTE',
       0.40,
       'Paste demo',
       concat('samples/', ls.session_id::text, '/img-1.jpg'),
       'OPEN'
FROM latest_session ls
WHERE NOT EXISTS (
  SELECT 1 FROM incidents i WHERE i.session_id = ls.session_id AND i.type = 'PASTE' AND i.created_at > now() - interval '1 day'
);

-- 7) Optionally create a review by 'reviewer' for one incident (mark CONFIRMED) once
WITH r AS (SELECT id FROM users WHERE username = 'reviewer' LIMIT 1),
     incident_to_review AS (
       SELECT id FROM incidents WHERE type = 'TAB_ABUSE' ORDER BY created_at DESC LIMIT 1
     )
INSERT INTO reviews (id, incident_id, reviewer_id, status, note)
SELECT gen_random_uuid(), ir.id, r.id, 'CONFIRMED', 'Sample confirm by reviewer'
FROM incident_to_review ir, r
ON CONFLICT (incident_id) DO NOTHING;

-- 8) Short verification selects (for convenience)
SELECT count(*) AS users_cnt FROM users;
SELECT id, username, role FROM users ORDER BY created_at;
SELECT id, name, created_at FROM exams ORDER BY created_at DESC LIMIT 5;
SELECT id, user_id, exam_id, started_at, status FROM sessions ORDER BY started_at DESC LIMIT 5;
SELECT id, session_id, event_type, to_timestamp(ts/1000.0) AS when_utc, details FROM events ORDER BY created_at DESC LIMIT 10;
SELECT id, session_id, type, status, reason, evidence_url FROM incidents ORDER BY created_at DESC LIMIT 10;
SELECT * FROM incidents_with_exam ORDER BY ts DESC LIMIT 10;
``` ````

Giải thích từng phần (ngắn gọn, rõ ràng)

- CREATE EXTENSION IF NOT EXISTS "pgcrypto";
  - Vì schema dùng gen_random_uuid() cho id mặc định. Đảm bảo hàm có sẵn.

- 1) Users
  - Tạo 4 user mẫu: admin, reviewer, proctor, student.
  - ON CONFLICT (username) DO NOTHING / DO UPDATE: để chạy seed nhiều lần không gây lỗi duplicate.
  - Tại sao cần: để test từng vai trò — admin tạo exam; student tạo session; reviewer duyệt incidents.

- 2) Exams
  - Tạo “Kỳ thi mẫu” do admin tạo (gán created_by = admin).
  - Kiểm tra NOT EXISTS by name để không tạo trùng.
  - Tại sao: cần kỳ thi để tạo session → incidents gắn vào exam thông qua sessions.

- 3) Sessions
  - Tạo 1 session cho student trong exam vừa tạo.
  - Condition NOT EXISTS → tránh tạo session trùng nếu đã có session gần đây.
  - Tại sao: session là trung tâm — events, media_snapshots, incidents liên kết tới session_id.

- 4) Events
  - Thêm 2 event mẫu (TAB_SWITCH, PASTE).
  - ts là epoch millis; idempotency_key gen_random_uuid() để tránh duplicate.
  - WHERE NOT EXISTS tránh spam insert khi chạy seed liên tục.
  - Tại sao: để test rule TAB_ABUSE (count tab switches) và PASTE detection.

- 5) Media snapshots
  - Thêm 1 metadata ảnh (object_key sample path). face_count=1 (vision giả lập).
  - Tại sao: evidence_url trong incidents có thể trỏ tới object_key; Vision service có thể update face_count sau khi xử lý.

- 6) Incidents
  - Tạo 2 incidents OPEN: TAB_ABUSE và PASTE (với score và evidence_url).
  - WHERE NOT EXISTS tránh tạo nhiều incidents giống nhau khi chạy seed nhiều lần.
  - Tại sao: để reviewer xem danh sách cảnh báo, test flow review → status change.

- 7) Reviews
  - Tạo 1 review CONFIRMED cho incident TAB_ABUSE bởi reviewer (ON CONFLICT DO NOTHING tránh duplicate unique incident_id).
  - Trigger trong schema sẽ tự động cập nhật incidents.status → CONFIRMED khi insert review. Đây là cách test trigger hoạt động.
  - Tại sao: test flow reviewer duyệt cảnh báo và cập nhật status.

- 8) Verification selects
  - Một số SELECT mẫu để bạn copy/paste chạy nhanh kiểm tra kết quả seed.

Cách chạy (ngắn gọn)
- Trong pgAdmin Query Tool: mở file seed_sample_data_idempotent.sql → Execute.
- Hoặc Docker:
  docker exec -i exam-postgres psql -U postgres -d examdb < "E:\...path...\sql\seed_sample_data_idempotent.sql"

Các kiểm tra bạn nên thực hiện sau khi chạy
- SELECT count(*) FROM users; → expect >= 4
- SELECT * FROM sessions ORDER BY started_at DESC LIMIT 1; → có 1 session ACTIVE
- SELECT * FROM events WHERE session_id = <that session id> ORDER BY created_at DESC LIMIT 10; → thấy TAB_SWITCH / PASTE
- SELECT * FROM incidents_with_exam WHERE exam_id = <exam id> ORDER BY ts DESC LIMIT 10; → thấy incidents
- SELECT * FROM reviews ORDER BY reviewed_at DESC LIMIT 10; → thấy review (nếu inserted)

Vì sao seed này có ích cho dự án (liên hệ chức năng)
- Cho phép bạn chạy toàn bộ flow MVP mà không cần UI:
  - Tạo session → ingest events → rule engine tạo incidents → reviewer confirm/reject.
- Test trigger logic: insert review → incidents.status tự đổi nhờ trigger.
- Test APIs backend: bạn có dữ liệu sẵn để GET /incidents, GET /sessions, POST /events, etc.
- Giúp UI/FE dev có dữ liệu thật để hiển thị bảng danh sách cảnh báo, chi tiết ảnh, workflow duyệt.

Nếu bạn muốn mình tiếp:
- A) Gửi phiên bản seed "hoàn toàn sạch" (xóa dữ liệu mẫu cũ trước khi chèn) — nếu muốn reset hoàn toàn DB dev.
- B) Gửi hướng dẫn step-by-step chạy seed + kiểm tra (các câu SELECT + ví dụ output mong đợi).
- C) Tạo sẵn các API Spring Boot mẫu (Controller + Repository/Sql) tương thích để bạn paste vào backend và test (ví dụ: POST /events, GET /incidents, POST /incidents/{id}/review).

Chọn A / B / C hoặc nói "Chạy seed" nếu bạn muốn mình cung cấp lệnh Docker/pgAdmin chính xác để chạy seed này ngay.