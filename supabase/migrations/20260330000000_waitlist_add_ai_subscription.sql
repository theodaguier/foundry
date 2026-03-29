-- Migration: add ai_subscription field to waitlist
-- Created: 2026-03-30

ALTER TABLE waitlist
  ADD COLUMN IF NOT EXISTS ai_subscription TEXT;
