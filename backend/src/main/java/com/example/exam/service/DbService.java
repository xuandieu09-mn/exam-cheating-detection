package com.example.exam.service;

import com.example.exam.web.dto.EventRequest;
import com.example.exam.web.dto.IncidentItem;
import com.example.exam.web.dto.ExamItem;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.*;

@Service
public class DbService {
  private final JdbcTemplate jdbc;

  public DbService(JdbcTemplate jdbc) {
    this.jdbc = jdbc;
  }

  // ========== EXAMS ==========
  public List<ExamItem> listExams() {
    return jdbc.query("""
        SELECT id, name, created_at
        FROM exams
        ORDER BY created_at DESC
        LIMIT 100
        """, (rs, i) -> {
      ExamItem e = new ExamItem();
      e.id = (UUID) rs.getObject("id");
      e.name = rs.getString("name");
      e.createdAt = rs.getObject("created_at", OffsetDateTime.class);
      return e;
    });
  }

  // ========== SESSIONS ==========
  public UUID createSession(UUID userId, UUID examId, String ip, String ua) {
    UUID id = UUID.randomUUID();
    jdbc.update("""
        INSERT INTO sessions (id, user_id, exam_id, started_at, status, ip_address, user_agent)
        VALUES (?, ?, ?, now(), 'ACTIVE', ?, ?)
        """, id, userId, examId, ip, ua);
    return id;
  }

  // ========== EVENTS + RULES ==========
  @Transactional
  public void insertEventAndRunRules(EventRequest req) {
    UUID id = UUID.randomUUID();

    String idem = (req.idempotencyKey == null || req.idempotencyKey.isBlank())
        ? UUID.randomUUID().toString()
        : req.idempotencyKey;

    String detailsJson = req.details == null ? null : toJson(req.details);

    try {
      jdbc.update("""
          INSERT INTO events (id, session_id, ts, event_type, details, idempotency_key)
          VALUES (?, ?, ?, ?::event_type, ?::jsonb, ?)
          """,
          id, req.sessionId, req.ts, req.eventType, detailsJson, idem
      );
    } catch (DuplicateKeyException e) {
      // idempotency_key trùng: coi như OK, không làm gì thêm
      return;
    }

    // Sau khi ghi event, chạy rules đơn giản
    runRulesForSession(req.sessionId, req.eventType, req.ts);
  }

  private void runRulesForSession(UUID sessionId, String eventType, long eventTs) {
    // Rule 1: Nếu là PASTE -> tạo incident PASTE (tránh trùng trong 10 phút)
    if ("PASTE".equalsIgnoreCase(eventType)) {
      maybeCreateIncident(
          sessionId, eventTs,
          "PASTE", 0.40, "Paste detected",
          /*dedupWindowMillis*/10 * 60_000L
      );
    }

    // Rule 2: TAB_ABUSE: nếu trong 5 phút có > 3 TAB_SWITCH -> tạo incident
    long windowStart = eventTs - 5 * 60_000L;
    Integer cnt = jdbc.queryForObject("""
        SELECT COUNT(*) FROM events
        WHERE session_id = ?
          AND event_type = 'TAB_SWITCH'::event_type
          AND ts > ?
        """, Integer.class, sessionId, windowStart);

    if (cnt != null && cnt > 3) {
      maybeCreateIncident(
          sessionId, eventTs,
          "TAB_ABUSE", 0.50, "Too many TAB switches in 5 minutes",
          /*dedupWindowMillis*/10 * 60_000L
      );
    }
  }

  private void maybeCreateIncident(UUID sessionId, long ts, String type, double score, String reason, long dedupWindowMillis) {
    long recentSince = ts - dedupWindowMillis;

    Integer existed = jdbc.queryForObject("""
        SELECT COUNT(*) FROM incidents
        WHERE session_id = ?
          AND type = ?::incident_type
          AND ts > ?
        """, Integer.class, sessionId, type, recentSince);

    if (existed != null && existed > 0) {
      return; // đã có incident tương tự gần đây
    }

    // Lấy evidence_url: ảnh mới nhất (nếu có)
    String evidence = jdbc.query("""
        SELECT object_key
        FROM media_snapshots
        WHERE session_id = ?
        ORDER BY uploaded_at DESC
        LIMIT 1
        """,
        ps -> ps.setObject(1, sessionId),
        rs -> rs.next() ? rs.getString("object_key") : null
    );

    jdbc.update("""
        INSERT INTO incidents (id, session_id, ts, type, score, reason, evidence_url, status)
        VALUES (?, ?, ?, ?::incident_type, ?, ?, ?, 'OPEN'::incident_status)
        """, UUID.randomUUID(), sessionId, ts, type, score, reason, evidence);
  }

  // ========== INCIDENTS ==========
  public List<IncidentItem> listIncidents(UUID examId, String status, String type, int page, int pageSize) {
    StringBuilder sql = new StringBuilder("""
      SELECT i.id, i.session_id, i.ts, i.type::text AS type, i.score, i.reason, i.evidence_url,
             i.status::text AS status, i.created_at, s.exam_id
      FROM incidents i
      JOIN sessions s ON s.id = i.session_id
      WHERE 1=1
      """);

    List<Object> params = new ArrayList<>();
    if (examId != null) {
      sql.append(" AND s.exam_id = ? ");
      params.add(examId);
    }
    if (status != null && !status.isBlank()) {
      sql.append(" AND i.status = ?::incident_status ");
      params.add(status);
    }
    if (type != null && !type.isBlank()) {
      sql.append(" AND i.type = ?::incident_type ");
      params.add(type);
    }
    sql.append(" ORDER BY i.ts DESC ");
    sql.append(" LIMIT ? OFFSET ? ");
    params.add(pageSize);
    params.add((page - 1) * pageSize);

    return jdbc.query(sql.toString(), params.toArray(), incidentRowMapper());
  }

  public void upsertReview(UUID incidentId, UUID reviewerId, String status, String note) {
    jdbc.update("""
      INSERT INTO reviews (id, incident_id, reviewer_id, status, note)
      VALUES (?, ?, ?, ?::review_status, ?)
      ON CONFLICT (incident_id) DO UPDATE
        SET reviewer_id = EXCLUDED.reviewer_id,
            status = EXCLUDED.status,
            note = EXCLUDED.note,
            reviewed_at = now()
      """, UUID.randomUUID(), incidentId, reviewerId, status, note);
    // Trigger DB sẽ tự cập nhật incidents.status
  }

  // ========== Helpers ==========
  private RowMapper<IncidentItem> incidentRowMapper() {
    return new RowMapper<>() {
      @Override public IncidentItem mapRow(ResultSet rs, int rowNum) throws SQLException {
        IncidentItem it = new IncidentItem();
        it.id = (UUID) rs.getObject("id");
        it.sessionId = (UUID) rs.getObject("session_id");
        it.ts = rs.getLong("ts");
        it.type = rs.getString("type");
        it.score = rs.getObject("score") == null ? null : rs.getDouble("score");
        it.reason = rs.getString("reason");
        it.evidenceUrl = rs.getString("evidence_url");
        it.status = rs.getString("status");
        it.createdAt = rs.getObject("created_at", OffsetDateTime.class);
        it.examId = (UUID) rs.getObject("exam_id");
        return it;
      }
    };
  }

  private String toJson(Map<String, Object> map) {
    // Dùng JSON đơn giản (String.format) sẽ rủi ro; tốt nhất dùng Jackson.
    // Nhưng ở đây JdbcTemplate không cần convert phức tạp vì ta cast ?::jsonb trong SQL.
    try {
      // Dùng Jackson mặc định của Spring
      return new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(map);
    } catch (Exception e) {
      throw new RuntimeException("Cannot serialize details to JSON", e);
    }
  }
}