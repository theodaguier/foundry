import type { Plugin, PluginType } from "@/lib/types"
import { cn } from "@/lib/utils"
import { Piano, Waves, Gauge } from "lucide-react"

interface Props {
  plugin: Plugin
  size?: "full" | "compact"
  className?: string
}

function TypeIcon({ type, size }: { type: PluginType; size: number }) {
  const props = { className: "shrink-0", size, strokeWidth: 1.5 }
  switch (type) {
    case "instrument": return <Piano {...props} />
    case "effect": return <Waves {...props} />
    case "utility": return <Gauge {...props} />
  }
}

export function PluginArtworkView({ plugin, size = "full", className }: Props) {
  if (size === "compact") {
    return (
      <div
        className={cn(
          "rounded-lg flex items-center justify-center bg-foreground/[0.06] text-foreground/50",
          className,
        )}
        style={{ width: 28, height: 28 }}
      >
        <TypeIcon type={plugin.type} size={13} />
      </div>
    )
  }

  return (
    <div className={cn("relative w-full h-full", className)}>
      <div className="absolute inset-0 bg-muted" />
      <div className="absolute inset-0 bg-gradient-to-br from-foreground/[0.04] via-foreground/[0.02] to-transparent" />
      <div className="absolute inset-0 flex items-center justify-center text-foreground/40">
        <TypeIcon type={plugin.type} size={36} />
      </div>
    </div>
  )
}
