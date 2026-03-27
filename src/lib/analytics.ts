import posthog from "posthog-js"

const POSTHOG_KEY = import.meta.env.VITE_PUBLIC_POSTHOG_PROJECT_TOKEN as string | undefined
const POSTHOG_HOST = (import.meta.env.VITE_PUBLIC_POSTHOG_HOST as string | undefined) ?? "https://e.byfoundry.app"

let initialized = false

export function initAnalytics() {
  if (!POSTHOG_KEY || initialized) return
  posthog.init(POSTHOG_KEY, {
    api_host: POSTHOG_HOST,
    ui_host: "https://eu.posthog.com",
    person_profiles: "identified_only",
    capture_pageview: false,
    capture_pageleave: false,
    autocapture: false,
  })
  initialized = true
}

export function identifyUser(userId: string, props?: Record<string, unknown>) {
  if (!initialized) return
  posthog.identify(userId, props)
}

export function resetUser() {
  if (!initialized) return
  posthog.reset()
}

export function track(event: string, props?: Record<string, unknown>) {
  if (!initialized) return
  posthog.capture(event, props)
}

// ── Typed event helpers ──────────────────────────────────────────────────────

export function trackAppOpened() {
  track("app_opened")
}

export function trackGenerationStarted(props: {
  pluginType: string
  agent: string
  model: string
  format: string
}) {
  track("plugin_generation_started", props)
}

export function trackGenerationCompleted(props: {
  pluginType: string
  agent: string
  model: string
  outcome: "success" | "failed" | "cancelled"
  durationSeconds?: number
  estimatedCostUsd?: number
  buildAttempts?: number
}) {
  track("plugin_generation_completed", props)
}

export function trackGenerationRated(props: {
  rating: 1 | -1
  telemetryId: string
}) {
  track("plugin_generation_rated", props)
}

export function trackPluginDeleted() {
  track("plugin_deleted")
}

export function trackRefineStarted(props: { agent: string; model: string }) {
  track("plugin_refine_started", props)
}
