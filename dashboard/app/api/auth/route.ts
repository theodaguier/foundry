export const runtime = 'edge'

import { NextRequest, NextResponse } from "next/server"

const AUTH_TOKEN = "foundry_authenticated"

export async function POST(req: NextRequest) {
  const PASSWORD = process.env.ADMIN_PASSWORD ?? "foundry"
  const { password } = await req.json()
  if (password !== PASSWORD) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const res = NextResponse.json({ ok: true })
  res.cookies.set("foundry_dash_auth", AUTH_TOKEN, {
    httpOnly: true,
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 30,
  })
  return res
}
