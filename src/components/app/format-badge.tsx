import type { PluginFormat } from "@/lib/types"

interface Props {
  formats: PluginFormat[]
  style?: "accent" | "muted"
}

export function FormatBadge({ formats, style = "accent" }: Props) {
  const label = formats.join(" · ")

  if (style === "muted") {
    return (
      <span className="text-[10px] font-bold font-mono text-muted-foreground/60 px-2.5 py-1 bg-secondary rounded-full">
        {label}
      </span>
    )
  }

  return (
    <span className="text-[10px] font-bold font-mono text-primary px-2.5 py-1 bg-primary/12 rounded-full">
      {label}
    </span>
  )
}
