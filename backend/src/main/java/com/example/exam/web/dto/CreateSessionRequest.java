package com.example.exam.web.dto;

import jakarta.validation.constraints.NotNull;
import java.util.UUID;

public class CreateSessionRequest {
  @NotNull
  public UUID userId;
  @NotNull
  public UUID examId;
  public String ipAddress;
  public String userAgent;
}