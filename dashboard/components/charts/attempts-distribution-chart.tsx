"use client"

import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from "recharts"

interface Props { data: { attempts: number; success: number; failed: number }[] }

const tip = { background: "var(--popover)", border: "1px solid var(--border)", borderRadius: 6, fontSize: 12, color: "var(--popover-foreground)" }

export function AttemptsDistributionChart({ data }: Props) {
  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={data} margin={{ top: 4, right: 4, bottom: 16, left: -20 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" vertical={false} />
        <XAxis dataKey="attempts" tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} tickLine={false} axisLine={false} label={{ value: "Build attempts", position: "insideBottom", offset: -8, fontSize: 11, fill: "var(--muted-foreground)" }} />
        <YAxis tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} tickLine={false} axisLine={false} />
        <Tooltip contentStyle={tip} cursor={{ fill: "var(--muted)" }} />
        <Legend wrapperStyle={{ fontSize: 11, paddingTop: 8 }} iconType="circle" iconSize={7} />
        <Bar dataKey="success" fill="var(--success)" stackId="s" name="Success" />
        <Bar dataKey="failed" fill="var(--destructive)" stackId="s" radius={[3, 3, 0, 0]} name="Failed" />
      </BarChart>
    </ResponsiveContainer>
  )
}
