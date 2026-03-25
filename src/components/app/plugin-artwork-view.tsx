import type { Plugin, PluginType } from "@/lib/types"
import { Piano, Waves, Gauge } from "lucide-react"

interface Props {
  plugin: Plugin
  size?: "full" | "compact"
  className?: string
}

/**
 * Type-based color system — cohesive, curated.
 * No more random iconColor chaos.
 */
const typeStyles: Record<PluginType, { bg: string; icon: string; gradient: string }> = {
  instrument: {
    bg: "bg-foreground/[0.06]",
    icon: "text-foreground/50",
    gradient: "from-foreground/[0.04] via-foreground/[0.02] to-transparent",
  },
  effect: {
    bg: "bg-foreground/[0.06]",
    icon: "text-foreground/50",
    gradient: "from-foreground/[0.04] via-foreground/[0.02] to-transparent",
  },
  utility: {
    bg: "bg-foreground/[0.06]",
    icon: "text-foreground/50",
    gradient: "from-foreground/[0.04] via-foreground/[0.02] to-transparent",
  },
}

function TypeIcon({ type, size }: { type: PluginType; size: number }) {
  const props = { className: "shrink-0", size, strokeWidth: 1.5 }
  switch (type) {
    case "instrument": return <Piano {...props} />
    case "effect": return <Waves {...props} />
    case "utility": return <Gauge {...props} />
  }
}

export function PluginArtworkView({ plugin, size = "full", className = "" }: Props) {
  const style = typeStyles[plugin.type]

  if (size === "compact") {
    return (
      <div
        className={`rounded-lg flex items-center justify-center ${style.bg} ${style.icon} ${className}`}
        style={{ width: 32, height: 32 }}
      >
        <TypeIcon type={plugin.type} size={15} />
      </div>
    )
  }

  return (
    <div className={`relative w-full h-full ${className}`}>
      <div className="absolute inset-0 bg-muted" />
      <div className={`absolute inset-0 bg-gradient-to-br ${style.gradient}`} />
      <div className={`absolute inset-0 flex items-center justify-center ${style.icon}`}>
        <TypeIcon type={plugin.type} size={32} />
      </div>
    </div>
  )
}
