import { useState, useMemo } from "react"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { showInFinder } from "@/lib/commands"
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
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
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
import { Plus, Settings, Search, Hammer, User } from "lucide-react"
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

  const [pluginToDelete, setPluginToDelete] = useState<string | null>(null)
  const [pluginToRename, setPluginToRename] = useState<Plugin | null>(null)
  const [renameText, setRenameText] = useState("")
  const [search, setSearch] = useState("")

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
        {/* Drag region — space for macOS traffic lights */}
        <div data-tauri-drag-region className="h-[52px] shrink-0" />

        {/* Logo */}
        <div className="flex items-center">
          <FoundryLogo
            height={36}
            className="text-sidebar-foreground/70 shrink-0"
          />
        </div>

        {/* New Plugin */}
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              tooltip="New Plugin"
              onClick={() => setMainView({ kind: "prompt" })}
            >
              <Plus className="size-4" />
              <span>New Plugin</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>

        {/* Search */}
        <div className="relative">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 size-3 text-sidebar-foreground/50 pointer-events-none" />
          <SidebarInput
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search..."
            className="pl-7 text-[12px] h-7"
          />
        </div>

        {/* Filters */}
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
                  <div className="px-3 py-6 text-center text-[11px] text-sidebar-foreground/40">
                    No plugins
                  </div>
                )}
              </div>
            </ScrollArea>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              isActive={mainView.kind === "build-queue"}
              onClick={() => setMainView({ kind: "build-queue" })}
            >
              <Hammer className={`size-4 ${isRunning ? "animate-pulse" : ""}`} />
              <span>Builds</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton
              isActive={mainView.kind === "profile"}
              onClick={() => setMainView({ kind: "profile" })}
            >
              <User className="size-4" />
              <span>Profile</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton
              isActive={mainView.kind === "settings"}
              onClick={() => setMainView({ kind: "settings" })}
            >
              <Settings className="size-4" />
              <span>Settings</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>

      {/* Delete dialog */}
      <Dialog open={!!pluginToDelete} onOpenChange={(v) => { if (!v) setPluginToDelete(null) }}>
        <DialogContent showCloseButton={false}>
          <DialogHeader>
            <DialogTitle>Delete Plugin?</DialogTitle>
            <DialogDescription>This will uninstall the AU/VST3 files from your system. This cannot be undone.</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPluginToDelete(null)}>Cancel</Button>
            <Button variant="destructive" onClick={() => { if (pluginToDelete) handleDelete(pluginToDelete) }}>Delete</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Rename dialog */}
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
    </SidebarRoot>
  )
}
