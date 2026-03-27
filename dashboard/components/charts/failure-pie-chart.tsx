"use client"

import { PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer } from "recharts"

interface Props { data: { name: string; value: number }[] }

const COLORS = ["var(--destructive)", "var(--warning)", "var(--chart-1)", "var(--chart-2)", "var(--chart-3)"]
const tip = { background: "var(--popover)", border: "1px solid var(--border)", borderRadius: 6, fontSize: 12, color: "var(--popover-foreground)" }

export function FailurePieChart({ data }: Props) {
  if (!data.length) return (
    <div className="flex items-center justify-center h-[220px] text-muted-foreground text-xs">No failures recorded</div>
  )
  return (
    <ResponsiveContainer width="100%" height={220}>
      <PieChart>
        <Pie data={data} cx="50%" cy="45%" innerRadius={55} outerRadius={80} dataKey="value" paddingAngle={2}>
          {data.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
        </Pie>
        <Tooltip contentStyle={tip} />
        <Legend wrapperStyle={{ fontSize: 11 }} iconType="circle" iconSize={7} />
      </PieChart>
    </ResponsiveContainer>
  )
}
