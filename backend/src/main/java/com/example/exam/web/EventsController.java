package com.example.exam.web;

import com.example.exam.service.DbService;
import com.example.exam.web.dto.EventRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

@RestController
public class EventsController {
  private final DbService db;

  public EventsController(DbService db) {
    this.db = db;
  }

  @PostMapping("/events")
  public String insert(@Valid @RequestBody EventRequest req) {
    db.insertEventAndRunRules(req);
    return "OK";
  }
}