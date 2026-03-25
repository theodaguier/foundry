import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { formatTime, generationStepLabel } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Hammer } from "lucide-react"

export default function BuildQueue() {
  const setMainView = useAppStore((s) => s.setMainView)
  const isRunning = useBuildStore((s) => s.isRunning)
  const generatedPluginName = useBuildStore((s) => s.generatedPluginName)
  const config = useBuildStore((s) => s.config)
  const refineConfig = useBuildStore((s) => s.refineConfig)
  const currentStep = useBuildStore((s) => s.currentStep)
  const progress = useBuildStore((s) => s.progress)
  const elapsedSeconds = useBuildStore((s) => s.elapsedSeconds)

  const isRefine = !!refineConfig
  const displayName = generatedPluginName
    || refineConfig?.plugin.name
    || config?.prompt.slice(0, 48)
    || "Building…"

  if (!isRunning) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-3">
        <Hammer className="size-9 text-muted-foreground/30" />
        <p className="text-sm text-muted-foreground/50">
          No active builds
        </p>
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full">
      <div className="px-5 py-4 shrink-0">
        <span className="text-sm font-[ArchitypeStedelijk] uppercase tracking-[0.5px]">Builds</span>
      </div>

      <Button
        variant="ghost"
        className="flex flex-col items-stretch gap-1 px-5 py-3.5 h-auto rounded-none w-full"
        onClick={() => setMainView({ kind: isRefine ? "refinement" : "generation" })}
      >
        <div className="flex items-center gap-2">
          <div className="w-2.5 h-2.5 border-[1.5px] border-foreground border-t-transparent rounded-full animate-spin shrink-0" />
          <span className="text-[15px] font-[ArchitypeStedelijk] flex-1 truncate text-left">{displayName}</span>
          <span className="text-[11px] text-muted-foreground/50 font-mono tabular-nums">{formatTime(elapsedSeconds)}</span>
        </div>
        <div className="flex items-center gap-2 pl-[18px]">
          <span className="text-[11px] text-muted-foreground/50 flex-1 text-left">{generationStepLabel(currentStep, isRefine)}</span>
          <span className="text-[11px] text-muted-foreground/40 font-mono">{Math.round(progress * 100)}%</span>
        </div>
        <div className="h-px bg-muted rounded-full overflow-hidden mt-1 ml-[18px]">
          <div
            className="h-full bg-muted-foreground/40 rounded-full transition-all duration-500"
            style={{ width: `${progress * 100}%` }}
          />
        </div>
      </Button>
    </div>
  )
}
