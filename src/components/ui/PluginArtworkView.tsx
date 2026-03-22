import type { Plugin } from "../../lib/types";
import { hexToRgba } from "../../lib/utils";
import AbstractArtwork from "./AbstractArtwork";

interface Props {
  plugin: Plugin;
  /** Full-size artwork (for cards, detail view) vs compact (for list rows) */
  size?: "full" | "compact";
  className?: string;
}

/**
 * Plugin artwork — shows logo image if available, otherwise AbstractArtwork fallback.
 * Matches Swift PluginArtworkView + LibraryPluginCard artworkArea.
 */
export default function PluginArtworkView({ plugin, size = "full", className = "" }: Props) {
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
    );
  }

  return (
    <div className={`relative w-full h-full ${className}`}>
      {/* Base background */}
      <div className="absolute inset-0 bg-[var(--color-bg-text)]" />
      {/* Plugin color wash at 7% */}
      <div className="absolute inset-0" style={{ backgroundColor: hexToRgba(plugin.iconColor, 0.07) }} />
      {/* Content */}
      <div className="absolute inset-0 flex items-center justify-center">
        <AbstractArtwork pluginType={plugin.type} />
      </div>
    </div>
  );
}
