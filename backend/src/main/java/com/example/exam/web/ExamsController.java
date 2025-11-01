package com.example.exam.web;

import com.example.exam.service.DbService;
import com.example.exam.web.dto.ExamItem;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
public class ExamsController {
  private final DbService db;

  public ExamsController(DbService db) {
    this.db = db;
  }

  @GetMapping("/exams")
  public List<ExamItem> list() {
    return db.listExams();
  }
}