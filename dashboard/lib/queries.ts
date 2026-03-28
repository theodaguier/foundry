import { supabase, TelemetryRow, Profile, WaitlistEntry } from "./supabase"
import { format, subDays, eachDayOfInterval, parseISO, startOfDay } from "date-fns"

// ─── Overview ────────────────────────────────────────────────────────────────

export async function getOverviewStats() {
  const [gens, profiles, waitlist] = await Promise.all([
    supabase().from("generation_telemetry").select("outcome, estimated_cost_usd, build_attempts"),
    supabase().from("profiles").select("id", { count: "exact", head: true }),
    supabase().from("waitlist").select("id", { count: "exact", head: true }).maybeSingle(),
  ])

  const rows = (gens.data ?? []) as Pick<TelemetryRow, "outcome" | "estimated_cost_usd" | "build_attempts">[]
  const total = rows.length
  const successes = rows.filter((r) => r.outcome === "success").length
  const totalCost = rows.reduce((s, r) => s + (r.estimated_cost_usd ?? 0), 0)
  const avgAttempts =
    total > 0 ? rows.reduce((s, r) => s + (r.build_attempts ?? 0), 0) / total : 0

  return {
    totalGenerations: total,
    successRate: total > 0 ? (successes / total) * 100 : 0,
    totalCost,
    avgAttempts,
    totalUsers: profiles.count ?? 0,
    waitlistCount: waitlist?.count ?? null,
  }
}

// ─── Timeline (last N days) ───────────────────────────────────────────────────

export async function getGenerationsTimeline(days = 30) {
  const from = subDays(new Date(), days)
  const { data } = await supabase()
    .from("generation_telemetry")
    .select("started_at, outcome")
    .gte("started_at", from.toISOString())
    .order("started_at")

  const rows = (data ?? []) as Pick<TelemetryRow, "started_at" | "outcome">[]

  const interval = eachDayOfInterval({ start: from, end: new Date() })
  const map: Record<string, { date: string; total: number; success: number; failed: number }> = {}
  for (const d of interval) {
    const key = format(d, "MM/dd")
    map[key] = { date: key, total: 0, success: 0, failed: 0 }
  }

  for (const r of rows) {
    if (!r.started_at) continue
    const key = format(parseISO(r.started_at), "MM/dd")
    if (!map[key]) continue
    map[key].total++
    if (r.outcome === "success") map[key].success++
    else map[key].failed++
  }

  return Object.values(map)
}

// ─── Stage durations ──────────────────────────────────────────────────────────

export async function getStageDurations() {
  const { data } = await supabase()
    .from("generation_telemetry")
    .select("generation_duration, build_duration, install_duration, outcome")
    .eq("outcome", "success")

  const rows = (data ?? []) as Pick<
    TelemetryRow,
    "generation_duration" | "build_duration" | "install_duration" | "outcome"
  >[]

  const n = rows.length
  if (n === 0) return []

  const avg = (key: keyof typeof rows[0]) =>
    Math.round(rows.reduce((s, r) => s + ((r[key] as number) ?? 0), 0) / n)

  return [
    { stage: "Generation", avgSeconds: avg("generation_duration") },
    { stage: "Build", avgSeconds: avg("build_duration") },
    { stage: "Install", avgSeconds: avg("install_duration") },
  ]
}

// ─── Build attempts distribution ─────────────────────────────────────────────

export async function getBuildAttemptsDistribution() {
  const { data } = await supabase()
    .from("generation_telemetry")
    .select("build_attempts, outcome")

  const rows = (data ?? []) as Pick<TelemetryRow, "build_attempts" | "outcome">[]
  const counts: Record<number, { success: number; failed: number }> = {}

  for (const r of rows) {
    const n = r.build_attempts ?? 0
    if (!counts[n]) counts[n] = { success: 0, failed: 0 }
    if (r.outcome === "success") counts[n].success++
    else counts[n].failed++
  }

  return Object.entries(counts)
    .map(([k, v]) => ({ attempts: Number(k), ...v, total: v.success + v.failed }))
    .sort((a, b) => a.attempts - b.attempts)
}

// ─── Failure breakdown ────────────────────────────────────────────────────────

export async function getFailureBreakdown() {
  const { data } = await supabase()
    .from("generation_telemetry")
    .select("failure_stage")
    .eq("outcome", "failed")

  const rows = (data ?? []) as Pick<TelemetryRow, "failure_stage">[]
  const counts: Record<string, number> = {}
  for (const r of rows) {
    const s = r.failure_stage ?? "unknown"
    counts[s] = (counts[s] ?? 0) + 1
  }

  return Object.entries(counts)
    .map(([name, value]) => ({ name, value }))
    .sort((a, b) => b.value - a.value)
}

// ─── Success rate by model ────────────────────────────────────────────────────

export async function getSuccessRateByModel() {
  const { data } = await supabase()
    .from("generation_telemetry")
    .select("model, outcome")

  const rows = (data ?? []) as Pick<TelemetryRow, "model" | "outcome">[]
  const map: Record<string, { success: number; total: number }> = {}

  for (const r of rows) {
    const m = r.model ?? "unknown"
    if (!map[m]) map[m] = { success: 0, total: 0 }
    map[m].total++
    if (r.outcome === "success") map[m].success++
  }

  return Object.entries(map)
    .map(([model, v]) => ({
      model: model.split("-").slice(-2).join("-"), // shorten model name
      successRate: Math.round((v.success / v.total) * 100),
      total: v.total,
    }))
    .sort((a, b) => b.total - a.total)
}

// ─── Token & cost over time ───────────────────────────────────────────────────

export async function getTokenCostTimeline(days = 30) {
  const from = subDays(new Date(), days)
  const { data } = await supabase()
    .from("generation_telemetry")
    .select("started_at, input_tokens, output_tokens, cache_read_tokens, estimated_cost_usd")
    .gte("started_at", from.toISOString())
    .order("started_at")

  const rows = (data ?? []) as Pick<
    TelemetryRow,
    "started_at" | "input_tokens" | "output_tokens" | "cache_read_tokens" | "estimated_cost_usd"
  >[]

  const interval = eachDayOfInterval({ start: from, end: new Date() })
  const map: Record<
    string,
    { date: string; inputTokens: number; outputTokens: number; cacheTokens: number; cost: number }
  > = {}
  for (const d of interval) {
    const key = format(d, "MM/dd")
    map[key] = { date: key, inputTokens: 0, outputTokens: 0, cacheTokens: 0, cost: 0 }
  }

  for (const r of rows) {
    if (!r.started_at) continue
    const key = format(parseISO(r.started_at), "MM/dd")
    if (!map[key]) continue
    map[key].inputTokens += r.input_tokens ?? 0
    map[key].outputTokens += r.output_tokens ?? 0
    map[key].cacheTokens += r.cache_read_tokens ?? 0
    map[key].cost += r.estimated_cost_usd ?? 0
  }

  return Object.values(map)
}

// ─── Recent generations table ─────────────────────────────────────────────────

export async function getRecentGenerations(limit = 50, filters?: {
  outcome?: string
  agent?: string
  model?: string
  plugin_type?: string
}) {
  let q = supabase()
    .from("generation_telemetry")
    .select(
      "id, started_at, generation_type, agent, model, plugin_type, original_prompt, outcome, failure_stage, build_attempts, total_duration, generation_duration, build_duration, input_tokens, output_tokens, cache_read_tokens, estimated_cost_usd, user_id, user_rating, os_platform, os_version"
    )
    .order("started_at", { ascending: false })
    .limit(limit)

  if (filters?.outcome) q = q.eq("outcome", filters.outcome)
  if (filters?.agent) q = q.eq("agent", filters.agent)
  if (filters?.model) q = q.eq("model", filters.model)
  if (filters?.plugin_type) q = q.eq("plugin_type", filters.plugin_type)

  const { data } = await q
  return (data ?? []) as TelemetryRow[]
}

// ─── Single telemetry row ─────────────────────────────────────────────────────

export async function getTelemetryById(id: string): Promise<TelemetryRow | null> {
  const { data } = await supabase()
    .from("generation_telemetry")
    .select("*")
    .eq("id", id)
    .single()
  return data as TelemetryRow | null
}

// ─── Users ────────────────────────────────────────────────────────────────────

export async function getUsers() {
  const [profiles, genCounts] = await Promise.all([
    supabase().from("profiles").select("*").order("id"),
    supabase()
      .from("generation_telemetry")
      .select("user_id, outcome")
      .not("user_id", "is", null),
  ])

  const rows = (genCounts.data ?? []) as Pick<TelemetryRow, "user_id" | "outcome">[]
  const countMap: Record<string, { total: number; success: number }> = {}
  for (const r of rows) {
    const uid = r.user_id!
    if (!countMap[uid]) countMap[uid] = { total: 0, success: 0 }
    countMap[uid].total++
    if (r.outcome === "success") countMap[uid].success++
  }

  return ((profiles.data ?? []) as Profile[]).map((p) => ({
    ...p,
    generations: countMap[p.id]?.total ?? 0,
    successGenerations: countMap[p.id]?.success ?? 0,
  }))
}

// ─── Waitlist ─────────────────────────────────────────────────────────────────

export async function getWaitlist(): Promise<WaitlistEntry[] | null> {
  const { data, error } = await supabase()
    .from("waitlist")
    .select("*")
    .order("created_at", { ascending: false })

  if (error) return null
  return data as WaitlistEntry[]
}

// ─── Correlations (build_attempts vs total_duration) ─────────────────────────

export async function getAttemptsVsDuration() {
  const { data } = await supabase()
    .from("generation_telemetry")
    .select("build_attempts, total_duration, outcome")
    .eq("outcome", "success")
    .not("total_duration", "is", null)
    .limit(200)

  return ((data ?? []) as Pick<TelemetryRow, "build_attempts" | "total_duration" | "outcome">[]).map(
    (r) => ({
      attempts: r.build_attempts ?? 0,
      duration: Math.round((r.total_duration ?? 0) / 1000),
    })
  )
}

// ─── Filter options ───────────────────────────────────────────────────────────

export async function getFilterOptions() {
  const { data } = await supabase()
    .from("generation_telemetry")
    .select("agent, model, plugin_type")

  const rows = (data ?? []) as Pick<TelemetryRow, "agent" | "model" | "plugin_type">[]
  const agents = [...new Set(rows.map((r) => r.agent).filter(Boolean))] as string[]
  const models = [...new Set(rows.map((r) => r.model).filter(Boolean))] as string[]
  const types = [...new Set(rows.map((r) => r.plugin_type).filter(Boolean))] as string[]

  return { agents, models, types }
}
