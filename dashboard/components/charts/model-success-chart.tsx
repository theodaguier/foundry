"use client"

import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell } from "recharts"

interface Props { data: { model: string; successRate: number; total: number }[] }

const tip = { background: "var(--popover)", border: "1px solid var(--border)", borderRadius: 6, fontSize: 12, color: "var(--popover-foreground)" }

export function ModelSuccessChart({ data }: Props) {
  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={data} layout="vertical" margin={{ top: 4, right: 30, bottom: 0, left: 10 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" horizontal={false} />
        <XAxis type="number" domain={[0, 100]} tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} tickLine={false} axisLine={false} tickFormatter={(v) => `${v}%`} />
        <YAxis type="category" dataKey="model" tick={{ fontSize: 10, fill: "var(--muted-foreground)" }} tickLine={false} axisLine={false} width={90} />
        <Tooltip contentStyle={tip} cursor={{ fill: "var(--muted)" }} formatter={(v, _, p) => [`${v}% (n=${p.payload.total})`, "Success rate"]} />
        <Bar dataKey="successRate" radius={[0, 3, 3, 0]}>
          {data.map((d, i) => (
            <Cell key={i} fill={d.successRate >= 80 ? "var(--success)" : d.successRate >= 50 ? "var(--warning)" : "var(--destructive)"} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  )
}
