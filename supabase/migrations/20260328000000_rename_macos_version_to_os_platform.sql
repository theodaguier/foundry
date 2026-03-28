-- Migration: rename macos_version to os_platform in generation_telemetry
-- Foundry is now cross-platform (macOS, Windows, Linux)
-- Created: 2026-03-28

ALTER TABLE generation_telemetry
  RENAME COLUMN macos_version TO os_platform;

-- Update existing rows: assume existing data is macOS
UPDATE generation_telemetry
  SET os_platform = 'macos'
  WHERE os_platform IS NOT NULL;
