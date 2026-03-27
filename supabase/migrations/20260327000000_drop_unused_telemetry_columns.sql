-- Migration: drop unused columns from generation_telemetry
-- These columns are never populated in the codebase and correspond
-- to unimplemented features (audit pass, prompt enhancer).
-- Created: 2026-03-27

ALTER TABLE generation_telemetry
  DROP COLUMN IF EXISTS audit_duration,
  DROP COLUMN IF EXISTS enhanced_prompt,
  DROP COLUMN IF EXISTS failure_details;
