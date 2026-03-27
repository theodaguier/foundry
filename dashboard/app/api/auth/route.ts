import { NextRequest, NextResponse } from "next/server"

const PASSWORD = process.env.ADMIN_PASSWORD ?? "foundry"

export async function POST(req: NextRequest) {
  const { password } = await req.json()
  if (password !== PASSWORD) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const res = NextResponse.json({ ok: true })
  res.cookies.set("foundry_dash_auth", PASSWORD, {
    httpOnly: true,
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 30, // 30 days
  })
  return res
}
