import { useState } from "react"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { useSettingsStore } from "@/stores/settings-store"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuGroup,
  DropdownMenuLabel,
} from "@/components/ui/dropdown-menu"
import { AgentIcon } from "@/components/app/agent-icon"
import { Wrench } from "lucide-react"
import type { Plugin } from "@/lib/types"

interface Props {
  plugin: Plugin
}

export default function Refine({ plugin }: Props) {
  const setMainView = useAppStore((s) => s.setMainView)
  const startRefine = useBuildStore((s) => s.startRefine)
  const modelCatalog = useSettingsStore((s) => s.modelCatalog)
  const [modification, setModification] = useState("")
  const [selectedAgent, setSelectedAgent] = useState(plugin.agent ?? "Claude Code")
  const [selectedModel, setSelectedModel] = useState(plugin.model?.flag ?? plugin.model?.id ?? "sonnet")

  const isEmpty = !modification.trim()

  const refine = async () => {
    if (isEmpty) return
    setMainView({ kind: "refinement" })
    void startRefine({ plugin, modification: modification.trim() })
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-[520px] mx-auto flex flex-col py-8 px-6">
        <div className="flex flex-col items-center gap-2.5 mb-8">
          <Wrench className="size-12 text-muted-foreground" strokeWidth={1} />
          <span className="text-sm text-muted-foreground">Modify {plugin.name}</span>
        </div>

        <div className="mb-6">
          <Textarea
            value={modification}
            onChange={(e) => setModification(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && e.metaKey) refine() }}
            placeholder="Add a low-pass filter with resonance control..."
            autoFocus
            rows={5}
            className="min-h-[100px] resize-none font-mono text-[14px]"
          />

          <div className="flex items-center gap-1.5 mt-2.5">
            <DropdownMenu>
              <DropdownMenuTrigger
                render={
                  <Button variant="secondary" size="sm" className="gap-1.5 text-[12px]">
                    <AgentIcon agent={selectedAgent} className="size-3.5" />
                    <span>{selectedModel}</span>
                  </Button>
                }
              />
              <DropdownMenuContent align="start" className="min-w-[200px] w-auto">
                {modelCatalog.length === 0 ? (
                  <div className="px-3 py-3 text-xs text-muted-foreground">
                    No agent CLI installed.
                  </div>
                ) : modelCatalog.map((provider) => (
                  <DropdownMenuGroup key={provider.id}>
                    <DropdownMenuLabel className="flex items-center gap-1.5 text-[9px] tracking-[1px] text-muted-foreground/60 uppercase">
                      <AgentIcon agent={provider.name} className="size-3" />
                      {provider.name}
                    </DropdownMenuLabel>
                    {provider.models.map((model) => (
                      <DropdownMenuItem
                        key={model.id}
                        onClick={() => { setSelectedAgent(provider.name); setSelectedModel(model.flag || model.id) }}
                        className={selectedModel === (model.flag || model.id) ? "text-primary" : ""}
                      >
                        <span>{model.name}</span>
                        <span className="text-muted-foreground/60 text-[10px]">— {model.subtitle}</span>
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuGroup>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>

            <div className="flex-1" />

            <Button variant="ghost" size="sm" onClick={() => setMainView({ kind: "detail", pluginId: plugin.id })}>
              Cancel
            </Button>
            <Button size="sm" onClick={refine} disabled={isEmpty}>
              Refine
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
