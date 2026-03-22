import type { PluginFilter } from "../../lib/types";

const tabs: PluginFilter[] = ["ALL", "INSTRUMENTS", "EFFECTS", "UTILITIES"];

interface Props {
  activeFilter: PluginFilter;
  onTap: (filter: PluginFilter) => void;
}

export default function FilterTabBar({ activeFilter, onTap }: Props) {
  return (
    <div className="flex items-center h-full">
      {tabs.map((tab, i) => (
        <button
          key={tab}
          onClick={() => onTap(tab)}
          className="flex flex-col items-center justify-center h-full relative"
          style={{ marginLeft: i === 0 ? 0 : 24 }}
        >
          <span
            className={`px-3 text-[11px] tracking-[0.5px] font-[var(--font-mono)] transition-colors ${
              activeFilter === tab
                ? "text-[var(--color-text-primary)]"
                : "text-[var(--color-text-secondary)] hover:text-[var(--color-text-primary)]"
            }`}
          >
            {tab}
          </span>
          <div
            className="absolute bottom-0 left-0 right-0 h-[2px]"
            style={{ backgroundColor: activeFilter === tab ? "rgba(255,255,255,0.85)" : "transparent" }}
          />
        </button>
      ))}
    </div>
  );
}
