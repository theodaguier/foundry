create table if not exists plugin_feedback (
  id uuid default gen_random_uuid() primary key,
  plugin_id text not null,
  user_id uuid references auth.users(id) not null,
  speed smallint not null check (speed between 1 and 5),
  quality smallint not null check (quality between 1 and 5),
  design smallint not null check (design between 1 and 5),
  created_at timestamptz default now(),
  unique (plugin_id, user_id)
);

alter table plugin_feedback enable row level security;

create policy "Users can insert their own feedback"
  on plugin_feedback for insert with check (auth.uid() = user_id);

create policy "Users can update their own feedback"
  on plugin_feedback for update using (auth.uid() = user_id);

create policy "Users can read their own feedback"
  on plugin_feedback for select using (auth.uid() = user_id);
