import type { PluginFilter } from "@/lib/types"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"

const tabs: { filter: PluginFilter; label: string }[] = [
  { filter: "ALL", label: "All" },
  { filter: "INSTRUMENTS", label: "Inst" },
  { filter: "EFFECTS", label: "FX" },
  { filter: "UTILITIES", label: "Util" },
]

interface Props {
  activeFilter: PluginFilter
  onTap: (filter: PluginFilter) => void
}

export function FilterTabBar({ activeFilter, onTap }: Props) {
  return (
    <ToggleGroup
      value={[activeFilter]}
      onValueChange={(value) => {
        // Keep single-select behavior: use the last pressed value
        const next = value.filter((v) => v !== activeFilter)
        if (next.length > 0) onTap(next[0] as PluginFilter)
      }}
      variant="default"
      size="sm"
      className="w-full"
    >
      {tabs.map((tab) => (
        <ToggleGroupItem
          key={tab.filter}
          value={tab.filter}
          className="flex-1 text-[10px] font-mono tracking-[0.5px]"
        >
          {tab.label}
        </ToggleGroupItem>
      ))}
    </ToggleGroup>
  )
}
