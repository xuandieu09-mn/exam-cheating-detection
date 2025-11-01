-- new_schema_fixed.sql
-- Idempotent schema for Online Exam Fraud Detection (fixed DROP TYPE lines)
-- Uses gen_random_uuid() from pgcrypto for UUID generation.
-- Run in target database (e.g., examdb) via pgAdmin Query Tool or psql.

-- 0) Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1) Drop existing objects (safe re-run)
DROP VIEW IF EXISTS incidents_with_exam CASCADE;

DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS incidents CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS media_snapshots CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;
DROP TABLE IF EXISTS exams CASCADE;
DROP TABLE IF EXISTS users CASCADE;

DROP TYPE IF EXISTS user_role CASCADE;
DROP TYPE IF EXISTS session_status CASCADE;
DROP TYPE IF EXISTS event_type CASCADE;
DROP TYPE IF EXISTS incident_type CASCADE;
DROP TYPE IF EXISTS incident_status CASCADE;
DROP TYPE IF EXISTS review_status CASCADE;

-- 2) Create enums
CREATE TYPE user_role AS ENUM ('ADMIN', 'PROCTOR', 'REVIEWER', 'CANDIDATE');
CREATE TYPE session_status AS ENUM ('ACTIVE', 'ENDED', 'ABORTED');
CREATE TYPE event_type AS ENUM ('TAB_SWITCH', 'PASTE', 'FOCUS', 'BLUR');
CREATE TYPE incident_type AS ENUM ('NO_FACE', 'MULTI_FACE', 'TAB_ABUSE', 'PASTE');
CREATE TYPE incident_status AS ENUM ('OPEN', 'CONFIRMED', 'REJECTED');
CREATE TYPE review_status AS ENUM ('CONFIRMED', 'REJECTED');

-- 3) Tables

-- users
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(100) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role user_role NOT NULL DEFAULT 'CANDIDATE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- exams
CREATE TABLE exams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  start_time TIMESTAMPTZ,
  end_time TIMESTAMPTZ,
  retention_days INT NOT NULL DEFAULT 30,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (end_time IS NULL OR start_time IS NULL OR end_time > start_time)
);

-- sessions (allow multiple sessions per user/exam)
CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  exam_id UUID NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  ip_address INET,
  user_agent TEXT,
  status session_status NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (ended_at IS NULL OR ended_at > started_at)
);

-- media_snapshots (webcam images)
CREATE TABLE media_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  ts BIGINT NOT NULL, -- epoch milliseconds
  object_key TEXT NOT NULL UNIQUE,
  file_size BIGINT,
  mime_type VARCHAR(100),
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  face_count INT, -- NULL until processed
  idempotency_key VARCHAR(255) UNIQUE,
  CHECK (face_count IS NULL OR face_count >= 0)
);

-- events (browser telemetry)
CREATE TABLE events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  ts BIGINT NOT NULL, -- epoch milliseconds
  event_type event_type NOT NULL,
  details JSONB,
  idempotency_key VARCHAR(255) UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- incidents (alerts)
CREATE TABLE incidents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  ts BIGINT NOT NULL, -- epoch milliseconds when incident created
  type incident_type NOT NULL,
  score NUMERIC(5,2),
  reason TEXT,
  evidence_url TEXT,
  status incident_status NOT NULL DEFAULT 'OPEN',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- reviews (proctor decisions) - one final review per incident (unique)
CREATE TABLE reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
  status review_status NOT NULL,
  note TEXT,
  reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (incident_id)
);

-- 4) Indexes for common queries
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_exams_created_by ON exams(created_by);
CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_exam ON sessions(exam_id);
CREATE INDEX idx_media_snapshots_session_ts ON media_snapshots(session_id, ts);
CREATE INDEX idx_events_session_ts ON events(session_id, ts);
CREATE INDEX idx_events_type ON events(event_type);
CREATE INDEX idx_incidents_session_ts ON incidents(session_id, ts);
CREATE INDEX idx_incidents_type_status ON incidents(type, status);
CREATE INDEX idx_reviews_reviewer ON reviews(reviewer_id);

-- 5) View: incidents with exam_id for easy filtering
CREATE OR REPLACE VIEW incidents_with_exam AS
SELECT i.*, s.exam_id
FROM incidents i
JOIN sessions s ON s.id = i.session_id;

-- 6) Trigger functions

-- Update updated_at timestamp on users/exams
CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_updated_at_users ON users;
CREATE TRIGGER set_updated_at_users
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_exams ON exams;
CREATE TRIGGER set_updated_at_exams
BEFORE UPDATE ON exams
FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- Sync incident.status when review inserted/updated
CREATE OR REPLACE FUNCTION trg_sync_incident_status_from_review()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    UPDATE incidents
    SET status = CASE NEW.status WHEN 'CONFIRMED' THEN 'CONFIRMED' WHEN 'REJECTED' THEN 'REJECTED' END
    WHERE id = NEW.incident_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    -- do nothing here; separate trigger handles delete revert
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_incident_status ON reviews;
CREATE TRIGGER trg_sync_incident_status
AFTER INSERT OR UPDATE ON reviews
FOR EACH ROW EXECUTE FUNCTION trg_sync_incident_status_from_review();

-- When a review is deleted, revert incident to OPEN
CREATE OR REPLACE FUNCTION trg_reopen_incident_on_review_delete()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE incidents SET status = 'OPEN' WHERE id = OLD.incident_id;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_reopen_incident ON reviews;
CREATE TRIGGER trg_reopen_incident
AFTER DELETE ON reviews
FOR EACH ROW EXECUTE FUNCTION trg_reopen_incident_on_review_delete();


-- Sửa lại trigger function này:
CREATE OR REPLACE FUNCTION trg_sync_incident_status_from_review()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    UPDATE incidents
    SET status = CASE NEW.status
      WHEN 'CONFIRMED' THEN 'CONFIRMED'::incident_status
      WHEN 'REJECTED' THEN 'REJECTED'::incident_status
    END
    WHERE id = NEW.incident_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;
-- End of script (no VACUUM)