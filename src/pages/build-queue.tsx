import { useMemo, useState } from "react"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { formatTime, generationStepLabel, pluginTypeDisplayName } from "@/lib/utils"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Hammer, RotateCcw, TriangleAlert } from "lucide-react"

function summarizeError(message?: string) {
  if (!message) return "Generation failed before Foundry could save a detailed error."
  return message.replace(/\s+/g, " ").trim()
}

function ActiveBuildFallback() {
  const setMainView = useAppStore((s) => s.setMainView)
  const generatedPluginName = useBuildStore((s) => s.generatedPluginName)
  const config = useBuildStore((s) => s.config)
  const refineConfig = useBuildStore((s) => s.refineConfig)
  const currentStep = useBuildStore((s) => s.currentStep)
  const progress = useBuildStore((s) => s.progress)
  const elapsedSeconds = useBuildStore((s) => s.elapsedSeconds)

  const isRefine = !!refineConfig
  const displayName =
    generatedPluginName ||
    refineConfig?.plugin.name ||
    config?.prompt.slice(0, 48) ||
    "Building..."

  return (
    <Card size="sm">
      <CardContent className="flex flex-col gap-3 py-4">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="text-sm font-[ArchitypeStedelijk] uppercase tracking-[0.5px] truncate">
              {displayName}
            </div>
            <div className="text-xs text-muted-foreground mt-1">
              {generationStepLabel(currentStep, isRefine)}
            </div>
          </div>
          <Badge variant="outline">{Math.round(progress * 100)}%</Badge>
        </div>

        <div className="h-px bg-muted rounded-full overflow-hidden">
          <div
            className="h-full bg-muted-foreground/40 rounded-full transition-all duration-500"
            style={{ width: `${progress * 100}%` }}
          />
        </div>

        <div className="flex items-center justify-between gap-3">
          <span className="text-xs text-muted-foreground">Build is starting up...</span>
          <Button variant="ghost" size="sm" onClick={() => setMainView({ kind: isRefine ? "refinement" : "generation" })}>
            Open
          </Button>
        </div>

        <div className="text-[11px] text-muted-foreground/60 font-mono">
          {formatTime(elapsedSeconds)}
        </div>
      </CardContent>
    </Card>
  )
}

export default function BuildQueue() {
  const plugins = useAppStore((s) => s.plugins)
  const setMainView = useAppStore((s) => s.setMainView)
  const isRunning = useBuildStore((s) => s.isRunning)
  const activePluginId = useBuildStore((s) => s.activePluginId)
  const currentStep = useBuildStore((s) => s.currentStep)
  const progress = useBuildStore((s) => s.progress)
  const elapsedSeconds = useBuildStore((s) => s.elapsedSeconds)
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

  const hasPersistedActiveBuild = buildPlugins.some((plugin) => plugin.status === "building")

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
      <div className="flex flex-col items-center justify-center h-full gap-3">
        <Hammer className="size-9 text-muted-foreground/30" />
        <p className="text-sm text-muted-foreground/50">No recent builds</p>
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full overflow-y-auto">
      <div className="px-5 py-4 shrink-0">
        <span className="text-sm font-[ArchitypeStedelijk] uppercase tracking-[0.5px]">Builds</span>
      </div>

      <div className="px-5 pb-5 flex flex-col gap-3">
        {isRunning && !hasPersistedActiveBuild && <ActiveBuildFallback />}

        {buildPlugins.map((plugin) => {
          const isActive = plugin.status === "building" && (activePluginId === plugin.id || !activePluginId)
          const canRetry = !!plugin.generationConfig || !!plugin.prompt

          return (
            <Card key={plugin.id} size="sm">
              <CardContent className="flex flex-col gap-3 py-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="text-sm font-[ArchitypeStedelijk] uppercase tracking-[0.5px] truncate">
                      {plugin.name}
                    </div>
                    <div className="text-xs text-muted-foreground mt-1 truncate">
                      {pluginTypeDisplayName(plugin.type)} · {plugin.formats.join(" / ")}
                    </div>
                  </div>

                  <Badge variant={plugin.status === "failed" ? "destructive" : "outline"}>
                    {plugin.status === "failed" ? "Failed" : "Building"}
                  </Badge>
                </div>

                <div className="text-xs text-muted-foreground leading-relaxed">
                  {isActive
                    ? generationStepLabel(currentStep, false)
                    : summarizeError(plugin.lastErrorMessage)}
                </div>

                {isActive && (
                  <>
                    <div className="h-px bg-muted rounded-full overflow-hidden">
                      <div
                        className="h-full bg-muted-foreground/40 rounded-full transition-all duration-500"
                        style={{ width: `${progress * 100}%` }}
                      />
                    </div>
                    <div className="flex items-center justify-between gap-3 text-[11px] text-muted-foreground/60 font-mono">
                      <span>{Math.round(progress * 100)}%</span>
                      <span>{formatTime(elapsedSeconds)}</span>
                    </div>
                  </>
                )}

                <div className="flex items-center justify-between gap-3">
                  <div className="text-[11px] text-muted-foreground/60 truncate">
                    {plugin.prompt}
                  </div>

                  <div className="flex items-center gap-2 shrink-0">
                    {plugin.status === "failed" ? (
                      <>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => setMainView({ kind: "detail", pluginId: plugin.id })}
                        >
                          Open
                        </Button>
                        <Button
                          size="sm"
                          disabled={!canRetry || isRunning || retryingId === plugin.id}
                          onClick={() => void handleRetry(plugin.id)}
                        >
                          <RotateCcw className="size-3.5" />
                          {retryingId === plugin.id ? "Retrying..." : "Retry"}
                        </Button>
                      </>
                    ) : (
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setMainView({ kind: "generation" })}
                      >
                        Open
                      </Button>
                    )}
                  </div>
                </div>

                {plugin.status === "failed" && plugin.lastErrorMessage && (
                  <div className="flex items-start gap-2 rounded-lg bg-destructive/5 border border-destructive/10 px-3 py-2">
                    <TriangleAlert className="size-3.5 mt-0.5 text-destructive/70 shrink-0" />
                    <div className="text-[11px] text-muted-foreground break-words">
                      {summarizeError(plugin.lastErrorMessage)}
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          )
        })}
      </div>
    </div>
  )
}
