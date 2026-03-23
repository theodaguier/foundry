import type { PluginFilter } from "@/lib/types"

const tabs: PluginFilter[] = ["ALL", "INSTRUMENTS", "EFFECTS", "UTILITIES"]

interface Props {
  activeFilter: PluginFilter
  onTap: (filter: PluginFilter) => void
}

export function FilterTabBar({ activeFilter, onTap }: Props) {
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
            className={`px-3 text-[11px] tracking-[0.5px] font-mono transition-colors ${
              activeFilter === tab
                ? "text-foreground"
                : "text-muted-foreground hover:text-foreground"
            }`}
          >
            {tab}
          </span>
          <div
            className={`absolute bottom-0 left-0 right-0 h-[2px] ${activeFilter === tab ? "bg-primary" : "bg-transparent"}`}
          />
        </button>
      ))}
    </div>
  )
}
