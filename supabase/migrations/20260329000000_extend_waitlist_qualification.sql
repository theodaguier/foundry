-- Migration: extend waitlist table with qualification fields
-- Created: 2026-03-29

ALTER TABLE waitlist
  ADD COLUMN IF NOT EXISTS platform TEXT,        -- 'macos' | 'windows' | 'both'
  ADD COLUMN IF NOT EXISTS ram_gb INTEGER,        -- 8, 16, 32, 64
  ADD COLUMN IF NOT EXISTS storage_gb INTEGER,    -- available storage in GB
  ADD COLUMN IF NOT EXISTS daw TEXT,              -- primary DAW
  ADD COLUMN IF NOT EXISTS profile TEXT,          -- 'producer' | 'developer' | 'both'
  ADD COLUMN IF NOT EXISTS use_case TEXT,         -- free text: why they want Foundry
  ADD COLUMN IF NOT EXISTS source TEXT;           -- how they heard about it
