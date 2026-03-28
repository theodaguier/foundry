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
import { ArrowUp } from "lucide-react"
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
      <div className="w-full flex flex-col py-8 px-6">
        <div className="flex flex-col items-center gap-2 mb-8">
          <span className="text-[10px] uppercase tracking-[2px] text-muted-foreground/40">Refine</span>
          <h1 className="text-xl font-[ArchitypeStedelijk] tracking-[0.5px] uppercase text-foreground">
            {plugin.name}
          </h1>
          <p className="text-[12px] text-muted-foreground text-center max-w-xs">
            Describe what to change. Foundry will modify the source code and rebuild.
          </p>
        </div>

        <div className="mb-6">
          <div className="relative">
            <Textarea
              value={modification}
              onChange={(e) => setModification(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && e.metaKey) refine() }}
              placeholder="Add a low-pass filter with resonance control..."
              autoFocus
              rows={4}
              className="min-h-[100px] resize-none pr-12 rounded-xl"
            />
            <Button
              size="icon-sm"
              onClick={refine}
              disabled={isEmpty}
              className="absolute right-2.5 bottom-2.5 rounded-lg disabled:bg-muted disabled:text-muted-foreground"
            >
              <ArrowUp className="size-4" />
            </Button>
          </div>

          <div className="flex items-center gap-1.5 mt-2">
            <DropdownMenu>
              <DropdownMenuTrigger
                render={
                  <Button variant="ghost" size="sm" className="gap-1.5 text-[11px] text-muted-foreground hover:text-foreground">
                    <AgentIcon agent={selectedAgent} className="size-3.5" />
                    <span>{selectedModel}</span>
                  </Button>
                }
              />
              <DropdownMenuContent align="start" className="min-w-[200px] w-auto">
                {modelCatalog.length === 0 ? (
                  <div className="px-3 py-3 text-[11px] text-muted-foreground">
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
                        className={model.flag === selectedModel || model.id === selectedModel ? "text-foreground" : ""}
                      >
                        <span className="text-[12px]">{model.name}</span>
                        <span className="text-muted-foreground/50 text-[10px] ml-1">{model.subtitle}</span>
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuGroup>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>

            <div className="flex-1" />

            <Button
              variant="ghost"
              size="sm"
              onClick={() => setMainView({ kind: "detail", pluginId: plugin.id })}
              className="text-[11px] text-muted-foreground"
            >
              Cancel
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
