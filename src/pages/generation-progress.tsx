import { useState, useEffect, useRef, useLayoutEffect } from "react"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { cn, formatTime, generationStepLabel } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog"
import { CheckCircle2, Circle, Loader2, Terminal, ArrowLeft, X } from "lucide-react"
import type { AgentModel, GenerationStep } from "@/lib/types"
import { GenerationFeedback } from "@/components/app/generation-feedback"

const STEP_ORDER: Record<GenerationStep, number> = {
  preparingEnvironment: 0,
  preparingProject: 1,
  generating: 2,
  compiling: 3,
  installing: 4,
}

const GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const ALL_STEPS: GenerationStep[] = [
  "preparingEnvironment",
  "preparingProject",
  "generating",
  "compiling",
  "installing",
]
const REFINE_STEPS: GenerationStep[] = [
  "preparingEnvironment",
  "generating",
  "compiling",
  "installing",
]

function NameScramble({ targetName }: { targetName: string | null }) {
  const [slots, setSlots] = useState<{ char: string; locked: boolean }[]>(
    Array.from({ length: 7 }, () => ({
      char: GLYPHS[Math.floor(Math.random() * 26)],
      locked: false,
    })),
  )
  const resolved = useRef(false)

  useEffect(() => {
    if (resolved.current) return
    const interval = setInterval(() => {
      setSlots((prev) =>
        prev.map((s) =>
          s.locked ? s : { ...s, char: GLYPHS[Math.floor(Math.random() * 26)] },
        ),
      )
    }, 80)
    return () => clearInterval(interval)
  }, [])

  useEffect(() => {
    if (!targetName || resolved.current) return
    const target = targetName.toUpperCase().split("")
    setSlots((prev) => {
      const newSlots = [...prev]
      while (newSlots.length < target.length)
        newSlots.push({
          char: GLYPHS[Math.floor(Math.random() * 26)],
          locked: false,
        })
      return newSlots.slice(0, target.length)
    })

    target.forEach((ch, i) => {
      setTimeout(
        () => {
          setSlots((prev) =>
            prev.map((s, j) => (j === i ? { char: ch, locked: true } : s)),
          )
          if (i === target.length - 1) resolved.current = true
        },
        i * 120 + 150,
      )
    })
  }, [targetName])

  return (
    <div className="flex gap-[2px] h-[44px] items-center justify-center">
      {slots.map((slot, i) => (
        <span
          key={i}
          className={cn(
            "text-[36px] font-[ArchitypeStedelijk] transition-all duration-300",
            slot.locked ? "text-foreground" : "text-muted-foreground/20 blur-[1px]",
          )}
        >
          {slot.char}
        </span>
      ))}
    </div>
  )
}

function ConsolePanel({
  logLines,
  streamingText,
  modelMeta,
  buildAttempt,
  elapsedSeconds,
  logStyleClass,
}: {
  logLines: { timestamp: string; message: string; style?: string }[]
  streamingText: string
  modelMeta: { agentLabel: string; modelLabel: string; stepLabel: string }
  buildAttempt: number
  elapsedSeconds: number
  logStyleClass: (style?: string) => string
}) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const isAtBottom = useRef(true)

  const handleScroll = () => {
    const el = scrollRef.current
    if (!el) return
    isAtBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 40
  }

  useLayoutEffect(() => {
    const el = scrollRef.current
    if (el && isAtBottom.current) {
      el.scrollTop = el.scrollHeight
    }
  }, [logLines, streamingText])

  return (
    <div className="flex-1 flex flex-col bg-card/50">
      <div className="flex items-center justify-between px-3 py-2 border-b border-border/50">
        <div className="flex items-center gap-2 text-[9px] text-muted-foreground/40">
          <span>{modelMeta.agentLabel}</span>
          <span>·</span>
          <span>{modelMeta.modelLabel}</span>
          <span>·</span>
          <span>{modelMeta.stepLabel}</span>
          {buildAttempt > 0 && <><span>·</span><span>attempt {buildAttempt}</span></>}
        </div>
        <span className="text-[9px] text-muted-foreground/30 tabular-nums">{formatTime(elapsedSeconds)}</span>
      </div>
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto px-3 py-2 space-y-1"
      >
        {streamingText && (
          <div className="text-[10px] text-foreground/70 whitespace-pre-wrap break-words leading-relaxed pb-2 mb-2 border-b border-border/30">
            {streamingText}
          </div>
        )}
        {logLines.map((line, i) => (
          <div key={i} className="flex gap-2 text-[9px] leading-4">
            <span className="text-muted-foreground/20 shrink-0 tabular-nums">{line.timestamp}</span>
            <span className={cn("break-words whitespace-pre-wrap", logStyleClass(line.style))}>{line.message}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

interface Props {
  mode: "generation" | "refinement"
}

export default function GenerationProgress({ mode }: Props) {
  const setMainView = useAppStore((s) => s.setMainView)
  const currentStep = useBuildStore((s) => s.currentStep)
  const completedSteps = useBuildStore((s) => s.completedSteps)
  const showConsole = useBuildStore((s) => s.showConsole)
  const generatedPluginName = useBuildStore((s) => s.generatedPluginName)
  const progress = useBuildStore((s) => s.progress)
  const elapsedSeconds = useBuildStore((s) => s.elapsedSeconds)
  const logLines = useBuildStore((s) => s.logLines)
  const streamingText = useBuildStore((s) => s.streamingText)
  const buildAttempt = useBuildStore((s) => s.buildAttempt)
  const config = useBuildStore((s) => s.config)
  const isRunning = useBuildStore((s) => s.isRunning)
  const lastCompletedTelemetryId = useBuildStore((s) => s.lastCompletedTelemetryId)
  const refineConfig = useBuildStore((s) => s.refineConfig)
  const setShowConsole = useBuildStore((s) => s.setShowConsole)
  const reset = useBuildStore((s) => s.reset)
  const cancel = useBuildStore((s) => s.cancel)

  const [showCancel, setShowCancel] = useState(false)
  const isRefine = mode === "refinement"
  const steps = isRefine ? REFINE_STEPS : ALL_STEPS

  const modelMeta = (() => {
    const selectedModel: AgentModel | null = refineConfig?.plugin.model ?? null
    const agentLabel = config?.agent ?? refineConfig?.plugin.agent ?? "claude-code"
    const modelLabel = config?.model ?? selectedModel?.name ?? selectedModel?.flag ?? "unknown-model"
    return {
      agentLabel,
      modelLabel,
      stepLabel: generationStepLabel(currentStep, isRefine),
    }
  })()

  const logStyleClass = (style?: string) => {
    switch (style) {
      case "success": return "text-success"
      case "error": return "text-destructive"
      case "active": return "text-foreground"
      default: return "text-muted-foreground/70"
    }
  }

  return (
    <div className="flex h-full">
      <div className="flex-1 flex flex-col">
        {/* Top bar — actions */}
        <div className="flex items-center justify-end gap-1 px-2 pt-1.5 shrink-0">
          <Button variant="secondary" size="icon" onClick={() => setShowConsole(!showConsole)}>
            <Terminal />
          </Button>
          <Button variant="secondary" size="icon" onClick={() => setMainView({ kind: "empty" })}>
            <ArrowLeft />
          </Button>
          <Button variant="secondary" size="icon" onClick={() => setShowCancel(true)} className="text-destructive/70 hover:text-destructive">
            <X />
          </Button>
        </div>

        {/* Center content */}
        <div className="flex-1 flex flex-col items-center justify-center p-6">
          <div className="flex flex-col gap-8 w-full max-w-sm">
            {!isRefine ? (
              <NameScramble targetName={generatedPluginName} />
            ) : (
              <div className="text-center">
                <span className="text-[10px] uppercase tracking-[2px] text-muted-foreground/50">
                  Refining
                </span>
              </div>
            )}

            <div className="flex flex-col gap-0.5">
              {steps.map((step) => {
                const isDone = completedSteps.has(STEP_ORDER[step])
                const isActive = currentStep === step
                const isPending = !isDone && !isActive
                return (
                  <div key={step} className="flex items-center gap-2.5 py-1.5">
                    <div className="w-4 flex items-center justify-center">
                      {isDone ? (
                        <CheckCircle2 className="size-3.5 text-success" />
                      ) : isActive ? (
                        <Loader2 className="size-3.5 text-muted-foreground animate-spin" />
                      ) : (
                        <Circle className="size-3.5 text-muted-foreground/20" />
                      )}
                    </div>
                    <span className={cn(
                      "text-[12px]",
                      isPending && "text-muted-foreground/40",
                      isActive && "text-foreground",
                      isDone && "text-foreground",
                    )}>
                      {generationStepLabel(step, isRefine)}
                    </span>
                    <span className="flex-1" />
                    {isDone && (
                      <span className="text-[10px] text-muted-foreground/40">Done</span>
                    )}
                  </div>
                )
              })}
            </div>

            <div className="flex flex-col gap-1.5">
              <div className="w-full h-1 bg-muted rounded-full overflow-hidden">
                <div
                  className="h-full bg-primary rounded-full transition-all duration-500 ease-out"
                  style={{ width: `${progress * 100}%` }}
                />
              </div>
              <div className="flex items-center justify-between">
                <span className="text-[10px] text-muted-foreground/40 tabular-nums">
                  {Math.round(progress * 100)}%
                </span>
                <span className="text-[10px] text-muted-foreground/40 tabular-nums">
                  {formatTime(elapsedSeconds)}
                </span>
              </div>
            </div>

            {!isRunning && lastCompletedTelemetryId && (
              <div className="flex justify-center">
                <GenerationFeedback />
              </div>
            )}
          </div>
        </div>
      </div>

      {showConsole && (
        <>
          <div className="w-px bg-border" />
          <ConsolePanel
            logLines={logLines}
            streamingText={streamingText}
            modelMeta={modelMeta}
            buildAttempt={buildAttempt}
            elapsedSeconds={elapsedSeconds}
            logStyleClass={logStyleClass}
          />
        </>
      )}

      <Dialog open={showCancel} onOpenChange={(v) => { if (!v) setShowCancel(false) }}>
        <DialogContent showCloseButton={false}>
          <DialogHeader>
            <DialogTitle>{isRefine ? "Cancel Refinement?" : "Cancel Build?"}</DialogTitle>
            <DialogDescription>
              {`This will stop the current ${isRefine ? "refinement" : "build"}. You will lose all progress.`}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowCancel(false)}>Continue</Button>
            <Button variant="destructive" onClick={() => { cancel(); reset(); setMainView({ kind: "empty" }) }}>Cancel Build</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
