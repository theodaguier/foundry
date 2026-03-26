import { useState, useEffect } from "react"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"

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
    return { title: "Environment Not Ready", subtitle: "Foundry stopped before build because JUCE or the local build toolchain is not configured correctly.", kind: "environment" }
  }

  if (lower.includes("did not create the required source files") || lower.includes("missing source")) {
    return { title: "Incomplete Generation", subtitle: "The generator stopped before writing all required JUCE source files.", kind: "generation" }
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
    return { title: "Installation Failed", subtitle: "The plugin was generated, but Foundry could not install it on your system.", kind: "install" }
  }

  if (lower.includes("cli is not available") || lower.includes("failed to launch") || lower.includes("command not found")) {
    return { title: "Agent Unavailable", subtitle: "Foundry could not start the code generation agent in the current environment.", kind: "agent" }
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

  const [iconAppeared, setIconAppeared] = useState(false)
  const [textAppeared, setTextAppeared] = useState(false)
  const [actionsAppeared, setActionsAppeared] = useState(false)

  useEffect(() => {
    const t1 = setTimeout(() => setIconAppeared(true), 50)
    const t2 = setTimeout(() => setTextAppeared(true), 200)
    const t3 = setTimeout(() => setActionsAppeared(true), 350)
    return () => { clearTimeout(t1); clearTimeout(t2); clearTimeout(t3) }
  }, [])

  const retry = async () => {
    if (config) {
      await startGeneration(config)
      setMainView({ kind: "generation" })
    }
  }

  return (
    <div className="flex flex-col items-center justify-center h-full gap-5 px-6">
      <svg
        className="w-10 h-10 text-muted-foreground transition-all duration-500"
        style={{ opacity: iconAppeared ? 1 : 0, transform: iconAppeared ? "scale(1)" : "scale(0.92)" }}
        fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1}
      >
        <path strokeLinecap="round" strokeLinejoin="round" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>

      <div
        className="flex flex-col items-center gap-2 transition-all duration-350 max-w-[720px] w-full"
        style={{ opacity: textAppeared ? 1 : 0, transform: textAppeared ? "translateY(0)" : "translateY(4px)" }}
      >
        <h2 className="text-xl font-medium">{failureTitle}</h2>
        <p className="text-sm text-muted-foreground text-center whitespace-pre-line">{failureSubtitle}</p>

        <Card size="sm" className="w-full max-w-[720px] mt-3 bg-muted/60">
          <CardContent>
            <div className="text-[10px] tracking-[1px] text-muted-foreground/70 mb-1.5">RAW ERROR</div>
            <div className="font-mono text-xs text-foreground whitespace-pre-wrap break-words">{message}</div>
          </CardContent>
        </Card>

        {recentLogs.length > 0 && (
          <Card size="sm" className="w-full max-w-[720px] bg-muted/40">
            <CardContent>
              <div className="text-[10px] tracking-[1px] text-muted-foreground/70 mb-1.5">LAST LOG LINES</div>
              <div className="font-mono text-xs text-muted-foreground space-y-1">
                {recentLogs.map((line, index) => (
                  <div key={`${line.timestamp}-${index}`} className="break-words">
                    <span className="text-muted-foreground/60 mr-2">{line.timestamp}</span>
                    {line.message}
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}
      </div>

      <div
        className="flex gap-2.5 mt-2 transition-all duration-350"
        style={{ opacity: actionsAppeared ? 1 : 0, transform: actionsAppeared ? "translateY(0)" : "translateY(6px)" }}
      >
        <Button variant="secondary" onClick={() => setMainView({ kind: "empty" })}>
          Back to Library
        </Button>
        {kind === "environment" && (
          <Button variant="ghost" onClick={() => setMainView({ kind: "settings" })}>
            Open Settings
          </Button>
        )}
        {config && <Button onClick={retry}>Retry</Button>}
      </div>
    </div>
  )
}
