import { createClient } from "@supabase/supabase-js"
import { getRequestContext } from "@cloudflare/next-on-pages"

function getEnv() {
  try {
    // Runtime: Cloudflare Pages env bindings
    const ctx = getRequestContext()
    return ctx.env as Record<string, string>
  } catch {
    // Build time or local dev: fall back to process.env
    return process.env as Record<string, string>
  }
}

export function getSupabase() {
  const env = getEnv()
  const url = env.SUPABASE_URL
  const key = env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) throw new Error(`supabaseUrl is required. SUPABASE_URL=${url}`)
  return createClient(url, key, { auth: { persistSession: false } })
}

// Legacy export for code that imports supabase directly
export const supabase = {
  from: (...args: Parameters<ReturnType<typeof getSupabase>["from"]>) => getSupabase().from(...args),
}

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
