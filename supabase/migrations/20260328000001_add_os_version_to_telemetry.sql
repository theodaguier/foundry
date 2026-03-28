-- Migration: add os_version column to generation_telemetry
-- Stores the OS version string (e.g. "14.4.1", "11", "22.04")
-- Created: 2026-03-28

ALTER TABLE generation_telemetry
  ADD COLUMN IF NOT EXISTS os_version TEXT;
