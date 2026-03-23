import { useState } from "react"
import { useNavigate } from "react-router-dom"
import type { Plugin } from "@/lib/types"
import { pluginTypeDisplayName } from "@/lib/utils"
import { showInFinder } from "@/lib/commands"
import { Button } from "@/components/ui/button"
import { Separator } from "@/components/ui/separator"
import {
  Dialog,
  DialogContent,
} from "@/components/ui/dialog"
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu"
import { PluginArtworkView } from "@/components/app/plugin-artwork-view"
import { InfoRow } from "@/components/app/info-row"
import { VersionHistoryContent } from "@/components/app/version-history-view"

interface Props {
  plugin: Plugin
  onDismiss: () => void
  onDelete: () => void
  onRename: () => void
  onPluginUpdated?: (plugin: Plugin) => void
}

export function PluginDetailView({ plugin, onDismiss, onDelete, onRename, onPluginUpdated }: Props) {
  const navigate = useNavigate()
  const [showVersionHistory, setShowVersionHistory] = useState(false)

  const typeFormats = `${pluginTypeDisplayName(plugin.type).toUpperCase()} · ${plugin.formats.join(" / ")}`

  const openFinder = () => {
    const path = plugin.installPaths.vst3 || plugin.installPaths.au
    if (path) showInFinder(path)
  }

  const handleRefine = () => {
    onDismiss()
    navigate(`/refine/${plugin.id}`)
  }

  const createdDate = new Date(plugin.createdAt).toLocaleDateString("en-US", {
    month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit",
  })

  return (
    <Dialog open onOpenChange={(v) => { if (!v) onDismiss() }}>
      <DialogContent className="max-w-[520px] p-0 gap-0 overflow-hidden" showCloseButton={false}>
        {showVersionHistory ? (
          <VersionHistoryContent
            plugin={plugin}
            onBack={() => setShowVersionHistory(false)}
            onVersionRestored={onPluginUpdated}
          />
        ) : (
          <>
            <div className="h-[200px] relative overflow-hidden">
              <PluginArtworkView plugin={plugin} />
              <div className="absolute bottom-0 left-0 right-0 px-6 pb-5 pt-20 bg-gradient-to-t from-background via-background/50 to-transparent">
                <span className="text-[9px] font-mono tracking-[1.2px] text-muted-foreground uppercase block">
                  {typeFormats}
                </span>
                <h1 className="text-[32px] font-[ArchitypeStedelijk] tracking-[1px] text-foreground uppercase truncate leading-tight">
                  {plugin.name}
                </h1>
              </div>
              <Separator className="absolute bottom-0 left-0 right-0" />
            </div>

            <div className="bg-background">
              <InfoRow label="PROMPT" value={plugin.prompt} />
              <Separator />
              <InfoRow label="CREATED" value={createdDate} />
              {plugin.installPaths.au && (<><Separator /><InfoRow label="AU PATH" value={plugin.installPaths.au} /></>)}
              {plugin.installPaths.vst3 && (<><Separator /><InfoRow label="VST3 PATH" value={plugin.installPaths.vst3} /></>)}
              <Separator />
            </div>

            {plugin.versions.length > 0 && (
              <>
                <button
                  className="flex items-center w-full px-6 py-3 bg-background hover:bg-muted/50 transition-colors cursor-pointer text-left"
                  onClick={() => setShowVersionHistory(true)}
                >
                  <span className="text-[9px] font-mono tracking-[1.2px] text-muted-foreground/60 uppercase">Version</span>
                  <div className="flex-1" />
                  <span className="text-[11px] font-mono text-muted-foreground">v{plugin.currentVersion}</span>
                  <span className="text-muted-foreground/25 mx-1">·</span>
                  <span className="text-[11px] font-mono text-muted-foreground/60">
                    {plugin.versions.length} version{plugin.versions.length === 1 ? "" : "s"}
                  </span>
                  <svg className="w-3 h-3 ml-2 text-muted-foreground/40" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="4 3 8 6 4 9" />
                  </svg>
                </button>
                <Separator />
              </>
            )}

            <div className="flex items-center gap-3 px-6 py-4">
              <DropdownMenu>
                <DropdownMenuTrigger
                  render={
                    <button className="flex items-center gap-1.5 px-3 py-1.5 text-muted-foreground bg-muted border border-border rounded">
                      <span className="text-[11px] font-medium">···</span>
                      <span className="text-[9px] font-mono tracking-[1.2px] uppercase">Actions</span>
                    </button>
                  }
                />
                <DropdownMenuContent>
                  <DropdownMenuItem onClick={openFinder}>Show in Finder</DropdownMenuItem>
                  <DropdownMenuItem onClick={onRename}>Rename</DropdownMenuItem>
                  <DropdownMenuItem onClick={handleRefine} disabled={!plugin.buildDirectory}>Refine</DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onClick={onDelete} className="text-destructive">Delete</DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>

              <div className="flex-1" />
              <Button size="lg" onClick={onDismiss}>Done</Button>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
