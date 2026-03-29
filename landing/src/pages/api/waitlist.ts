import type { APIRoute } from "astro"
import { createClient } from "@supabase/supabase-js"
import { z } from "zod"

const supabase = createClient(
  import.meta.env.SUPABASE_URL,
  import.meta.env.SUPABASE_SERVICE_ROLE_KEY
)

const RESEND_KEY = import.meta.env.RESEND_API_KEY

export const prerender = false

const waitlistSchema = z.object({
  email: z.string().email("Invalid email address"),
  name: z.string().min(1, "Name is required").max(200),
  platform: z.enum(["macos", "windows", "both"]),
  ram_gb: z.number().optional(),
  storage_gb: z.number().optional(),
  daw: z.enum(["ableton", "logic", "fl", "bitwig", "other"]).optional(),
  profile: z.enum(["producer", "developer", "both"]).optional(),
  use_case: z.string().max(2000).optional(),
  source: z.enum(["twitter", "reddit", "friend", "other"]).optional(),
  music_genre: z.string().max(200).optional(),
  ai_subscription: z.enum(["claude", "chatgpt", "both", "none"]).optional(),
  prior_attempt: z.enum(["yes", "no"]).optional(),
  prior_attempt_detail: z.string().max(1000).optional(),
})

async function sendWaitlistEmail(email: string, name?: string, platform?: string) {
  if (!RESEND_KEY) return
  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "Foundry <hello@byfoundry.app>",
      to: [email],
      subject: "You're on the Foundry waitlist",
      template: "beta-waitlist-1",
      variables: {
        NAME: (name ?? email.trim().split("@")[0]).trim(),
        PLATFORM: (platform ?? "unknown").toUpperCase(),
      },
    }),
  })
}

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json()
    const result = waitlistSchema.safeParse(body)

    if (!result.success) {
      const errors = result.error.flatten().fieldErrors
      return new Response(JSON.stringify({ error: "Validation failed", fields: errors }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      })
    }

    const data = result.data

    const { error } = await supabase.from("waitlist").upsert(
      {
        email: data.email.trim().toLowerCase(),
        platform: data.platform,
        ram_gb: data.ram_gb ?? null,
        storage_gb: data.storage_gb ?? null,
        daw: data.daw ?? null,
        profile: data.profile ?? null,
        use_case: data.use_case ?? null,
        source: data.source ?? null,
        ai_subscription: data.ai_subscription ?? null,
        music_genre: data.music_genre ?? null,
        prior_attempt: data.prior_attempt ?? null,
        prior_attempt_detail: data.prior_attempt_detail ?? null,
        status: "pending",
      },
      { onConflict: "email", ignoreDuplicates: false }
    )

    if (error) {
      console.error("[waitlist]", error)
      return new Response(JSON.stringify({ error: "Failed to save" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      })
    }

    // Fire-and-forget confirmation email
    sendWaitlistEmail(data.email.trim().toLowerCase(), data.name, data.platform).catch(console.error)

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    })
  } catch {
    return new Response(JSON.stringify({ error: "Bad request" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    })
  }
}
