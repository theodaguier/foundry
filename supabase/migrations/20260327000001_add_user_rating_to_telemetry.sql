-- Migration: add user_rating to generation_telemetry
-- 1  = thumbs up (good)
-- -1 = thumbs down (bad)
-- NULL = no rating given
-- Created: 2026-03-27

ALTER TABLE generation_telemetry
  ADD COLUMN IF NOT EXISTS user_rating SMALLINT CHECK (user_rating IN (-1, 1));
