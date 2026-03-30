-- Backfill NULL channel_layout values with 'stereo' and add a default
-- so future inserts without this field don't violate the NOT NULL constraint.

UPDATE generation_telemetry
SET channel_layout = 'stereo'
WHERE channel_layout IS NULL OR channel_layout = '';

ALTER TABLE generation_telemetry
  ALTER COLUMN channel_layout SET DEFAULT 'stereo';
