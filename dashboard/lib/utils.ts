import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function fmt(ms: number | null | undefined): string {
  if (ms == null) return "—"
  const s = Math.round(ms / 1000)
  if (s < 60) return `${s}s`
  return `${Math.floor(s / 60)}m ${s % 60}s`
}

export function fmtCost(usd: number | null | undefined): string {
  if (usd == null) return "—"
  return `$${usd.toFixed(3)}`
}

export function fmtTokens(n: number | null | undefined): string {
  if (n == null) return "—"
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(0)}k`
  return String(n)
}

export function shortModel(model: string | null | undefined): string {
  if (!model) return "—"
  const parts = model.split("-")
  return parts.slice(-2).join("-")
}
