import { NextResponse } from "next/server"

export async function GET(req: Request) {
  const url = new URL(req.url)
  const res = NextResponse.redirect(new URL("/login", url.origin))
  res.cookies.delete("foundry_dash_auth")
  return res
}
