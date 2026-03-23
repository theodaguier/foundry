import { useState, useMemo } from "react"
import { useNavigate } from "react-router-dom"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { FoundryLogo } from "@/components/app/foundry-logo"
import { FilterTabBar } from "@/components/app/filter-tab-bar"
import { PluginCard } from "@/components/app/plugin-card"
import { PluginDetailView } from "@/components/app/plugin-detail-view"
import { ConfirmDialog, InputDialog } from "@/components/app/confirm-dialog"
import type { Plugin } from "@/lib/types"

export default function PluginLibrary() {
  const navigate = useNavigate()
  const allPlugins = useAppStore((s) => s.plugins)
  const filter = useAppStore((s) => s.filter)
  const plugins = useMemo(() => {
    let result = allPlugins
    switch (filter) {
      case "INSTRUMENTS": result = result.filter((p) => p.type === "instrument"); break
      case "EFFECTS": result = result.filter((p) => p.type === "effect"); break
      case "UTILITIES": result = result.filter((p) => p.type === "utility"); break
    }
    return [...result].sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
  }, [allPlugins, filter])
  const setFilter = useAppStore((s) => s.setFilter)
  const deletePlugin = useAppStore((s) => s.deletePlugin)
  const renamePlugin = useAppStore((s) => s.renamePlugin)
  const isRunning = useBuildStore((s) => s.isRunning)
  const buildProgress = useBuildStore((s) => s.progress)

  const [selectedPlugin, setSelectedPlugin] = useState<Plugin | null>(null)
  const [pluginToDelete, setPluginToDelete] = useState<string | null>(null)
  const [pluginToRename, setPluginToRename] = useState<Plugin | null>(null)
  const [renameText, setRenameText] = useState("")

  return (
    <div className="flex flex-col h-full">
      <div data-tauri-drag-region className="flex items-center h-[44px] px-4 bg-muted border-b border-border shrink-0">
        <button onClick={() => navigate("/prompt")} className="mr-6 shrink-0">
          <FoundryLogo height={18} className="text-foreground" />
        </button>
        <FilterTabBar activeFilter={filter} onTap={setFilter} />
        <div className="flex-1" />
        <div className="flex items-center gap-1">
          <button onClick={() => navigate("/queue")} className="relative p-1.5 text-muted-foreground/60 hover:text-muted-foreground">
            <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 12h16.5m-16.5 3.75h16.5M3.75 19.5h16.5M5.625 4.5h12.75a1.875 1.875 0 0 1 0 3.75H5.625a1.875 1.875 0 0 1 0-3.75Z" />
            </svg>
            {isRunning && (
              <span className="absolute top-0.5 right-0.5 w-1.5 h-1.5 bg-primary rounded-full" />
            )}
          </button>
          <button onClick={() => navigate("/settings")} className="p-1.5 text-muted-foreground/60 hover:text-muted-foreground">
            <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        <div className="grid gap-px bg-border" style={{ gridTemplateColumns: "repeat(5, 1fr)" }}>
          <button
            onClick={() => navigate("/prompt")}
            className="bg-muted flex flex-col items-center justify-center gap-2 min-h-[340px] hover:bg-card transition-colors"
          >
            <svg className="w-[18px] h-[18px] text-muted-foreground" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            <span className="text-[10px] font-mono tracking-[2px] text-muted-foreground">NEW PLUGIN</span>
          </button>

          {plugins.map((plugin) => (
            <PluginCard
              key={plugin.id}
              plugin={plugin}
              buildProgress={plugin.status === "building" ? buildProgress : 0}
              onTap={() => setSelectedPlugin(plugin)}
              onDelete={() => setPluginToDelete(plugin.id)}
            />
          ))}
        </div>
      </div>

      {selectedPlugin && (
        <PluginDetailView
          plugin={selectedPlugin}
          onDismiss={() => setSelectedPlugin(null)}
          onDelete={() => { setPluginToDelete(selectedPlugin.id); setSelectedPlugin(null) }}
          onRename={() => { setPluginToRename(selectedPlugin); setRenameText(selectedPlugin.name); setSelectedPlugin(null) }}
        />
      )}

      <ConfirmDialog
        open={!!pluginToDelete}
        title="Delete Plugin?"
        message="This will uninstall the AU/VST3 files from your system. This cannot be undone."
        confirmLabel="Delete"
        destructive
        onConfirm={() => { if (pluginToDelete) deletePlugin(pluginToDelete); setPluginToDelete(null) }}
        onCancel={() => setPluginToDelete(null)}
      />

      <InputDialog
        open={!!pluginToRename}
        title="Rename Plugin"
        value={renameText}
        onChange={setRenameText}
        confirmLabel="Rename"
        onConfirm={() => { if (pluginToRename && renameText.trim()) { renamePlugin(pluginToRename.id, renameText.trim()); setPluginToRename(null) } }}
        onCancel={() => setPluginToRename(null)}
      />
    </div>
  )
}
