package com.example.exam.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.util.Map;
import java.util.UUID;

public class EventRequest {
  @NotNull
  public UUID sessionId;

  // Ví dụ: "TAB_SWITCH", "PASTE", "FOCUS", "BLUR"
  @NotBlank
  public String eventType;

  // epoch millis
  @NotNull
  public Long ts;

  // Tuỳ chọn
  public Map<String, Object> details;

  // Khuyên dùng: UUID string để tránh trùng lặp khi retry
  public String idempotencyKey;
}