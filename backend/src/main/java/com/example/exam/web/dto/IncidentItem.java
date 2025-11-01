package com.example.exam.web.dto;

import java.time.OffsetDateTime;
import java.util.UUID;

public class IncidentItem {
  public UUID id;
  public UUID sessionId;
  public Long ts;
  public String type;
  public Double score;
  public String reason;
  public String evidenceUrl;
  public String status;
  public OffsetDateTime createdAt;
  public UUID examId;

  public IncidentItem() {}
}