import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import type { Plugin } from "@/lib/types"
import { cn, pluginTypeDisplayName } from "@/lib/utils"
import { showInFinder } from "@/lib/commands"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Separator } from "@/components/ui/separator"
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from "@/components/ui/dropdown-menu"
import { PluginArtworkView } from "@/components/app/plugin-artwork-view"
import { VersionHistoryView } from "@/components/app/version-history-view"
import { PluginFeedback } from "@/components/app/plugin-feedback"
import { MoreHorizontal, FolderOpen, RotateCcw } from "lucide-react"

interface Props {
  plugin: Plugin
}

export function PluginDetailView({ plugin }: Props) {
  const setMainView = useAppStore((s) => s.setMainView)
  const deletePlugin = useAppStore((s) => s.deletePlugin)
  const loadPlugins = useAppStore((s) => s.loadPlugins)
  const isRunning = useBuildStore((s) => s.isRunning)
  const retryPlugin = useBuildStore((s) => s.retryPlugin)
  const openFolder = () => {
    const path = plugin.installPaths.vst3 || plugin.installPaths.au
    if (path) showInFinder(path)
  }

  const handleRefine = () => {
    setMainView({ kind: "refine", pluginId: plugin.id })
  }

  const handleRetry = () => {
    setMainView({ kind: "generation" })
    void retryPlugin(plugin)
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
      <div className="w-full px-6 pt-4 pb-6 flex flex-col gap-4">

        {/* Hero banner */}
        <div className="relative h-[120px] rounded-lg overflow-hidden">
          <PluginArtworkView plugin={plugin} />
          <div className="absolute inset-0 bg-gradient-to-t from-background via-background/50 to-transparent" />
          <div className="absolute top-3 right-3 flex items-center gap-1.5">
            <Button
              size="sm"
              variant="secondary"
              className="bg-background/80 backdrop-blur-sm text-xs h-7"
              onClick={plugin.status === "failed" ? handleRetry : handleRefine}
              disabled={
                plugin.status === "failed"
                  ? isRunning || (!plugin.generationConfig && !plugin.prompt)
                  : !plugin.buildDirectory
              }
            >
              {plugin.status === "failed" ? (
                <>
                  <RotateCcw className="size-3.5" />
                  Retry
                </>
              ) : (
                "Refine"
              )}
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
            <div className="flex items-center gap-2 mb-0.5">
              <span className="text-[10px] tracking-[1.5px] uppercase text-muted-foreground">
                {pluginTypeDisplayName(plugin.type)}
              </span>
              <span className="text-[10px] text-muted-foreground/30">·</span>
              <span className="text-[10px] tracking-[0.5px] text-muted-foreground/50">
                {plugin.formats.join(" / ")}
              </span>
            </div>
            <h1 className="text-base font-[ArchitypeStedelijk] tracking-[0.5px] text-foreground uppercase truncate leading-tight">
              {plugin.name}
            </h1>
          </div>
        </div>

        {/* Prompt */}
        {plugin.prompt && plugin.prompt !== "Restored — original prompt unavailable" && (
          <p className="text-[10px] text-muted-foreground/60 leading-relaxed">
            {plugin.prompt}
          </p>
        )}

        {/* Error card */}
        {plugin.status === "failed" && plugin.lastErrorMessage && (
          <div className="flex flex-col gap-1">
            <div className="text-[10px] text-destructive/70 break-words whitespace-pre-wrap leading-relaxed">{plugin.lastErrorMessage}</div>
          </div>
        )}

        {/* Details */}
        <div>
          <div className="text-[10px] tracking-[1.5px] uppercase text-muted-foreground/50 mb-2">Details</div>
          <Card size="sm">
            <CardContent className="flex flex-col">
              <DetailRow label="Type" value={pluginTypeDisplayName(plugin.type)} />
              <Separator />
              <DetailRow label="Formats" value={plugin.formats.join(", ")} />
              <Separator />
              <DetailRow label="Created" value={createdDate} />
              <Separator />
              <div className="flex items-center justify-between py-2">
                <span className="text-[10px] text-muted-foreground/60">Status</span>
                <Badge variant={plugin.status === "failed" ? "destructive" : plugin.status === "building" ? "outline" : "secondary"}>
                  {plugin.status}
                </Badge>
              </div>
              {plugin.currentVersion > 0 && (
                <>
                  <Separator />
                  <DetailRow label="Version" value={`v${plugin.currentVersion}`} />
                </>
              )}
              {plugin.agent && (
                <>
                  <Separator />
                  <DetailRow label="Agent" value={plugin.agent} />
                </>
              )}
              {plugin.model && (
                <>
                  <Separator />
                  <DetailRow label="Model" value={plugin.model.name} />
                </>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Feedback */}
        {plugin.status === "installed" && (
          <div>
            <PluginFeedback pluginId={plugin.id} />
          </div>
        )}

        {/* Version History */}
        {plugin.versions.length > 0 && (
          <div>
            <VersionHistoryView plugin={plugin} onVersionRestored={handlePluginUpdated} />
          </div>
        )}

        {/* Install Paths */}
        {(plugin.installPaths.au || plugin.installPaths.vst3) && (
          <div>
            <div className="text-[10px] tracking-[1.5px] uppercase text-muted-foreground/50 mb-2">Install Paths</div>
            <Card size="sm">
              <CardContent className="flex flex-col">
                {plugin.installPaths.au && (
                  <div className="flex items-center gap-3 py-2">
                    <span className="text-[10px] text-muted-foreground/60 shrink-0 w-7">AU</span>
                    <span className="flex-1 text-[10px] text-muted-foreground/50 truncate">
                      {plugin.installPaths.au}
                    </span>
                    <Button
                      variant="ghost"
                      size="icon-xs"
                      onClick={() => showInFinder(plugin.installPaths.au!)}
                    >
                      <FolderOpen className="size-3" />
                    </Button>
                  </div>
                )}
                {plugin.installPaths.au && plugin.installPaths.vst3 && <Separator />}
                {plugin.installPaths.vst3 && (
                  <div className="flex items-center gap-3 py-2">
                    <span className="text-[10px] text-muted-foreground/60 shrink-0 w-7">VST3</span>
                    <span className="flex-1 text-[10px] text-muted-foreground/50 truncate">
                      {plugin.installPaths.vst3}
                    </span>
                    <Button
                      variant="ghost"
                      size="icon-xs"
                      onClick={() => showInFinder(plugin.installPaths.vst3!)}
                    >
                      <FolderOpen className="size-3" />
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

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between py-1.5">
      <span className="text-[10px] text-muted-foreground/60">{label}</span>
      <span className="text-[10px]">{value}</span>
    </div>
  )
}
