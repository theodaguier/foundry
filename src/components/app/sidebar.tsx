import { useState, useMemo } from "react"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { useSettingsStore } from "@/stores/settings-store"
import { showInFinder } from "@/lib/commands"
import { cn } from "@/lib/utils"
import { FoundryLogo } from "@/components/app/foundry-logo"
import { FilterTabBar } from "@/components/app/filter-tab-bar"
import { SidebarPluginRow } from "@/components/app/sidebar-plugin-row"
import {
  Sidebar as SidebarRoot,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarInput,
} from "@/components/ui/sidebar"
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Plus, Search, ArrowDownToLine } from "lucide-react"
import type { Plugin } from "@/lib/types"

export function AppSidebar() {
  const plugins = useAppStore((s) => s.plugins)
  const filter = useAppStore((s) => s.filter)
  const setFilter = useAppStore((s) => s.setFilter)
  const mainView = useAppStore((s) => s.mainView)
  const setMainView = useAppStore((s) => s.setMainView)
  const deletePlugin = useAppStore((s) => s.deletePlugin)
  const renamePlugin = useAppStore((s) => s.renamePlugin)
  const isRunning = useBuildStore((s) => s.isRunning)
  const buildProgress = useBuildStore((s) => s.progress)
  const refineConfig = useBuildStore((s) => s.refineConfig)
  const updateStatus = useSettingsStore((s) => s.updateStatus)
  const availableUpdate = useSettingsStore((s) => s.availableUpdate)

  const installAppUpdate = useSettingsStore((s) => s.installAppUpdate)
  const isBuildRunning = useBuildStore((s) => s.isRunning)

  const [pluginToDelete, setPluginToDelete] = useState<string | null>(null)
  const [pluginToRename, setPluginToRename] = useState<Plugin | null>(null)
  const [renameText, setRenameText] = useState("")
  const [search, setSearch] = useState("")
  const [showUpdate, setShowUpdate] = useState(false)

  const filteredPlugins = useMemo(() => {
    let result = plugins
    switch (filter) {
      case "INSTRUMENTS": result = result.filter((p) => p.type === "instrument"); break
      case "EFFECTS": result = result.filter((p) => p.type === "effect"); break
      case "UTILITIES": result = result.filter((p) => p.type === "utility"); break
    }
    if (search.trim()) {
      const q = search.toLowerCase()
      result = result.filter((p) => p.name.toLowerCase().includes(q))
    }
    return [...result].sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
  }, [plugins, filter, search])

  const selectedPluginId = mainView.kind === "detail" ? mainView.pluginId
    : mainView.kind === "refine" ? mainView.pluginId
    : null

  const handlePluginClick = (plugin: Plugin) => {
    if (plugin.status === "building" && isRunning) {
      setMainView({ kind: refineConfig ? "refinement" : "generation" })
    } else {
      setMainView({ kind: "detail", pluginId: plugin.id })
    }
  }

  const handleDelete = (id: string) => {
    deletePlugin(id)
    setPluginToDelete(null)
    if (selectedPluginId === id) {
      setMainView({ kind: "empty" })
    }
  }

  const handleRename = () => {
    if (pluginToRename && renameText.trim()) {
      renamePlugin(pluginToRename.id, renameText.trim())
      setPluginToRename(null)
    }
  }

  return (
    <SidebarRoot collapsible="none">
      <SidebarHeader>
        <div data-tauri-drag-region className="h-[52px] shrink-0 flex items-end justify-between pb-1 px-2">
          <FoundryLogo
            height={24}
            className="text-sidebar-foreground/50 shrink-0"
          />
          <Button
            size="icon-sm"
            variant="secondary"
            onClick={() => setMainView({ kind: "prompt" })}
          >
            <Plus className="size-3.5" />
          </Button>
        </div>

        <div className="relative">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 size-3 text-sidebar-foreground/40 pointer-events-none" />
          <SidebarInput
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search plugins..."
            className="pl-7 text-[11px] h-6"
          />
        </div>

        <div>
          <FilterTabBar activeFilter={filter} onTap={setFilter} />
        </div>
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup className="p-0">
          <SidebarGroupContent>
            <ScrollArea className="flex-1">
              <div className="flex flex-col px-2 gap-0.5">
                {filteredPlugins.map((plugin) => (
                  <SidebarPluginRow
                    key={plugin.id}
                    plugin={plugin}
                    isSelected={selectedPluginId === plugin.id}
                    isBuilding={plugin.status === "building"}
                    buildProgress={plugin.status === "building" ? buildProgress : 0}
                    onClick={() => handlePluginClick(plugin)}
                    onRename={() => { setPluginToRename(plugin); setRenameText(plugin.name) }}
                    onDelete={() => setPluginToDelete(plugin.id)}
                    onRefine={() => setMainView({ kind: "refine", pluginId: plugin.id })}
                    onShowInFinder={() => {
                      const path = plugin.installPaths.vst3 || plugin.installPaths.au
                      if (path) showInFinder(path)
                    }}
                  />
                ))}
                {filteredPlugins.length === 0 && (
                  <div className="px-3 py-8 text-center text-[11px] text-sidebar-foreground/30">
                    {search.trim() ? "No matches" : "No plugins yet"}
                  </div>
                )}
              </div>
            </ScrollArea>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="py-2">
        {updateStatus === "available" && availableUpdate && (
          <button
            onClick={() => setShowUpdate(true)}
            className="flex items-center gap-2 mx-2 px-2.5 py-1.5 rounded-md bg-primary/10 text-[10px] text-primary hover:bg-primary/15 transition-colors cursor-default"
          >
            <ArrowDownToLine className="size-3 shrink-0" />
            <span>Update {availableUpdate.version} available</span>
          </button>
        )}
      </SidebarFooter>

      <Dialog open={!!pluginToDelete} onOpenChange={(v) => { if (!v) setPluginToDelete(null) }}>
        <DialogContent showCloseButton={false}>
          <DialogHeader>
            <DialogTitle>Delete Plugin?</DialogTitle>
            <DialogDescription>This removes the plugin from Foundry. Installed files on disk are not deleted automatically.</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPluginToDelete(null)}>Cancel</Button>
            <Button variant="destructive" onClick={() => { if (pluginToDelete) handleDelete(pluginToDelete) }}>Delete</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!pluginToRename} onOpenChange={(v) => { if (!v) setPluginToRename(null) }}>
        <DialogContent showCloseButton={false}>
          <DialogHeader>
            <DialogTitle>Rename Plugin</DialogTitle>
          </DialogHeader>
          <Input
            value={renameText}
            onChange={(e) => setRenameText(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && renameText.trim()) handleRename() }}
            autoFocus
            className="font-mono text-[13px]"
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setPluginToRename(null)}>Cancel</Button>
            <Button onClick={handleRename} disabled={!renameText.trim()}>Rename</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Update dialog */}
      <Dialog open={showUpdate} onOpenChange={(v) => { if (!v) setShowUpdate(false) }}>
        <DialogContent showCloseButton={false}>
          <DialogHeader>
            <DialogTitle>Update available</DialogTitle>
            <DialogDescription>
              Version {availableUpdate?.version} is ready to install.
            </DialogDescription>
          </DialogHeader>
          {availableUpdate?.notes && (
            <div className="max-h-32 overflow-y-auto rounded-md bg-muted/40 px-2.5 py-2 text-[10px] text-muted-foreground/50 whitespace-pre-wrap break-words">
              {availableUpdate.notes}
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowUpdate(false)}>Later</Button>
            <Button
              onClick={() => { setShowUpdate(false); void installAppUpdate() }}
              disabled={isBuildRunning}
            >
              <ArrowDownToLine className="size-3" />
              Install now
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </SidebarRoot>
  )
}
