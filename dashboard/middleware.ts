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

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl
  if (pathname.startsWith("/login") || pathname.startsWith("/api/")) return NextResponse.next()

  const PASSWORD = getPassword()
  const cookie = req.cookies.get("foundry_dash_auth")
  if (cookie?.value === PASSWORD) return NextResponse.next()

  const url = req.nextUrl.clone()
  url.pathname = "/login"
  url.searchParams.set("from", pathname)
  return NextResponse.redirect(url)
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
}
