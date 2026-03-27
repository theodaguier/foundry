import { NextRequest, NextResponse } from "next/server"

const AUTH_TOKEN = "foundry_authenticated"

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl
  if (pathname.startsWith("/login") || pathname.startsWith("/api/")) return NextResponse.next()

  const cookie = req.cookies.get("foundry_dash_auth")
  if (cookie) return NextResponse.next()

  const url = req.nextUrl.clone()
  url.pathname = "/login"
  url.searchParams.set("from", pathname)
  return NextResponse.redirect(url)
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
}
