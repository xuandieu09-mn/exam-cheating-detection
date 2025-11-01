package com.example.exam.web.dto;

import java.time.OffsetDateTime;
import java.util.UUID;

public class ExamItem {
  public UUID id;
  public String name;
  public OffsetDateTime createdAt;
}