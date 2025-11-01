package com.example.exam.web;

import com.example.exam.service.DbService;
import com.example.exam.web.dto.CreateSessionRequest;
import com.example.exam.web.dto.CreateSessionResponse;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.time.OffsetDateTime;
import java.util.UUID;

@RestController
public class SessionsController {
  private final DbService db;

  public SessionsController(DbService db) {
    this.db = db;
  }

  @PostMapping("/sessions")
  public CreateSessionResponse create(@Valid @RequestBody CreateSessionRequest req) {
    UUID id = db.createSession(req.userId, req.examId, req.ipAddress, req.userAgent);
    return new CreateSessionResponse(id, "ACTIVE", OffsetDateTime.now());
  }
}