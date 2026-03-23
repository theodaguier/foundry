import type { Plugin } from "@/lib/types"
import { hexToRgba } from "@/lib/utils"
import { AbstractArtwork } from "@/components/app/abstract-artwork"

interface Props {
  plugin: Plugin
  size?: "full" | "compact"
  className?: string
}

export function PluginArtworkView({ plugin, size = "full", className = "" }: Props) {
  if (size === "compact") {
    return (
      <div
        className={`rounded-[10px] flex items-center justify-center overflow-hidden ${className}`}
        style={{
          width: 36,
          height: 36,
          backgroundColor: hexToRgba(plugin.iconColor, 0.15),
        }}
      >
        <span className="text-[15px]">
          {plugin.type === "instrument" ? "♪" : plugin.type === "effect" ? "~" : "◎"}
        </span>
      </div>
    )
  }

  return (
    <div className={`relative w-full h-full ${className}`}>
      <div className="absolute inset-0 bg-muted" />
      <div className="absolute inset-0" style={{ backgroundColor: hexToRgba(plugin.iconColor, 0.07) }} />
      <div className="absolute inset-0 flex items-center justify-center">
        <AbstractArtwork pluginType={plugin.type} />
      </div>
    </div>
  )
}
