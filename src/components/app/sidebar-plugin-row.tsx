import type { Plugin } from "@/lib/types"
import { cn, pluginTypeDisplayName } from "@/lib/utils"
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
  return (
    <ContextMenu>
      <ContextMenuTrigger>
        <SidebarMenuItem>
          <SidebarMenuButton
            size="lg"
            isActive={isSelected}
            onClick={onClick}
            className="relative gap-2.5"
          >
            <PluginArtworkView plugin={plugin} size="compact" className="shrink-0" />
            <div className="flex-1 min-w-0">
              <div className="text-[11px] truncate leading-tight">
                {plugin.name}
              </div>
              <div className="text-[9px] text-muted-foreground/40 truncate leading-tight mt-px">
                {isBuilding
                  ? `Building... ${Math.round(buildProgress * 100)}%`
                  : `${pluginTypeDisplayName(plugin.type)} · ${plugin.formats.join(" / ")}`}
              </div>
            </div>
            <div className="shrink-0 flex items-center">
              {isBuilding ? (
                <div className="size-1.5 border border-foreground/30 border-t-transparent rounded-full animate-spin" />
              ) : plugin.status === "installed" ? (
                <div className="size-1 rounded-full bg-foreground/15" />
              ) : plugin.status === "failed" ? (
                <div className="size-1 rounded-full bg-destructive/50" />
              ) : null}
            </div>
            {isBuilding && (
              <div className="absolute bottom-0 left-0 right-0 h-px">
                <div
                  className="h-full bg-foreground/10 transition-all duration-300 ease-out"
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
