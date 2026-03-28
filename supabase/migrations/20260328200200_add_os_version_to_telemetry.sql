-- Add os_version column to generation_telemetry if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'generation_telemetry' AND column_name = 'os_version'
  ) THEN
    ALTER TABLE generation_telemetry ADD COLUMN os_version text;
  END IF;
END $$;
