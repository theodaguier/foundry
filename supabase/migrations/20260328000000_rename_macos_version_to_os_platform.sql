-- Migration: rename macos_version to os_platform in generation_telemetry
-- Foundry is now cross-platform (macOS, Windows, Linux)
-- Created: 2026-03-28
--
-- Note: os_platform column already exists (created by migration 20260328001737).
-- macos_version column was dropped when os_platform was added separately.
-- This migration is now a no-op for the schema change, but still backfills data.

-- Copy any remaining macos_version data into os_platform if macos_version still exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'generation_telemetry' AND column_name = 'macos_version'
  ) THEN
    EXECUTE 'UPDATE generation_telemetry SET os_platform = ''macos'' WHERE macos_version IS NOT NULL AND os_platform IS NULL';
    EXECUTE 'ALTER TABLE generation_telemetry DROP COLUMN macos_version';
  END IF;
END $$;

-- Backfill: existing rows without os_platform were generated on macOS
UPDATE generation_telemetry
  SET os_platform = 'macos'
  WHERE os_platform IS NULL;
