import { getOverviewStats, getGenerationsTimeline, getRecentGenerations } from "@/lib/queries"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { TimelineChart } from "@/components/charts/timeline-chart"
import { fmt, fmtCost, shortModel } from "@/lib/utils"
import { format, parseISO } from "date-fns"

export const revalidate = 60

function OutcomeTag({ outcome }: { outcome: string | null }) {
  const color = outcome === "success"
    ? "text-[oklch(0.72_0.18_142)]"
    : outcome === "failed"
    ? "text-[oklch(0.65_0.2_22)]"
    : "text-muted-foreground"
  return <span className={`text-[11px] ${color}`}>{outcome ?? "—"}</span>
}

export default async function OverviewPage() {
  const [stats, timeline, recent] = await Promise.all([
    getOverviewStats(),
    getGenerationsTimeline(30),
    getRecentGenerations(10),
  ])

  const kpis = [
    { label: "Generations", value: stats.totalGenerations, sub: "all time" },
    { label: "Success rate", value: `${stats.successRate.toFixed(1)}%`, sub: stats.totalGenerations > 0 ? `${Math.round(stats.successRate * stats.totalGenerations / 100)} succeeded` : undefined },
    { label: "Total cost", value: `$${stats.totalCost.toFixed(2)}`, sub: `~${fmtCost(stats.totalCost / Math.max(stats.totalGenerations, 1))} avg` },
    { label: "Avg attempts", value: stats.avgAttempts.toFixed(1), sub: "per generation" },
    { label: "Users", value: stats.totalUsers, sub: "registered" },
    { label: "Waitlist", value: stats.waitlistCount === null ? "N/A" : stats.waitlistCount, sub: stats.waitlistCount === null ? "no table found" : "signups" },
  ]

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-base font-normal tracking-wide">Overview</h1>
        <p className="text-xs text-muted-foreground mt-0.5">
          {new Date().toLocaleDateString("en-US", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}
        </p>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        {kpis.map((k) => (
          <Card key={k.label}>
            <CardHeader>
              <CardTitle>{k.label}</CardTitle>
            </CardHeader>
            <CardContent className="px-4 pb-4">
              <p className="text-xl font-medium">{k.value}</p>
              {k.sub && <p className="text-[10px] text-muted-foreground mt-0.5">{k.sub}</p>}
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Timeline */}
      <Card>
        <CardHeader>
          <CardTitle>Generations — last 30 days</CardTitle>
        </CardHeader>
        <CardContent className="p-4">
          <TimelineChart data={timeline} />
        </CardContent>
      </Card>

      {/* Recent */}
      <Card>
        <CardHeader>
          <CardTitle>Recent generations</CardTitle>
        </CardHeader>
        <CardContent className="p-0 overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Time</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Prompt</TableHead>
                <TableHead>Agent / Model</TableHead>
                <TableHead>Attempts</TableHead>
                <TableHead>Duration</TableHead>
                <TableHead>Cost</TableHead>
                <TableHead>Outcome</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {recent.length === 0 && (
                <TableRow>
                  <TableCell colSpan={8} className="text-center text-muted-foreground py-8">No data yet</TableCell>
                </TableRow>
              )}
              {recent.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="text-muted-foreground whitespace-nowrap">
                    {r.started_at ? format(parseISO(r.started_at), "MM/dd HH:mm") : "—"}
                  </TableCell>
                  <TableCell>{r.generation_type ?? "—"}</TableCell>
                  <TableCell className="max-w-[180px] truncate" title={r.original_prompt ?? ""}>
                    {r.original_prompt ?? "—"}
                  </TableCell>
                  <TableCell className="text-muted-foreground whitespace-nowrap">
                    {r.agent ?? "—"} / {shortModel(r.model)}
                  </TableCell>
                  <TableCell>{r.build_attempts ?? "—"}</TableCell>
                  <TableCell className="whitespace-nowrap">{fmt(r.total_duration)}</TableCell>
                  <TableCell className="whitespace-nowrap">{fmtCost(r.estimated_cost_usd)}</TableCell>
                  <TableCell><OutcomeTag outcome={r.outcome} /></TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
