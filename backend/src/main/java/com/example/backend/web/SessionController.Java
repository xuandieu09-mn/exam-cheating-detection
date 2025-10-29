package com.example.backend.web;

import jakarta.validation.constraints.NotNull;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.OffsetDateTime;
import java.util.UUID;

record StartSessionRequest(@NotNull UUID userId, @NotNull UUID examId) {}
record StartSessionResponse(UUID sessionId, OffsetDateTime startedAt) {}

@RestController
@RequestMapping("/sessions")
public class SessionController {

  @Autowired
  private JdbcClient jdbc;

  @PostMapping
  public ResponseEntity<?> start(@RequestBody StartSessionRequest req) {
    UUID sessionId = UUID.randomUUID();
    OffsetDateTime now = OffsetDateTime.now();
    jdbc.sql("""
      INSERT INTO sessions(id, user_id, exam_id, started_at, status)
      VALUES(:id, :user_id, :exam_id, :started_at, 'ACTIVE')
    """)
      .param("id", sessionId)
      .param("user_id", req.userId())
      .param("exam_id", req.examId())
      .param("started_at", now)
      .update();
    return ResponseEntity.ok(new StartSessionResponse(sessionId, now));
  }
}