import { useState, useEffect } from "react"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"

function classifyFailure(message: string) {
  const lower = message.toLowerCase()

  if (
    lower.includes("build environment is not ready") ||
    lower.includes("juce override") ||
    lower.includes("juce is not installed") ||
    lower.includes("juce installation failed") ||
    lower.includes("juce_add_plugin") ||
    lower.includes("add_subdirectory given source") ||
    lower.includes("xcode command line tools") ||
    lower.includes("c++ build tools") ||
    lower.includes("visual studio 2022 build tools") ||
    lower.includes("visual studio build tools") ||
    lower.includes("desktop c++ workload") ||
    lower.includes("ninja is required") ||
    lower.includes("cmake is required") ||
    lower.includes("claude code cli")
  ) {
    return { title: "Environment Not Ready", subtitle: "JUCE or the local build toolchain is not configured correctly.", kind: "environment" }
  }

  if (lower.includes("did not create the required source files") || lower.includes("missing source")) {
    return { title: "Incomplete Generation", subtitle: "The generator stopped before writing all required source files.", kind: "generation" }
  }

  if (lower.includes("timed out") || lower.includes("watchdog")) {
    return { title: "Generation Timed Out", subtitle: "The code generator did not finish within the allowed time.", kind: "generation" }
  }

  if (lower.includes("no plugin bundles found") || lower.includes("bundle")) {
    return { title: "Build Output Invalid", subtitle: "The build completed without producing a usable plugin bundle.", kind: "build" }
  }

  if (lower.includes("compile") || lower.includes("cmake") || lower.includes("error:") || lower.includes("build failed")) {
    return { title: "Build Failed", subtitle: "Foundry could not compile the plugin into a working build.", kind: "build" }
  }

  if (lower.includes("install") || lower.includes("codesign") || lower.includes("administrator privileges") || lower.includes("permission")) {
    return { title: "Installation Failed", subtitle: "The plugin was built but could not be installed on your system.", kind: "install" }
  }

  if (lower.includes("cli is not available") || lower.includes("failed to launch") || lower.includes("command not found")) {
    return { title: "Agent Unavailable", subtitle: "Foundry could not start the code generation agent.", kind: "agent" }
  }

  return { title: "Generation Failed", subtitle: "Foundry could not finish a usable plugin from this brief.", kind: "unknown" }
}

interface Props {
  message: string
}

export default function ErrorPage({ message }: Props) {
  const setMainView = useAppStore((s) => s.setMainView)
  const config = useBuildStore((s) => s.config)
  const startGeneration = useBuildStore((s) => s.startGeneration)
  const logLines = useBuildStore((s) => s.logLines)
  const { title: failureTitle, subtitle: failureSubtitle, kind } = classifyFailure(message)
  const recentLogs = logLines.slice(-8)

  const [appeared, setAppeared] = useState(false)

  useEffect(() => {
    const t = setTimeout(() => setAppeared(true), 50)
    return () => clearTimeout(t)
  }, [])

  const retry = async () => {
    if (config) {
      await startGeneration(config)
      setMainView({ kind: "generation" })
    }
  }

  return (
    <div className="h-full overflow-y-auto">
      <div
        className={cn(
          "w-full px-6 py-8 flex flex-col gap-5 transition-all duration-300",
          appeared ? "opacity-100 translate-y-0" : "opacity-0 translate-y-1",
        )}
      >
        {/* Header */}
        <div className="flex flex-col gap-1">
          <h2 className="text-sm font-medium">{failureTitle}</h2>
          <p className="text-[11px] text-muted-foreground">{failureSubtitle}</p>
        </div>

        {/* Error message */}
        <div className="flex flex-col gap-1">
          <div className="text-[9px] tracking-[1.5px] text-muted-foreground/40 uppercase">Error</div>
          <div className="text-[11px] text-foreground/80 break-words whitespace-pre-wrap bg-muted/40 rounded-lg px-3 py-2">
            {message}
          </div>
        </div>

        {/* Log lines */}
        {recentLogs.length > 0 && (
          <div className="flex flex-col gap-1">
            <div className="text-[9px] tracking-[1.5px] text-muted-foreground/40 uppercase">Last log lines</div>
            <div className="bg-muted/40 rounded-lg px-3 py-2 space-y-0.5">
              {recentLogs.map((line, index) => (
                <div key={`${line.timestamp}-${index}`} className="text-[10px] text-muted-foreground break-words">
                  <span className="text-muted-foreground/40 mr-1.5">{line.timestamp}</span>
                  {line.message}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Actions */}
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={() => setMainView({ kind: "empty" })}>
            Back to Library
          </Button>
          {kind === "environment" && (
            <Button variant="ghost" size="sm" onClick={() => setMainView({ kind: "settings" })}>
              Open Settings
            </Button>
          )}
          {config && (
            <Button size="sm" onClick={retry}>
              Retry
            </Button>
          )}
        </div>
      </div>
    </div>
  )
}
