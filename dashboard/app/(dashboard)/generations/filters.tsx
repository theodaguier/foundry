"use client"

import { useRouter, usePathname } from "next/navigation"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"

interface Props {
  filters: { agents: string[]; models: string[]; types: string[] }
  current: { outcome?: string | null; agent?: string | null; model?: string | null; plugin_type?: string | null }
}

export function GenerationsFilters({ filters, current }: Props) {
  const router = useRouter()
  const pathname = usePathname()

  function update(key: string, value: string) {
    const p = new URLSearchParams()
    const prev: Record<string, string | null | undefined> = {
      outcome: current.outcome,
      agent: current.agent,
      model: current.model,
      plugin_type: current.plugin_type,
    }
    for (const [k, v] of Object.entries(prev)) {
      if (v) p.set(k, v)
    }
    if (value && value !== "all") p.set(key, value)
    else p.delete(key)
    router.push(`${pathname}?${p.toString()}`)
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const v = (val: any): string => val ?? "all"

  return (
    <div className="flex flex-wrap gap-2 overflow-x-auto pb-1">
      <Select value={v(current.outcome)} onValueChange={(x) => update("outcome", x ?? "all")}>
        <SelectTrigger className="w-32 h-7 text-xs">
          <SelectValue placeholder="Outcome" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All outcomes</SelectItem>
          <SelectItem value="success">Success</SelectItem>
          <SelectItem value="failed">Failed</SelectItem>
          <SelectItem value="cancelled">Cancelled</SelectItem>
        </SelectContent>
      </Select>

      <Select value={v(current.agent)} onValueChange={(x) => update("agent", x ?? "all")}>
        <SelectTrigger className="w-36 h-7 text-xs">
          <SelectValue placeholder="Agent" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All agents</SelectItem>
          {filters.agents.map((a) => <SelectItem key={a} value={a}>{a}</SelectItem>)}
        </SelectContent>
      </Select>

      <Select value={v(current.model)} onValueChange={(x) => update("model", x ?? "all")}>
        <SelectTrigger className="w-44 h-7 text-xs">
          <SelectValue placeholder="Model" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All models</SelectItem>
          {filters.models.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
        </SelectContent>
      </Select>

      <Select value={v(current.plugin_type)} onValueChange={(x) => update("plugin_type", x ?? "all")}>
        <SelectTrigger className="w-36 h-7 text-xs">
          <SelectValue placeholder="Type" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All types</SelectItem>
          {filters.types.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
        </SelectContent>
      </Select>
    </div>
  )
}
