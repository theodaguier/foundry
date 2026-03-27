import { getRecentGenerations, getFilterOptions } from "@/lib/queries"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { fmt, fmtCost, fmtTokens, shortModel } from "@/lib/utils"
import { format, parseISO } from "date-fns"
import { GenerationsFilters } from "./filters"

export const runtime = 'edge'
export const revalidate = 30

function OutcomeTag({ outcome }: { outcome: string | null }) {
  const color = outcome === "success"
    ? "text-[oklch(0.72_0.18_142)]"
    : outcome === "failed"
    ? "text-[oklch(0.65_0.2_22)]"
    : "text-muted-foreground"
  return <span className={`text-[11px] ${color}`}>{outcome ?? "—"}</span>
}

export default async function GenerationsPage({
  searchParams,
}: {
  searchParams: Promise<{ outcome?: string; agent?: string; model?: string; plugin_type?: string }>
}) {
  const sp = await searchParams
  const [rows, filters] = await Promise.all([
    getRecentGenerations(100, {
      outcome: sp.outcome,
      agent: sp.agent,
      model: sp.model,
      plugin_type: sp.plugin_type,
    }),
    getFilterOptions(),
  ])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-base font-normal tracking-wide">Generations</h1>
        <p className="text-xs text-muted-foreground mt-0.5">{rows.length} rows</p>
      </div>

      <GenerationsFilters filters={filters} current={sp} />

      <Card>
        <CardHeader>
          <CardTitle>All generations</CardTitle>
        </CardHeader>
        <CardContent className="p-0 overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Time</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Plugin type</TableHead>
                <TableHead>Prompt</TableHead>
                <TableHead>Agent / Model</TableHead>
                <TableHead>Attempts</TableHead>
                <TableHead>Gen</TableHead>
                <TableHead>Build</TableHead>
                <TableHead>Total</TableHead>
                <TableHead>In</TableHead>
                <TableHead>Out</TableHead>
                <TableHead>Cost</TableHead>
                <TableHead>Outcome</TableHead>
                <TableHead>Fail stage</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.length === 0 && (
                <TableRow>
                  <TableCell colSpan={14} className="text-center text-muted-foreground py-8">No results</TableCell>
                </TableRow>
              )}
              {rows.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="text-muted-foreground whitespace-nowrap text-[11px]">
                    {r.started_at ? format(parseISO(r.started_at), "MM/dd HH:mm") : "—"}
                  </TableCell>
                  <TableCell className="text-muted-foreground">{r.generation_type ?? "—"}</TableCell>
                  <TableCell className="text-muted-foreground">{r.plugin_type ?? "—"}</TableCell>
                  <TableCell className="max-w-[160px] truncate text-[11px]" title={r.original_prompt ?? ""}>
                    {r.original_prompt ?? "—"}
                  </TableCell>
                  <TableCell className="text-muted-foreground whitespace-nowrap text-[11px]">
                    {r.agent ?? "—"} / {shortModel(r.model)}
                  </TableCell>
                  <TableCell>{r.build_attempts ?? "—"}</TableCell>
                  <TableCell className="whitespace-nowrap text-[11px]">{fmt(r.generation_duration)}</TableCell>
                  <TableCell className="whitespace-nowrap text-[11px]">{fmt(r.build_duration)}</TableCell>
                  <TableCell className="whitespace-nowrap text-[11px] font-medium">{fmt(r.total_duration)}</TableCell>
                  <TableCell className="text-[11px]">{fmtTokens(r.input_tokens)}</TableCell>
                  <TableCell className="text-[11px]">{fmtTokens(r.output_tokens)}</TableCell>
                  <TableCell className="whitespace-nowrap text-[11px]">{fmtCost(r.estimated_cost_usd)}</TableCell>
                  <TableCell><OutcomeTag outcome={r.outcome} /></TableCell>
                  <TableCell className="text-[11px] text-muted-foreground">{r.failure_stage ?? "—"}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
