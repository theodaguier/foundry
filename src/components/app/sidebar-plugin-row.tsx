import type { Plugin } from "@/lib/types"
import { pluginTypeDisplayName } from "@/lib/utils"
import { PluginArtworkView } from "@/components/app/plugin-artwork-view"
import {
  SidebarMenuItem,
  SidebarMenuButton,
} from "@/components/ui/sidebar"
import {
  ContextMenu,
  ContextMenuTrigger,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
} from "@/components/ui/context-menu"

interface Props {
  plugin: Plugin
  isSelected: boolean
  isBuilding: boolean
  buildProgress: number
  onClick: () => void
  onRename: () => void
  onDelete: () => void
  onRefine: () => void
  onShowInFinder: () => void
}

export function SidebarPluginRow({
  plugin,
  isSelected,
  isBuilding,
  buildProgress,
  onClick,
  onRename,
  onDelete,
  onRefine,
  onShowInFinder,
}: Props) {
  const subtitle = `${pluginTypeDisplayName(plugin.type)} — ${plugin.formats.join(" / ")}`

  return (
    <ContextMenu>
      <ContextMenuTrigger>
        <SidebarMenuItem>
          <SidebarMenuButton
            size="lg"
            isActive={isSelected}
            onClick={onClick}
            className="relative"
          >
            <PluginArtworkView plugin={plugin} size="compact" className="shrink-0" />
            <div className="flex-1 min-w-0">
              <div className="text-[12px] truncate leading-tight">
                {plugin.name}
              </div>
              <div className="text-[10px] text-muted-foreground/60 truncate leading-tight mt-px">
                {isBuilding
                  ? `Building… ${Math.round(buildProgress * 100)}%`
                  : subtitle}
              </div>
            </div>
            <div className="shrink-0 flex items-center">
              {isBuilding ? (
                <div className="w-2 h-2 border-[1.5px] border-foreground/30 border-t-transparent rounded-full animate-spin" />
              ) : plugin.status === "installed" ? (
                <div className="w-1.5 h-1.5 rounded-full bg-foreground/20" />
              ) : plugin.status === "failed" ? (
                <div className="w-1.5 h-1.5 rounded-full bg-destructive/60" />
              ) : null}
            </div>
            {isBuilding && (
              <div className="absolute bottom-0 left-0 right-0 h-px">
                <div
                  className="h-full bg-foreground/15 transition-all duration-300 ease-out"
                  style={{ width: `${buildProgress * 100}%` }}
                />
              </div>
            )}
          </SidebarMenuButton>
        </SidebarMenuItem>
      </ContextMenuTrigger>
      <ContextMenuContent>
        <ContextMenuItem onClick={onShowInFinder}>
          Show in Folder
        </ContextMenuItem>
        <ContextMenuItem onClick={onRename}>
          Rename
        </ContextMenuItem>
        <ContextMenuItem onClick={onRefine} disabled={!plugin.buildDirectory}>
          Refine
        </ContextMenuItem>
        <ContextMenuSeparator />
        <ContextMenuItem variant="destructive" onClick={onDelete}>
          Delete
        </ContextMenuItem>
      </ContextMenuContent>
    </ContextMenu>
  )
}
