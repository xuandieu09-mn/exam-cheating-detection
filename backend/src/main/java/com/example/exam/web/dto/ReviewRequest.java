package com.example.exam.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.util.UUID;

public class ReviewRequest {
  @NotNull
  public UUID reviewerId;

  // "CONFIRMED" hoặc "REJECTED"
  @NotBlank
  public String status;

  public String note;
}