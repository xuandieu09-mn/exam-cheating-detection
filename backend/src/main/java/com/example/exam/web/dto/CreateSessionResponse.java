package com.example.exam.web.dto;

import java.time.OffsetDateTime;
import java.util.UUID;

public class CreateSessionResponse {
  public UUID id;
  public String status;
  public OffsetDateTime startedAt;

  public CreateSessionResponse(UUID id, String status, OffsetDateTime startedAt) {
    this.id = id;
    this.status = status;
    this.startedAt = startedAt;
  }
}