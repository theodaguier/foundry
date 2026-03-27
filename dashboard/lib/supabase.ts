import { createClient, type SupabaseClient } from "@supabase/supabase-js"

let _client: SupabaseClient | null = null

/**
 * Lazily create the Supabase client so env vars are read at request time,
 * not at module-init time (Cloudflare Pages populates process.env at request time).
 */
export function getSupabaseClient(): SupabaseClient {
  if (_client) return _client
  const url = process.env.SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) {
    throw new Error(
      `Missing Supabase env vars: SUPABASE_URL=${url ? "set" : "missing"}, SUPABASE_SERVICE_ROLE_KEY=${key ? "set" : "missing"}`
    )
  }
  _client = createClient(url, key, { auth: { persistSession: false } })
  return _client
}

/** Proxy that lazily initialises the client on first .from() call */
export const supabase = new Proxy({} as SupabaseClient, {
  get(_target, prop, receiver) {
    const client = getSupabaseClient()
    const value = Reflect.get(client, prop, receiver)
    return typeof value === "function" ? value.bind(client) : value
  },
})

export type Json = string | number | boolean | null | { [key: string]: Json } | Json[]

export interface TelemetryRow {
  id: string
  user_id: string | null
  plugin_id: string | null
  version_number: number | null
  generation_type: "generate" | "refine" | null
  agent: string | null
  model: string | null
  original_prompt: string | null
  started_at: string | null
  generation_duration: number | null
  build_duration: number | null
  install_duration: number | null
  total_duration: number | null
  input_tokens: number | null
  output_tokens: number | null
  cache_read_tokens: number | null
  estimated_cost_usd: number | null
  build_attempts: number | null
  build_logs: Json | null
  outcome: "success" | "failed" | "cancelled" | null
  failure_stage: string | null
  failure_message: string | null
  plugin_type: string | null
  format: string | null
  channel_layout: string | null
  macos_version: string | null
  cpu_architecture: string | null
  agent_cli_version: string | null
  juce_version: string | null
  user_rating: number | null
}

export interface Profile {
  id: string
  email: string | null
  onboarding_completed_at: string | null
  card_variant: string | null
}

export interface WaitlistEntry {
  id: string
  email: string
  created_at: string
  status?: string | null
}
