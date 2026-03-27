-- Migration: create waitlist table
-- Created: 2026-03-27

CREATE TABLE IF NOT EXISTS waitlist (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email       TEXT NOT NULL UNIQUE,
  daw         TEXT,
  profile     TEXT,
  message     TEXT,
  status      TEXT NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending', 'invited', 'rejected')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for listing by date
CREATE INDEX IF NOT EXISTS waitlist_created_at_idx ON waitlist (created_at DESC);

-- RLS: only service_role can read/write
ALTER TABLE waitlist ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role only" ON waitlist
  USING (auth.role() = 'service_role');
