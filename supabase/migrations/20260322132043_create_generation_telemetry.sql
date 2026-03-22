-- Generation telemetry table
create table public.generation_telemetry (
  id uuid primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  plugin_id uuid,
  version_number int,

  -- Agent
  agent text not null,
  model text not null,

  -- Prompt
  original_prompt text not null,
  enhanced_prompt text,
  system_prompt_version text,

  -- Timing (seconds)
  started_at timestamptz not null default now(),
  enhancer_duration double precision,
  generation_duration double precision not null default 0,
  audit_duration double precision,
  build_duration double precision not null default 0,
  install_duration double precision,
  total_duration double precision not null default 0,

  -- Tokens
  input_tokens int,
  output_tokens int,
  cache_read_tokens int,
  cache_write_tokens int,
  total_tokens int,

  -- Cost
  estimated_cost_usd double precision,

  -- Build
  build_attempts int not null default 1,
  build_logs jsonb not null default '[]',

  -- Outcome
  outcome text not null,
  failure_stage text,
  failure_message text,
  failure_details text,

  -- Plugin config
  plugin_type text not null,
  format text not null,
  channel_layout text not null default 'Stereo',
  preset_count int not null default 5,
  interface_style text,

  -- Environment
  macos_version text,
  cpu_architecture text,
  xcode_version text,
  juce_version text,
  agent_cli_version text,

  created_at timestamptz not null default now()
);

-- RLS: users can only access their own telemetry
alter table public.generation_telemetry enable row level security;

create policy "Users can insert their own telemetry"
  on public.generation_telemetry for insert
  with check (auth.uid() = user_id);

create policy "Users can read their own telemetry"
  on public.generation_telemetry for select
  using (auth.uid() = user_id);

-- Indexes
create index idx_telemetry_user_id on public.generation_telemetry(user_id);
create index idx_telemetry_plugin_id on public.generation_telemetry(plugin_id);
create index idx_telemetry_started_at on public.generation_telemetry(started_at desc);
