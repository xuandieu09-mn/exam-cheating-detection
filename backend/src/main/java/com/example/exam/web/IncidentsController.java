package com.example.exam.web;

import com.example.exam.service.DbService;
import com.example.exam.web.dto.IncidentItem;
import com.example.exam.web.dto.ReviewRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
public class IncidentsController {
  private final DbService db;

  public IncidentsController(DbService db) {
    this.db = db;
  }

  @GetMapping("/incidents")
  public List<IncidentItem> list(
      @RequestParam(required = false) UUID examId,
      @RequestParam(required = false) String status,   // OPEN | CONFIRMED | REJECTED
      @RequestParam(required = false) String type,     // PASTE | TAB_ABUSE | ...
      @RequestParam(defaultValue = "1") int page,
      @RequestParam(defaultValue = "20") int pageSize
  ) {
    if (page < 1) page = 1;
    if (pageSize < 1 || pageSize > 200) pageSize = 20;
    return db.listIncidents(examId, status, type, page, pageSize);
  }

  @PostMapping("/incidents/{id}/review")
  public String review(@PathVariable UUID id, @Valid @RequestBody ReviewRequest req) {
    db.upsertReview(id, req.reviewerId, req.status, req.note);
    return "OK";
  }
}