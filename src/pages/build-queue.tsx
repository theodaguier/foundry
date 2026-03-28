import { useMemo, useState } from "react"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { cn, formatTime, generationStepLabel, pluginTypeDisplayName } from "@/lib/utils"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Separator } from "@/components/ui/separator"
import { Hammer, RotateCcw } from "lucide-react"

function summarizeError(message?: string) {
  if (!message) return "Generation failed."
  return message.replace(/\s+/g, " ").trim()
}

export default function BuildQueue() {
  const plugins = useAppStore((s) => s.plugins)
  const setMainView = useAppStore((s) => s.setMainView)
  const isRunning = useBuildStore((s) => s.isRunning)
  const activePluginId = useBuildStore((s) => s.activePluginId)
  const currentStep = useBuildStore((s) => s.currentStep)
  const progress = useBuildStore((s) => s.progress)
  const elapsedSeconds = useBuildStore((s) => s.elapsedSeconds)
  const generatedPluginName = useBuildStore((s) => s.generatedPluginName)
  const config = useBuildStore((s) => s.config)
  const refineConfig = useBuildStore((s) => s.refineConfig)
  const retryPlugin = useBuildStore((s) => s.retryPlugin)

  const [retryingId, setRetryingId] = useState<string | null>(null)

  const buildPlugins = useMemo(
    () =>
      [...plugins]
        .filter((plugin) => plugin.status === "building" || plugin.status === "failed")
        .sort((a, b) => {
          if (a.status !== b.status) return a.status === "building" ? -1 : 1
          return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
        }),
    [plugins],
  )

  const hasPersistedActiveBuild = buildPlugins.some((p) => p.status === "building")

  const handleRetry = async (pluginId: string) => {
    const plugin = buildPlugins.find((item) => item.id === pluginId)
    if (!plugin) return
    setRetryingId(pluginId)
    setMainView({ kind: "generation" })
    try {
      await retryPlugin(plugin)
    } finally {
      setRetryingId((current) => (current === pluginId ? null : current))
    }
  }

  if (!isRunning && buildPlugins.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-2">
        <Hammer className="size-6 text-muted-foreground/20" />
        <p className="text-[11px] text-muted-foreground/40">No recent builds</p>
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full overflow-y-auto">
      <div className="px-6 pt-6 pb-3 shrink-0">
        <span className="text-lg font-[ArchitypeStedelijk] uppercase tracking-[1px]">Builds</span>
      </div>

      <div className="px-6 pb-6 flex flex-col">
        {/* Ephemeral active build (not yet persisted) */}
        {isRunning && !hasPersistedActiveBuild && (
          <>
            <div className="flex items-center gap-3 py-3">
              <div className="flex-1 min-w-0">
                <div className="text-xs truncate">
                  {generatedPluginName || refineConfig?.plugin.name || config?.prompt.slice(0, 40) || "Building..."}
                </div>
                <div className="text-[10px] text-muted-foreground/50 mt-0.5">
                  {generationStepLabel(currentStep, !!refineConfig)} · {formatTime(elapsedSeconds)}
                </div>
              </div>
              <Badge variant="outline">{Math.round(progress * 100)}%</Badge>
              <Button
                variant="ghost"
                size="xs"
                onClick={() => setMainView({ kind: refineConfig ? "refinement" : "generation" })}
              >
                Open
              </Button>
            </div>
            {buildPlugins.length > 0 && <Separator />}
          </>
        )}

        {buildPlugins.map((plugin, i) => {
          const isActive = plugin.status === "building" && (activePluginId === plugin.id || !activePluginId)
          const canRetry = !!plugin.generationConfig || !!plugin.prompt

          return (
            <div key={plugin.id}>
              {i > 0 && <Separator />}
              <div className="flex items-center gap-3 py-3">
                {/* Info */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-xs truncate">{plugin.name}</span>
                    <span className="text-[9px] text-muted-foreground/40 shrink-0">
                      {pluginTypeDisplayName(plugin.type)} · {plugin.formats.join(" / ")}
                    </span>
                  </div>
                  {isActive ? (
                    <div className="text-[10px] text-muted-foreground/50 mt-0.5">
                      {generationStepLabel(currentStep, false)} · {formatTime(elapsedSeconds)}
                    </div>
                  ) : plugin.status === "failed" ? (
                    <div className="text-[10px] text-destructive/70 mt-0.5 truncate">
                      {summarizeError(plugin.lastErrorMessage)}
                    </div>
                  ) : null}
                  {plugin.prompt && (
                    <div className="text-[9px] text-muted-foreground/30 mt-0.5 truncate">
                      {plugin.prompt}
                    </div>
                  )}
                </div>

                {/* Status + actions */}
                <Badge variant={plugin.status === "failed" ? "destructive" : "outline"} className="shrink-0">
                  {plugin.status === "failed" ? "Failed" : `${Math.round(progress * 100)}%`}
                </Badge>

                {plugin.status === "failed" ? (
                  <div className="flex items-center gap-1 shrink-0">
                    <Button
                      variant="ghost"
                      size="xs"
                      onClick={() => setMainView({ kind: "detail", pluginId: plugin.id })}
                    >
                      Open
                    </Button>
                    <Button
                      size="xs"
                      disabled={!canRetry || isRunning || retryingId === plugin.id}
                      onClick={() => void handleRetry(plugin.id)}
                    >
                      <RotateCcw className="size-3" />
                      Retry
                    </Button>
                  </div>
                ) : (
                  <Button
                    variant="ghost"
                    size="xs"
                    className="shrink-0"
                    onClick={() => setMainView({ kind: "generation" })}
                  >
                    Open
                  </Button>
                )}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
