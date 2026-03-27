"use client"

import { ComposedChart, Bar, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from "recharts"

interface Props {
  data: { date: string; inputTokens: number; outputTokens: number; cacheTokens: number; cost: number }[]
}

const tip = { background: "var(--popover)", border: "1px solid var(--border)", borderRadius: 6, fontSize: 12, color: "var(--popover-foreground)" }

export function TokenCostChart({ data }: Props) {
  return (
    <ResponsiveContainer width="100%" height={220}>
      <ComposedChart data={data} margin={{ top: 4, right: 20, bottom: 0, left: -10 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
        <XAxis dataKey="date" tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} tickLine={false} axisLine={false} interval={4} />
        <YAxis yAxisId="tokens" tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} tickLine={false} axisLine={false} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
        <YAxis yAxisId="cost" orientation="right" tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} tickLine={false} axisLine={false} tickFormatter={(v) => `$${v.toFixed(2)}`} />
        <Tooltip contentStyle={tip} cursor={{ fill: "var(--muted)" }} />
        <Legend wrapperStyle={{ fontSize: 11, paddingTop: 8 }} iconType="circle" iconSize={7} />
        <Bar yAxisId="tokens" dataKey="inputTokens" fill="var(--chart-1)" opacity={0.8} stackId="t" name="Input" />
        <Bar yAxisId="tokens" dataKey="outputTokens" fill="var(--chart-2)" opacity={0.8} stackId="t" name="Output" />
        <Bar yAxisId="tokens" dataKey="cacheTokens" fill="var(--chart-3)" opacity={0.8} stackId="t" name="Cache" />
        <Line yAxisId="cost" type="monotone" dataKey="cost" stroke="var(--warning)" strokeWidth={1.5} dot={false} name="Cost ($)" />
      </ComposedChart>
    </ResponsiveContainer>
  )
}
