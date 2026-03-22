import type { Plugin } from "../../lib/types";
import { pluginTypeDisplayName } from "../../lib/utils";
import PluginArtworkView from "./PluginArtworkView";

interface Props {
  plugin: Plugin;
  buildProgress?: number;
  onTap: () => void;
  onRename?: () => void;
  onShowInFinder?: () => void;
  onDelete?: () => void;
}

export default function PluginCard({ plugin, buildProgress = 0, onTap }: Props) {
  const isBuilding = plugin.status === "building";
  const subtitle = `${pluginTypeDisplayName(plugin.type).toUpperCase()} · ${plugin.formats.join(" / ")}`;

  return (
    <button onClick={onTap} onContextMenu={(e) => { e.preventDefault(); }} className="w-full text-left group bg-[var(--color-bg-window)]">
      <div className="flex flex-col">
        {/* Artwork area — Swift: height 204 */}
        <div className="h-[204px] relative overflow-hidden">
          {isBuilding ? (
            <BuildingArtwork />
          ) : (
            <PluginArtworkView plugin={plugin} />
          )}
        </div>

        {/* Info area — Swift: height 136, px 20, pb 13 */}
        <div className="h-[136px] bg-[var(--color-bg-window)] relative flex flex-col justify-end px-5 pb-[13px]">
          <div className="flex flex-col gap-[3px]">
            {isBuilding ? (
              <>
                <span className="text-[20px] font-[ArchitypeStedelijk] tracking-[1px] text-[var(--color-text-secondary)] uppercase truncate leading-tight">
                  {plugin.name}
                </span>
                <span className="text-[9px] font-[var(--font-mono)] tracking-[1.8px] text-[var(--color-text-primary)]">
                  BUILDING... {Math.round(buildProgress * 100)}%
                </span>
              </>
            ) : (
              <span className="text-[24px] font-[ArchitypeStedelijk] tracking-[1px] text-[var(--color-text-primary)] uppercase truncate leading-tight">
                {plugin.name}
              </span>
            )}
            <span className="text-[9px] font-[var(--font-mono)] tracking-[0.9px] text-[var(--color-text-secondary)] uppercase">
              {subtitle}
            </span>
          </div>

          {/* Progress bar — Swift: height 4pt at bottom */}
          {isBuilding && (
            <div className="absolute bottom-0 left-0 right-0 h-1">
              <div className="h-full bg-[var(--color-border)]" />
              <div
                className="h-full bg-[var(--color-accent)] absolute top-0 left-0 transition-all duration-300"
                style={{ width: `${buildProgress * 100}%` }}
              />
            </div>
          )}
        </div>
      </div>
    </button>
  );
}

/** Dashed border + gear icon — Swift: buildingArtwork */
function BuildingArtwork() {
  return (
    <div className="w-full h-full bg-[var(--color-bg-text)] flex items-center justify-center">
      <div className="m-8 border border-dashed border-[var(--color-border-subtle)] w-full h-full flex items-center justify-center">
        <svg className="w-[18px] h-[18px] text-[var(--color-border-subtle)]" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 12a7.5 7.5 0 0015 0m-15 0a7.5 7.5 0 1115 0m-15 0H3m16.5 0H21m-1.5 0H12m-8.457 3.077l1.41-.513m14.095-5.13l1.41-.513M5.106 17.785l1.15-.964m11.49-9.642l1.149-.964M7.501 19.795l.75-1.3m7.5-12.99l.75-1.3m-6.063 16.658l.26-1.477m2.605-14.772l.26-1.477m0 17.726l-.26-1.477M10.698 4.614l-.26-1.477M16.5 19.794l-.75-1.299M7.5 4.205L12 12m0 0l4.5 7.795M12 12L5.106 6.215M12 12l6.894-5.785" />
        </svg>
      </div>
    </div>
  );
}
