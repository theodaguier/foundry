import { useAppStore } from "@/stores/app-store"
import type { Plugin } from "@/lib/types"
import { pluginTypeDisplayName } from "@/lib/utils"
import { showInFinder } from "@/lib/commands"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from "@/components/ui/dropdown-menu"
import { PluginArtworkView } from "@/components/app/plugin-artwork-view"
import { VersionHistoryView } from "@/components/app/version-history-view"
import { MoreHorizontal, FolderOpen } from "lucide-react"

interface Props {
  plugin: Plugin
}

export function PluginDetailView({ plugin }: Props) {
  const setMainView = useAppStore((s) => s.setMainView)
  const deletePlugin = useAppStore((s) => s.deletePlugin)
  const loadPlugins = useAppStore((s) => s.loadPlugins)
  const openFolder = () => {
    const path = plugin.installPaths.vst3 || plugin.installPaths.au
    if (path) showInFinder(path)
  }

  const handleRefine = () => {
    setMainView({ kind: "refine", pluginId: plugin.id })
  }

  const handleDelete = async () => {
    await deletePlugin(plugin.id)
    setMainView({ kind: "empty" })
  }

  const handlePluginUpdated = async () => {
    await loadPlugins()
  }

  const createdDate = new Date(plugin.createdAt).toLocaleDateString("en-US", {
    month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit",
  })

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-[600px] mx-auto px-6 pt-4 pb-6 flex flex-col gap-5">

        {/* Hero banner */}
        <div className="relative h-[140px] rounded-xl overflow-hidden">
          <PluginArtworkView plugin={plugin} />
          <div className="absolute inset-0 bg-gradient-to-t from-background/90 via-background/40 to-transparent" />
          <div className="absolute top-3 right-3 flex items-center gap-1.5">
            <Button
              size="sm"
              variant="secondary"
              className="bg-background/80 backdrop-blur-sm text-xs h-7"
              onClick={handleRefine}
              disabled={!plugin.buildDirectory}
            >
              Refine
            </Button>
            <DropdownMenu>
              <DropdownMenuTrigger
                render={
                  <Button variant="ghost" size="icon" className="size-7 bg-background/80 backdrop-blur-sm">
                    <MoreHorizontal className="size-3.5" />
                  </Button>
                }
              />
              <DropdownMenuContent align="end">
                <DropdownMenuItem onClick={openFolder}>
                  Show in Folder
                </DropdownMenuItem>
                <DropdownMenuItem onClick={handleDelete} className="text-destructive">
                  Delete
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
          <div className="absolute bottom-3 left-4 right-4">
            <span className="text-[10px] tracking-[1px] text-muted-foreground uppercase">
              {pluginTypeDisplayName(plugin.type)} — {plugin.formats.join(" / ")}
            </span>
            <h1 className="text-2xl font-[ArchitypeStedelijk] tracking-[0.5px] text-foreground uppercase truncate leading-tight mt-0.5">
              {plugin.name}
            </h1>
          </div>
        </div>

        {/* Prompt */}
        {plugin.prompt && plugin.prompt !== "Restored — original prompt unavailable" && (
          <p className="text-sm text-muted-foreground leading-relaxed">
            {plugin.prompt}
          </p>
        )}

        {/* Details */}
        <div className="flex flex-col gap-3">
          <Label>Details</Label>
          <Card size="sm">
            <CardContent className="flex flex-col">
              <div className="flex items-center justify-between py-2">
                <span className="text-sm text-muted-foreground">Type</span>
                <span className="text-sm">{pluginTypeDisplayName(plugin.type)}</span>
              </div>
              <Separator />
              <div className="flex items-center justify-between py-2">
                <span className="text-sm text-muted-foreground">Formats</span>
                <span className="text-sm">{plugin.formats.join(", ")}</span>
              </div>
              <Separator />
              <div className="flex items-center justify-between py-2">
                <span className="text-sm text-muted-foreground">Created</span>
                <span className="text-sm">{createdDate}</span>
              </div>
              {plugin.currentVersion > 0 && (
                <>
                  <Separator />
                  <div className="flex items-center justify-between py-2">
                    <span className="text-sm text-muted-foreground">Version</span>
                    <span className="text-sm">v{plugin.currentVersion}</span>
                  </div>
                </>
              )}
              {plugin.agent && (
                <>
                  <Separator />
                  <div className="flex items-center justify-between py-2">
                    <span className="text-sm text-muted-foreground">Agent</span>
                    <span className="text-sm">{plugin.agent}</span>
                  </div>
                </>
              )}
              {plugin.model && (
                <>
                  <Separator />
                  <div className="flex items-center justify-between py-2">
                    <span className="text-sm text-muted-foreground">Model</span>
                    <span className="text-sm">{plugin.model.name}</span>
                  </div>
                </>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Version History */}
        {plugin.versions.length > 0 && (
          <VersionHistoryView plugin={plugin} onVersionRestored={handlePluginUpdated} />
        )}

        {/* Install Paths */}
        {(plugin.installPaths.au || plugin.installPaths.vst3) && (
          <div className="flex flex-col gap-3">
            <Label>Install Paths</Label>
            <Card size="sm">
              <CardContent className="flex flex-col">
                {plugin.installPaths.au && (
                  <div className="flex items-center gap-3 py-2">
                    <span className="text-sm text-muted-foreground shrink-0">AU</span>
                    <span className="flex-1 text-xs font-mono text-muted-foreground/70 truncate">
                      {plugin.installPaths.au}
                    </span>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="size-7 shrink-0"
                      onClick={() => showInFinder(plugin.installPaths.au!)}
                    >
                      <FolderOpen className="size-3.5" />
                    </Button>
                  </div>
                )}
                {plugin.installPaths.au && plugin.installPaths.vst3 && <Separator />}
                {plugin.installPaths.vst3 && (
                  <div className="flex items-center gap-3 py-2">
                    <span className="text-sm text-muted-foreground shrink-0">VST3</span>
                    <span className="flex-1 text-xs font-mono text-muted-foreground/70 truncate">
                      {plugin.installPaths.vst3}
                    </span>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="size-7 shrink-0"
                      onClick={() => showInFinder(plugin.installPaths.vst3!)}
                    >
                      <FolderOpen className="size-3.5" />
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        )}

      </div>

    </div>
  )
}
