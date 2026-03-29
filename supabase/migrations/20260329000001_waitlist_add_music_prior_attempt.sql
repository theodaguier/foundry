-- Migration: add music_genre and prior_attempt fields to waitlist
-- Created: 2026-03-29

ALTER TABLE waitlist
  ADD COLUMN IF NOT EXISTS music_genre TEXT,
  ADD COLUMN IF NOT EXISTS prior_attempt TEXT,
  ADD COLUMN IF NOT EXISTS prior_attempt_detail TEXT;
