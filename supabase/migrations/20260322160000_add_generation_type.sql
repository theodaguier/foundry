-- Add generation_type column to differentiate generate, refine, and preset flows
alter table public.generation_telemetry
  add column generation_type text not null default 'generate';

-- Index for filtering by type
create index idx_telemetry_generation_type on public.generation_telemetry(generation_type);
