import type { APIRoute } from "astro"
import { createClient } from "@supabase/supabase-js"

const supabase = createClient(
  import.meta.env.SUPABASE_URL,
  import.meta.env.SUPABASE_SERVICE_ROLE_KEY
)

export const prerender = false

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json()

    const {
      email,
      platform,
      ram_gb,
      storage_gb,
      daw,
      profile,
      use_case,
      source,
    } = body

    if (!email || !email.includes("@")) {
      return new Response(JSON.stringify({ error: "Invalid email" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      })
    }

    const { error } = await supabase.from("waitlist").upsert(
      {
        email: email.trim().toLowerCase(),
        platform: platform ?? null,
        ram_gb: ram_gb ? Number(ram_gb) : null,
        storage_gb: storage_gb ? Number(storage_gb) : null,
        daw: daw ?? null,
        profile: profile ?? null,
        use_case: use_case ?? null,
        source: source ?? null,
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

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: "Bad request" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    })
  }
}
