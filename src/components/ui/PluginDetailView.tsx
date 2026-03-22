import { useNavigate } from "react-router-dom";
import type { Plugin } from "../../lib/types";
import { pluginTypeDisplayName } from "../../lib/utils";
import { showInFinder } from "../../lib/commands";
import PluginArtworkView from "./PluginArtworkView";
import Button from "./Button";
import InfoRow from "./InfoRow";
import Separator from "./Separator";
import { Menu, MenuItem, MenuSeparator } from "./Menu";

interface Props {
  plugin: Plugin;
  onDismiss: () => void;
  onDelete: () => void;
  onRename: () => void;
}

export default function PluginDetailView({ plugin, onDismiss, onDelete, onRename }: Props) {
  const navigate = useNavigate();

  const typeFormats = `${pluginTypeDisplayName(plugin.type).toUpperCase()} · ${plugin.formats.join(" / ")}`;

  const openFinder = () => {
    const path = plugin.installPaths.vst3 || plugin.installPaths.au;
    if (path) showInFinder(path);
  };

  const handleRefine = () => {
    onDismiss();
    navigate(`/refine/${plugin.id}`);
  };

  const createdDate = new Date(plugin.createdAt).toLocaleDateString("en-US", {
    month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit",
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={onDismiss}>
      <div className="w-[520px] bg-[var(--color-bg-window)] shadow-2xl overflow-hidden" onClick={(e) => e.stopPropagation()}>
        {/* Artwork */}
        <div className="h-[200px] relative overflow-hidden">
          <PluginArtworkView plugin={plugin} />
          <div className="absolute bottom-0 left-0 right-0 px-6 pb-5 pt-20 bg-gradient-to-t from-[var(--color-bg-window)] via-[var(--color-bg-window)]/50 to-transparent">
            <span className="text-[9px] font-[var(--font-mono)] tracking-[1.2px] text-[var(--color-text-secondary)] uppercase block">
              {typeFormats}
            </span>
            <h1 className="text-[32px] font-[ArchitypeStedelijk] tracking-[1px] text-[var(--color-text-primary)] uppercase truncate leading-tight">
              {plugin.name}
            </h1>
          </div>
          <Separator className="absolute bottom-0 left-0 right-0" />
        </div>

        {/* Info rows */}
        <div className="bg-[var(--color-bg-window)]">
          <InfoRow label="PROMPT" value={plugin.prompt} />
          <Separator />
          <InfoRow label="CREATED" value={createdDate} />
          {plugin.installPaths.au && (<><Separator /><InfoRow label="AU PATH" value={plugin.installPaths.au} /></>)}
          {plugin.installPaths.vst3 && (<><Separator /><InfoRow label="VST3 PATH" value={plugin.installPaths.vst3} /></>)}
          <Separator />
        </div>

        {/* Version section */}
        {plugin.versions.length > 0 && (
          <>
            <div className="flex items-center px-6 py-3 bg-[var(--color-bg-window)]">
              <span className="text-[9px] font-[var(--font-mono)] tracking-[1.2px] text-[var(--color-text-muted)] uppercase">Version</span>
              <div className="flex-1" />
              <span className="text-[11px] font-[var(--font-mono)] text-[var(--color-text-secondary)]">v{plugin.currentVersion}</span>
              <span className="text-[var(--color-text-faint)] mx-1">·</span>
              <span className="text-[11px] font-[var(--font-mono)] text-[var(--color-text-muted)]">
                {plugin.versions.length} version{plugin.versions.length === 1 ? "" : "s"}
              </span>
            </div>
            <Separator />
          </>
        )}

        {/* Actions */}
        <div className="flex items-center gap-3 px-6 py-4">
          <Menu
            trigger={
              <button className="flex items-center gap-1.5 px-3 py-1.5 text-[var(--color-text-secondary)] bg-[var(--color-bg-text)] border border-[var(--color-border)] rounded">
                <span className="text-[11px] font-medium">···</span>
                <span className="text-[9px] font-[var(--font-mono)] tracking-[1.2px] uppercase">Actions</span>
              </button>
            }
          >
            <MenuItem label="Show in Finder" onClick={openFinder} />
            <MenuItem label="Rename" onClick={onRename} />
            <MenuItem label="Refine" onClick={handleRefine} disabled={!plugin.buildDirectory} />
            <MenuSeparator />
            <MenuItem label="Delete" onClick={onDelete} destructive />
          </Menu>

          <div className="flex-1" />
          <Button variant="primary" size="lg" onClick={onDismiss}>Done</Button>
        </div>
      </div>
    </div>
  );
}
