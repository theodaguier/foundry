-- Change plugin_id from text to uuid for consistency
alter table plugin_feedback
  alter column plugin_id type uuid using plugin_id::uuid;
