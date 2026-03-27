"use client"

import { ScatterChart, Scatter, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from "recharts"

interface Props { data: { attempts: number; duration: number }[] }

const tip = { background: "var(--popover)", border: "1px solid var(--border)", borderRadius: 6, fontSize: 12, color: "var(--popover-foreground)" }

export function AttemptsScatterChart({ data }: Props) {
  return (
    <ResponsiveContainer width="100%" height={220}>
      <ScatterChart margin={{ top: 4, right: 4, bottom: 20, left: -10 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
        <XAxis dataKey="attempts" type="number" name="Build attempts" tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} tickLine={false} axisLine={false} label={{ value: "Build attempts", position: "insideBottom", offset: -8, fontSize: 11, fill: "var(--muted-foreground)" }} />
        <YAxis dataKey="duration" type="number" name="Duration (s)" tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} tickLine={false} axisLine={false} tickFormatter={(v) => `${v}s`} />
        <Tooltip contentStyle={tip} cursor={{ strokeDasharray: "3 3" }} formatter={(v, name) => [name === "Duration (s)" ? `${v}s` : v, name]} />
        <Scatter data={data} fill="var(--primary)" opacity={0.5} />
      </ScatterChart>
    </ResponsiveContainer>
  )
}
