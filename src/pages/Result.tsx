import { useNavigate, useParams } from "react-router-dom"
import { useAppStore } from "@/stores/app-store"
import { pluginTypeDisplayName } from "@/lib/utils"
import { showInFinder } from "@/lib/commands"
import { Button } from "@/components/ui/button"
import { Separator } from "@/components/ui/separator"
import { PluginArtworkView } from "@/components/app/plugin-artwork-view"
import { InfoRow } from "@/components/app/info-row"

export default function Result() {
  const navigate = useNavigate()
  const { pluginId } = useParams()
  const plugins = useAppStore((s) => s.plugins)
  const plugin = plugins.find((p) => p.id === pluginId)

  if (!plugin) return <div className="flex items-center justify-center h-full text-muted-foreground/60">Plugin not found</div>

  const typeFormats = `${pluginTypeDisplayName(plugin.type).toUpperCase()} · ${plugin.formats.join(" / ")}`

  const openFinder = () => {
    const path = plugin.installPaths.vst3 || plugin.installPaths.au
    if (path) showInFinder(path)
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-[680px] mx-auto">
        <div className="h-[240px] relative overflow-hidden">
          <PluginArtworkView plugin={plugin} />
          <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-background to-transparent px-8 pb-6 pt-16">
            <span className="text-[9px] font-mono tracking-[1.2px] text-muted-foreground uppercase">{typeFormats}</span>
            <h1 className="text-[32px] font-[ArchitypeStedelijk] tracking-[1px] text-foreground uppercase truncate leading-tight">{plugin.name}</h1>
          </div>
        </div>

        <div>
          <InfoRow label="PROMPT" value={plugin.prompt} />
          <Separator />
          <InfoRow label="TYPE" value={pluginTypeDisplayName(plugin.type)} />
          <Separator />
          <InfoRow label="FORMATS" value={plugin.formats.join(" / ")} />
          {plugin.installPaths.au && (<><Separator /><InfoRow label="AU PATH" value={plugin.installPaths.au} /></>)}
          {plugin.installPaths.vst3 && (<><Separator /><InfoRow label="VST3 PATH" value={plugin.installPaths.vst3} /></>)}
        </div>

        <div className="flex items-center gap-3 px-8 py-6">
          <Button variant="secondary" onClick={openFinder}>Show in Finder</Button>
          <Button variant="secondary" onClick={() => navigate(`/refine/${plugin.id}`)} disabled={!plugin.buildDirectory}>Refine</Button>
          <div className="flex-1" />
          <Button size="lg" onClick={() => navigate("/")}>Done</Button>
        </div>
      </div>
    </div>
  )
}
