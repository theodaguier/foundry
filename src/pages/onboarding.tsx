import { useState, useEffect, useCallback, useRef } from "react"
import { open } from "@tauri-apps/plugin-shell"
import { Button } from "@/components/ui/button"
import { FoundryLogo } from "@/components/app/foundry-logo"
import { useAppStore } from "@/stores/app-store"
import * as commands from "@/lib/commands"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type DepStatus = "checking" | "installed" | "missing" | "installing" | "failed" | "auth_required"
type SetupPhase = "checking" | "ready_to_setup" | "installing" | "done"

interface Dep {
  name: string
  key: string
  label: string
  description: string
  required: boolean
  status: DepStatus
  message?: string
}

// ---------------------------------------------------------------------------
// Product-level naming — hides infrastructure details from the user
// ---------------------------------------------------------------------------

const DEP_LABELS: Record<string, string> = {
  "Xcode Command Line Tools": "Apple Build Tools",
  "C++ Build Tools": "Windows Build Tools",
  "CMake": "CMake",
  "Claude Code CLI": "Claude Code",
  "Codex CLI": "Codex",
  "JUCE SDK": "Audio Framework",
}

const DEP_DESCRIPTIONS: Record<string, string> = {
  "Xcode Command Line Tools": "C++ compiler for building audio plugins",
  "C++ Build Tools": "C++ compiler for building audio plugins",
  "CMake": "Builds and compiles your plugin projects",
  "Claude Code CLI": "AI engine that writes the plugin code",
  "Codex CLI": "Alternative AI engine (optional)",
  "JUCE SDK": "Audio plugin framework by JUCE",
}

const DEP_KEY_BY_NAME: Record<string, string> = {
  "Xcode Command Line Tools": "xcode_clt",
  "C++ Build Tools": "cpp_build_tools",
  "CMake": "cmake",
  "Claude Code CLI": "claude_code",
  "Codex CLI": "codex",
  "JUCE SDK": "juce",
}

const OPTIONAL_DEPS = new Set(["Codex CLI"])

const DEP_ORDER = [
  "Xcode Command Line Tools",
  "C++ Build Tools",
  "CMake",
  "Claude Code CLI",
  "Codex CLI",
  "JUCE SDK",
]

/** Estimated install duration in seconds per dependency (used for progress) */
const ESTIMATED_DURATION: Record<string, number> = {
  xcode_clt: 180,      // ~3 min (GUI installer)
  cpp_build_tools: 420, // ~7 min (large VS workload)
  cmake: 30,
  claude_code: 20,
  codex: 20,
  juce: 25,
}

function depSortOrder(name: string) {
  const i = DEP_ORDER.indexOf(name)
  return i === -1 ? DEP_ORDER.length : i
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function mapDependency(
  result: Awaited<ReturnType<typeof commands.checkDependencies>>[number],
): Dep {
  let status: DepStatus = "missing"
  if (result.installed && result.authRequired) {
    status = "auth_required"
  } else if (result.installed) {
    status = "installed"
  }

  return {
    name: result.name,
    key: DEP_KEY_BY_NAME[result.name] ?? result.name.toLowerCase().replace(/\s+/g, "_"),
    label: DEP_LABELS[result.name] ?? result.name,
    description: DEP_DESCRIPTIONS[result.name] ?? "Required for plugin generation",
    required: !OPTIONAL_DEPS.has(result.name),
    status,
  }
}

// ---------------------------------------------------------------------------
// Hook: elapsed-time progress estimation
// ---------------------------------------------------------------------------

function useInstallProgress(deps: Dep[]) {
  const [progress, setProgress] = useState<Record<string, number>>({})
  const timersRef = useRef<Record<string, ReturnType<typeof setInterval>>>({})
  const startTimesRef = useRef<Record<string, number>>({})

  useEffect(() => {
    for (const dep of deps) {
      if (dep.status === "installing" && !timersRef.current[dep.key]) {
        // Start tracking this dep
        startTimesRef.current[dep.key] = Date.now()
        setProgress(prev => ({ ...prev, [dep.key]: 0 }))

        const estimatedMs = (ESTIMATED_DURATION[dep.key] ?? 30) * 1000

        timersRef.current[dep.key] = setInterval(() => {
          const elapsed = Date.now() - startTimesRef.current[dep.key]
          // Asymptotic curve: approaches 90% but never reaches it
          // progress = 90 * (1 - e^(-2 * elapsed / estimated))
          const pct = Math.min(90, 90 * (1 - Math.exp((-2 * elapsed) / estimatedMs)))
          setProgress(prev => ({ ...prev, [dep.key]: Math.round(pct) }))
        }, 500)
      }

      if (dep.status === "installed" && timersRef.current[dep.key]) {
        // Complete: jump to 100%
        clearInterval(timersRef.current[dep.key])
        delete timersRef.current[dep.key]
        delete startTimesRef.current[dep.key]
        setProgress(prev => ({ ...prev, [dep.key]: 100 }))
      }

      if (dep.status === "failed" && timersRef.current[dep.key]) {
        // Failed: stop timer
        clearInterval(timersRef.current[dep.key])
        delete timersRef.current[dep.key]
        delete startTimesRef.current[dep.key]
        setProgress(prev => {
          const next = { ...prev }
          delete next[dep.key]
          return next
        })
      }
    }

    return () => {
      // Cleanup on unmount
      for (const key of Object.keys(timersRef.current)) {
        clearInterval(timersRef.current[key])
      }
    }
  }, [deps])

  return progress
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function StatusIcon({ status, progress }: { status: DepStatus; progress?: number }) {
  if (status === "installing" && progress !== undefined) {
    // Circular progress ring
    const radius = 6
    const circumference = 2 * Math.PI * radius
    const offset = circumference - (progress / 100) * circumference
    return (
      <div className="w-5 h-5 flex items-center justify-center shrink-0">
        <svg width="16" height="16" viewBox="0 0 16 16" className="text-primary -rotate-90">
          <circle
            cx="8" cy="8" r={radius}
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            opacity="0.15"
          />
          <circle
            cx="8" cy="8" r={radius}
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeDasharray={circumference}
            strokeDashoffset={offset}
            strokeLinecap="round"
            className="transition-[stroke-dashoffset] duration-500 ease-out"
          />
        </svg>
      </div>
    )
  }
  if (status === "checking") {
    return (
      <div className="w-5 h-5 flex items-center justify-center shrink-0">
        <div className="w-3.5 h-3.5 border-[1.5px] border-primary/60 border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }
  if (status === "installed") {
    return (
      <div className="w-5 h-5 flex items-center justify-center shrink-0">
        <svg width="16" height="16" viewBox="0 0 16 16" className="text-emerald-500">
          <circle cx="8" cy="8" r="8" fill="currentColor" />
          <path d="M4.5 8.2L6.8 10.5L11.5 5.5" stroke="white" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
        </svg>
      </div>
    )
  }
  if (status === "auth_required") {
    return (
      <div className="w-5 h-5 flex items-center justify-center shrink-0">
        <svg width="16" height="16" viewBox="0 0 16 16" className="text-amber-500">
          <circle cx="8" cy="8" r="8" fill="currentColor" />
          <path d="M8 4.5V9" stroke="white" strokeWidth="1.5" strokeLinecap="round" fill="none" />
          <circle cx="8" cy="11.5" r="1" fill="white" />
        </svg>
      </div>
    )
  }
  if (status === "failed") {
    return (
      <div className="w-5 h-5 flex items-center justify-center shrink-0">
        <svg width="16" height="16" viewBox="0 0 16 16" className="text-destructive">
          <circle cx="8" cy="8" r="8" fill="currentColor" />
          <path d="M5.5 5.5L10.5 10.5M10.5 5.5L5.5 10.5" stroke="white" strokeWidth="1.5" strokeLinecap="round" fill="none" />
        </svg>
      </div>
    )
  }
  // missing
  return (
    <div className="w-5 h-5 flex items-center justify-center shrink-0">
      <div className="w-3 h-3 rounded-full bg-muted-foreground/25" />
    </div>
  )
}

function statusColor(status: DepStatus): string {
  switch (status) {
    case "installed": return "text-emerald-500"
    case "auth_required": return "text-amber-500"
    case "installing":
    case "checking": return "text-muted-foreground"
    case "failed": return "text-destructive"
    case "missing": return "text-muted-foreground/50"
  }
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export default function Onboarding() {
  const [phase, setPhase] = useState<SetupPhase>("checking")
  const [deps, setDeps] = useState<Dep[]>([])
  const [appeared, setAppeared] = useState(false)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const abortedRef = useRef(false)

  const installProgress = useInstallProgress(deps)

  // Entrance animation
  useEffect(() => {
    const t = setTimeout(() => setAppeared(true), 50)
    return () => clearTimeout(t)
  }, [])

  // Clean up Xcode CLT poll on unmount
  useEffect(() => {
    return () => {
      abortedRef.current = true
      if (pollRef.current) clearInterval(pollRef.current)
    }
  }, [])

  // ---- Dep state helpers ----

  const updateDep = useCallback((key: string, update: Partial<Dep>) => {
    setDeps(prev => prev.map(d => d.key === key ? { ...d, ...update } : d))
  }, [])

  // ---- Check dependencies ----

  const checkDeps = useCallback(async (): Promise<Dep[]> => {
    try {
      const results = await commands.checkDependencies()
      const mapped = results
        .map(mapDependency)
        .sort((a, b) => depSortOrder(a.name) - depSortOrder(b.name))

      setDeps(prev => mapped.map(dep => {
        const current = prev.find(entry => entry.key === dep.key)
        if (current?.status === "installing") return current
        if (current?.status === "failed" && dep.status === "missing") return current
        return dep
      }))
      return mapped
    } catch {
      return []
    }
  }, [])

  // ---- Install a single dependency ----

  const installSingle = useCallback(async (dep: Dep) => {
    if (abortedRef.current) return

    updateDep(dep.key, { status: "installing", message: undefined })

    try {
      if (dep.key === "juce") {
        const env = await commands.installJuce()
        if (env.jucePath) {
          updateDep(dep.key, { status: "installed", message: undefined })
        } else {
          updateDep(dep.key, {
            status: "failed",
            message: env.issues[0]?.detail ?? "Could not download audio framework.",
          })
        }
        return
      }

      const result = await commands.installDependency(dep.key)

      // GUI-based installers (Xcode CLT, VS Build Tools) — poll until detected
      const isGuiInstaller = (dep.key === "xcode_clt" || dep.key === "cpp_build_tools") && result.success
      if (isGuiInstaller) {
        const depName = dep.key === "xcode_clt" ? "Xcode Command Line Tools" : "C++ Build Tools"
        if (pollRef.current) clearInterval(pollRef.current)
        pollRef.current = setInterval(async () => {
          try {
            const results = await commands.checkDependencies()
            const found = results.find(r => r.name === depName)
            if (found?.installed) {
              if (pollRef.current) clearInterval(pollRef.current)
              pollRef.current = null
              updateDep(dep.key, { status: "installed", message: undefined })
            }
          } catch { /* keep polling */ }
        }, 5000)
        // Stop after 15 minutes (Build Tools can take a while)
        setTimeout(() => {
          if (pollRef.current) {
            clearInterval(pollRef.current)
            pollRef.current = null
            updateDep(dep.key, {
              status: "failed",
              message: "Installation timed out. Click Retry to try again.",
            })
          }
        }, 900_000)
        return
      }

      if (result.success) {
        updateDep(dep.key, { status: "installed", message: undefined })
      } else {
        updateDep(dep.key, { status: "failed", message: result.message })
      }
    } catch (e) {
      updateDep(dep.key, { status: "failed", message: String(e) })
    }
  }, [updateDep])

  // ---- Install all missing (serial) ----

  const installAll = useCallback(async () => {
    setPhase("installing")

    // Re-check first to get latest state
    const fresh = await checkDeps()
    const missing = fresh.filter(d => d.status === "missing" && d.required)

    for (const dep of missing) {
      if (abortedRef.current) return
      await installSingle(dep)
      // Small delay for PATH cache to settle between installs
      await new Promise(r => setTimeout(r, 600))
    }

    // Final recheck
    await checkDeps()
  }, [checkDeps, installSingle])

  // ---- Initial check on mount ----

  useEffect(() => {
    let mounted = true
    async function init() {
      const results = await checkDeps()
      if (!mounted) return
      const requiredMissing = results.filter(d => d.required && d.status !== "installed")
      if (requiredMissing.length === 0) {
        setPhase("done")
      } else {
        setPhase("ready_to_setup")
      }
    }
    init()
    return () => { mounted = false }
  }, [checkDeps])

  // ---- Derived state ----

  const requiredDeps = deps.filter(d => d.required)
  const allReady = requiredDeps.length > 0 && requiredDeps.every(d => d.status === "installed")
  const hasAuthRequired = deps.some(d => d.status === "auth_required")
  const hasFailed = deps.some(d => d.status === "failed" && d.required)
  const isInstalling = phase === "installing" && deps.some(d => d.status === "installing")

  // Auto-transition to done when all required deps are installed during install phase
  useEffect(() => {
    if (phase === "installing" && allReady) {
      setPhase("done")
    }
  }, [phase, allReady])

  // ---- Finish ----

  const finish = async () => {
    await commands.completeOnboarding()
    useAppStore.getState().checkOnboarding()
  }

  // ---- Auto-complete after brief delay when done ----

  useEffect(() => {
    if (phase !== "done") return
    const t = setTimeout(() => finish(), 1500)
    return () => clearTimeout(t)
  }, [phase])

  // ---- Overall progress ----

  const installedCount = requiredDeps.filter(d => d.status === "installed").length
  const totalRequired = requiredDeps.length
  const overallPct = totalRequired > 0 ? (installedCount / totalRequired) * 100 : 0

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <div className="flex flex-col items-center justify-center h-full px-8">
      <div
        className="flex flex-col items-center w-full max-w-[420px] transition-all duration-500"
        style={{ opacity: appeared ? 1 : 0, transform: appeared ? "translateY(0)" : "translateY(8px)" }}
      >
        {/* Done state */}
        {phase === "done" && (
          <div className="flex flex-col items-center gap-6 text-center">
            <div className="w-16 h-16 rounded-full bg-emerald-500/10 flex items-center justify-center">
              <svg width="32" height="32" viewBox="0 0 32 32" className="text-emerald-500">
                <path
                  d="M8 16.5L13.5 22L24 10"
                  stroke="currentColor"
                  strokeWidth="2.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  fill="none"
                />
              </svg>
            </div>
            <div className="flex flex-col gap-2">
              <h1 className="text-xl font-medium">Ready to go</h1>
              <p className="text-[13px] text-muted-foreground leading-relaxed">
                Foundry is set up. Let's build something.
              </p>
            </div>
          </div>
        )}

        {/* Checking state */}
        {phase === "checking" && (
          <div className="flex flex-col items-center gap-5 text-center">
            <FoundryLogo height={48} className="text-muted-foreground" />
            <div className="flex flex-col gap-2">
              <h1 className="text-lg font-medium">Checking your setup…</h1>
              <p className="text-[13px] text-muted-foreground">
                Looking for the tools Foundry needs.
              </p>
            </div>
            <div className="w-5 h-5 border-2 border-muted-foreground/60 border-t-transparent rounded-full animate-spin" />
          </div>
        )}

        {/* Setup / Installing state */}
        {(phase === "ready_to_setup" || phase === "installing") && (
          <div className="flex flex-col gap-6 w-full">
            {/* Header */}
            <div className="flex flex-col items-center gap-2 text-center">
              <FoundryLogo height={40} className="text-muted-foreground" />
              <h1 className="text-lg font-medium">
                {phase === "installing" ? "Setting up Foundry" : "Almost ready"}
              </h1>
              <p className="text-[13px] text-muted-foreground leading-relaxed">
                {phase === "installing"
                  ? "Installing the tools needed to build audio plugins."
                  : "A few tools are needed before you can start building."}
              </p>
            </div>

            {/* Progress bar (only during install) */}
            {phase === "installing" && (
              <div className="w-full h-1 rounded-full bg-muted overflow-hidden">
                <div
                  className="h-full bg-primary rounded-full transition-all duration-500 ease-out"
                  style={{ width: `${overallPct}%` }}
                />
              </div>
            )}

            {/* Dependency list */}
            <div className="flex flex-col rounded-lg overflow-hidden border border-border/50">
              {deps.map((dep, i) => {
                const pct = installProgress[dep.key]
                return (
                  <div
                    key={dep.key}
                    className={`flex items-center gap-3 px-4 py-3 ${
                      i > 0 ? "border-t border-border/30" : ""
                    } ${dep.status === "installing" ? "bg-muted/60" : "bg-muted/30"}`}
                  >
                    <StatusIcon status={dep.status} progress={pct} />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-[13px] font-medium text-foreground">
                          {dep.label}
                        </span>
                        {!dep.required && (
                          <span className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">
                            Optional
                          </span>
                        )}
                      </div>
                      {dep.status === "failed" && dep.message ? (
                        <div className="text-[11px] text-destructive/80 mt-0.5 line-clamp-2">
                          {dep.message}
                        </div>
                      ) : dep.status === "auth_required" ? (
                        <div className="text-[11px] text-amber-500/80 mt-0.5">
                          Installed — sign in to activate
                        </div>
                      ) : (
                        <div className="text-[11px] text-muted-foreground/70 mt-0.5">
                          {dep.status === "installing"
                            ? "Setting up…"
                            : dep.description}
                        </div>
                      )}
                    </div>
                    <span className={`text-[11px] font-medium shrink-0 tabular-nums ${statusColor(dep.status)}`}>
                      {dep.status === "installed" && "Ready"}
                      {dep.status === "installing" && pct !== undefined && `${pct}%`}
                      {dep.status === "auth_required" && (
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={async () => {
                            // Open terminal with claude auth login
                            try {
                              await open("https://claude.ai/login")
                            } catch { /* fallback: user opens manually */ }
                          }}
                          className="text-[11px] h-6 px-2 text-amber-500 hover:text-amber-500"
                        >
                          Sign in
                        </Button>
                      )}
                      {dep.status === "failed" && (
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={isInstalling}
                          onClick={() => installSingle(dep)}
                          className="text-[11px] h-6 px-2 text-destructive hover:text-destructive"
                        >
                          Retry
                        </Button>
                      )}
                    </span>
                  </div>
                )
              })}
            </div>

            {/* Actions */}
            <div className="flex flex-col items-center gap-3">
              {phase === "ready_to_setup" && (
                <Button size="lg" onClick={installAll} className="w-full">
                  Set Up Foundry
                </Button>
              )}

              {phase === "installing" && !allReady && !hasFailed && (
                <Button size="lg" disabled className="w-full">
                  <div className="w-3.5 h-3.5 border-[1.5px] border-current border-t-transparent rounded-full animate-spin mr-2" />
                  Setting up…
                </Button>
              )}

              {phase === "installing" && hasFailed && (
                <div className="flex gap-2 w-full">
                  <Button
                    variant="secondary"
                    onClick={async () => {
                      await checkDeps()
                      setPhase("ready_to_setup")
                    }}
                    className="flex-1"
                  >
                    Re-check
                  </Button>
                  <Button onClick={installAll} className="flex-1">
                    Retry All
                  </Button>
                </div>
              )}

              {hasAuthRequired && !isInstalling && (
                <div className="flex flex-col items-center gap-2 w-full">
                  <p className="text-[12px] text-muted-foreground text-center">
                    Open a terminal and run <code className="text-[11px] bg-muted px-1.5 py-0.5 rounded font-mono">claude</code> to sign in, then click Re-check.
                  </p>
                  <Button
                    variant="secondary"
                    onClick={checkDeps}
                    className="w-full"
                  >
                    Re-check
                  </Button>
                </div>
              )}

              {allReady && (
                <Button size="lg" onClick={finish} className="w-full">
                  Start Building
                </Button>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
