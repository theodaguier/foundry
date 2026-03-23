import { useNavigate } from "react-router-dom"
import { useBuildStore } from "@/stores/build-store"
import { formatTime, generationStepLabel } from "@/lib/utils"
import { Button } from "@/components/ui/button"

export default function BuildQueue() {
  const navigate = useNavigate()
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

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between px-5 py-4 border-b border-border shrink-0">
        <span className="text-[13px] font-medium">Builds</span>
        <Button variant="ghost" size="sm" onClick={() => navigate("/")}>Done</Button>
      </div>

      {/* List */}
      {!isRunning ? (
        <div className="flex-1 flex items-center justify-center">
          <span className="text-[13px] text-muted-foreground/40">No active builds</span>
        </div>
      ) : (
        <button
          className="flex flex-col gap-1 px-5 py-3.5 border-b border-border text-left hover:bg-muted/30 transition-colors w-full"
          onClick={() => navigate(isRefine ? "/refinement" : "/generation")}
        >
          <div className="flex items-center gap-2">
            <div className="w-2.5 h-2.5 border-[1.5px] border-foreground border-t-transparent rounded-full animate-spin shrink-0" />
            <span className="text-[15px] font-[ArchitypeStedelijk] flex-1 truncate">{displayName}</span>
            <span className="text-[11px] text-muted-foreground/50 font-mono tabular-nums">{formatTime(elapsedSeconds)}</span>
          </div>
          <div className="flex items-center gap-2 pl-[18px]">
            <span className="text-[11px] text-muted-foreground/50 flex-1">{generationStepLabel(currentStep, isRefine)}</span>
            <span className="text-[11px] text-muted-foreground/40 font-mono">{Math.round(progress * 100)}%</span>
          </div>
          <div className="h-px bg-border rounded-full overflow-hidden mt-1 ml-[18px]">
            <div
              className="h-full bg-muted-foreground/40 rounded-full transition-all duration-500"
              style={{ width: `${progress * 100}%` }}
            />
          </div>
        </button>
      )}
    </div>
  )
}
