import { NextRequest, NextResponse } from "next/server"
import { getRequestContext } from "@cloudflare/next-on-pages"

function getPassword() {
  try {
    const ctx = getRequestContext()
    return (ctx.env as Record<string, string>).ADMIN_PASSWORD ?? "foundry"
  } catch {
    return process.env.ADMIN_PASSWORD ?? "foundry"
  }
}

export const runtime = "edge"

export async function POST(req: NextRequest) {
  const { password } = await req.json()
  const PASSWORD = getPassword()
  if (password !== PASSWORD) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const res = NextResponse.json({ ok: true })
  res.cookies.set("foundry_dash_auth", PASSWORD, {
    httpOnly: true,
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 30,
  })
  return res
}
