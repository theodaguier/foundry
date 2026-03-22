import { useState, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { useAppStore } from "../stores/app-store";
import { useBuildStore } from "../stores/build-store";
import { FilterTabBar, PluginCard, PluginDetailView } from "../components/ui";
import { ConfirmDialog, InputDialog } from "../components/ui/Dialog";
import type { Plugin } from "../lib/types";

export default function PluginLibrary() {
  const navigate = useNavigate();
  const allPlugins = useAppStore((s) => s.plugins);
  const filter = useAppStore((s) => s.filter);
  const plugins = useMemo(() => {
    let result = allPlugins;
    switch (filter) {
      case "INSTRUMENTS": result = result.filter((p) => p.type === "instrument"); break;
      case "EFFECTS": result = result.filter((p) => p.type === "effect"); break;
      case "UTILITIES": result = result.filter((p) => p.type === "utility"); break;
    }
    return [...result].sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
  }, [allPlugins, filter]);
  const setFilter = useAppStore((s) => s.setFilter);
  const deletePlugin = useAppStore((s) => s.deletePlugin);
  const renamePlugin = useAppStore((s) => s.renamePlugin);
  const buildProgress = useBuildStore((s) => s.progress);

  const [selectedPlugin, setSelectedPlugin] = useState<Plugin | null>(null);
  const [pluginToDelete, setPluginToDelete] = useState<string | null>(null);
  const [pluginToRename, setPluginToRename] = useState<Plugin | null>(null);
  const [renameText, setRenameText] = useState("");

  return (
    <div className="flex flex-col h-full">
      {/* Filter bar */}
      <div className="flex items-center h-[44px] px-4 bg-[var(--color-bg-bar)] border-b border-[var(--color-border)] shrink-0">
        <FilterTabBar activeFilter={filter} onTap={setFilter} />
        <div className="flex-1" />
        <div className="flex items-center gap-1">
          <button onClick={() => navigate("/queue")} className="p-1.5 text-[var(--color-text-muted)] hover:text-[var(--color-text-secondary)]">
            <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085" />
            </svg>
          </button>
          <button onClick={() => navigate("/settings")} className="p-1.5 text-[var(--color-text-muted)] hover:text-[var(--color-text-secondary)]">
            <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          </button>
        </div>
      </div>

      {/* Plugin grid */}
      <div className="flex-1 overflow-y-auto">
        <div className="grid gap-px bg-[var(--color-border)]" style={{ gridTemplateColumns: "repeat(5, 1fr)" }}>
          <button
            onClick={() => navigate("/prompt")}
            className="bg-[var(--color-bg-text)] flex flex-col items-center justify-center gap-2 min-h-[340px] hover:bg-[var(--color-bg-elevated)] transition-colors"
          >
            <svg className="w-[18px] h-[18px] text-[var(--color-text-secondary)]" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            <span className="text-[10px] font-[var(--font-mono)] tracking-[2px] text-[var(--color-text-secondary)]">NEW PLUGIN</span>
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

      {/* Plugin detail sheet */}
      {selectedPlugin && (
        <PluginDetailView
          plugin={selectedPlugin}
          onDismiss={() => setSelectedPlugin(null)}
          onDelete={() => { setPluginToDelete(selectedPlugin.id); setSelectedPlugin(null); }}
          onRename={() => { setPluginToRename(selectedPlugin); setRenameText(selectedPlugin.name); setSelectedPlugin(null); }}
        />
      )}

      {/* Delete confirmation */}
      <ConfirmDialog
        open={!!pluginToDelete}
        title="Delete Plugin?"
        message="This will uninstall the AU/VST3 files from your system. This cannot be undone."
        confirmLabel="Delete"
        destructive
        onConfirm={() => { if (pluginToDelete) deletePlugin(pluginToDelete); setPluginToDelete(null); }}
        onCancel={() => setPluginToDelete(null)}
      />

      {/* Rename dialog */}
      <InputDialog
        open={!!pluginToRename}
        title="Rename Plugin"
        value={renameText}
        onChange={setRenameText}
        confirmLabel="Rename"
        onConfirm={() => { if (pluginToRename && renameText.trim()) { renamePlugin(pluginToRename.id, renameText.trim()); setPluginToRename(null); } }}
        onCancel={() => setPluginToRename(null)}
      />
    </div>
  );
}
