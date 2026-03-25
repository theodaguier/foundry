import { useState, useEffect, useCallback, useRef } from "react"
import { Button } from "@/components/ui/button"
import { FoundryLogo } from "@/components/app/foundry-logo"
import { useAppStore } from "@/stores/app-store"
import * as commands from "@/lib/commands"

type OnboardingStep = "welcome" | "dependencies" | "ready"

type DepStatus = "checking" | "installed" | "missing" | "installing" | "failed"

interface Dep {
  name: string
  key: string
  required: boolean
  status: DepStatus
  message?: string
}

const OPTIONAL_DEPENDENCIES = new Set(["Codex CLI"])

const DEP_KEY_BY_NAME: Record<string, string> = {
  "Xcode Command Line Tools": "xcode_clt",
  "C++ Build Tools": "cpp_build_tools",
  "CMake": "cmake",
  "Claude Code CLI": "claude_code",
  "Codex CLI": "codex",
  "JUCE SDK": "juce",
}

const DEP_ORDER = [
  "Xcode Command Line Tools",
  "C++ Build Tools",
  "CMake",
  "Claude Code CLI",
  "Codex CLI",
  "JUCE SDK",
]

const DEP_DESCRIPTIONS: Record<string, string> = {
  "Xcode Command Line Tools": "C++ compiler and Apple build tools",
  "C++ Build Tools": "Visual Studio toolchain required to compile JUCE plugins",
  "CMake": "Cross-platform build system for JUCE projects",
  "Claude Code CLI": "Primary AI coding agent used for plugin generation",
  "Codex CLI": "Optional OpenAI coding agent",
  "JUCE SDK": "Framework used to compile the generated plugin",
}

function depSortOrder(name: string) {
  const index = DEP_ORDER.indexOf(name)
  return index === -1 ? DEP_ORDER.length : index
}

function mapDependency(result: Awaited<ReturnType<typeof commands.checkDependencies>>[number]): Dep {
  return {
    name: result.name,
    key: DEP_KEY_BY_NAME[result.name] ?? result.name.toLowerCase().replace(/\s+/g, "_"),
    required: !OPTIONAL_DEPENDENCIES.has(result.name),
    status: result.installed ? "installed" : "missing",
  }
}

function StatusDot({ status }: { status: DepStatus }) {
  if (status === "checking" || status === "installing") {
    return (
      <div className="w-3 h-3 border-[1.5px] border-muted-foreground/60 border-t-transparent rounded-full animate-spin shrink-0" />
    )
  }
  if (status === "installed") {
    return (
      <svg width="14" height="14" viewBox="0 0 14 14" className="text-emerald-500 shrink-0">
        <circle cx="7" cy="7" r="7" fill="currentColor" />
        <path d="M4 7.2L6 9.2L10 5" stroke="white" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
      </svg>
    )
  }
  if (status === "failed") {
    return (
      <svg width="14" height="14" viewBox="0 0 14 14" className="text-destructive shrink-0">
        <circle cx="7" cy="7" r="7" fill="currentColor" />
        <path d="M5 5L9 9M9 5L5 9" stroke="white" strokeWidth="1.5" strokeLinecap="round" fill="none" />
      </svg>
    )
  }
  // missing
  return <div className="w-3 h-3 rounded-full bg-muted-foreground/30 shrink-0" />
}

function StepIndicator({ current }: { current: OnboardingStep }) {
  const steps: OnboardingStep[] = ["welcome", "dependencies", "ready"]
  const idx = steps.indexOf(current)

  return (
    <div className="flex items-center gap-2">
      {steps.map((s, i) => (
        <div
          key={s}
          className={`h-1 rounded-full transition-all duration-300 ${
            i <= idx ? "bg-primary w-6" : "bg-muted-foreground/20 w-4"
          }`}
        />
      ))}
    </div>
  )
}

export default function Onboarding() {
  const [step, setStep] = useState<OnboardingStep>("welcome")
  const [deps, setDeps] = useState<Dep[]>([])
  const [isInstallingAll, setIsInstallingAll] = useState(false)
  const [appeared, setAppeared] = useState(false)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  useEffect(() => {
    const t = setTimeout(() => setAppeared(true), 50)
    return () => clearTimeout(t)
  }, [])

  // Clean up xcode poll on unmount
  useEffect(() => {
    return () => {
      if (pollRef.current) clearInterval(pollRef.current)
    }
  }, [])

  const updateDep = useCallback((key: string, update: Partial<Dep>) => {
    setDeps(prev => prev.map(d => d.key === key ? { ...d, ...update } : d))
  }, [])

  const checkDeps = useCallback(async () => {
    try {
      const results = await commands.checkDependencies()
      const nextDeps = results
        .map(mapDependency)
        .sort((a, b) => depSortOrder(a.name) - depSortOrder(b.name))

      setDeps(prev => nextDeps.map(dep => {
        const current = prev.find(entry => entry.key === dep.key)
        if (current?.status === "installing") return current
        if (current?.status === "failed" && dep.status === "missing") return current
        return dep
      }))
    } catch {
      setDeps(prev => prev.map(d => d.status === "checking" ? { ...d, status: "missing" as DepStatus } : d))
    }
  }, [])

  useEffect(() => {
    if (step === "dependencies") {
      checkDeps()
    }
  }, [step, checkDeps])

  const installSingle = useCallback(async (key: string) => {
    updateDep(key, { status: "installing", message: undefined })

    try {
      if (key === "juce") {
        const buildEnvironment = await commands.installJuce()
        if (buildEnvironment.jucePath) {
          await checkDeps()
        } else {
          updateDep(key, {
            status: "failed",
            message: buildEnvironment.issues[0]?.detail ?? "Failed to install JUCE.",
          })
        }
        return
      }

      const result = await commands.installDependency(key)

      if (key === "xcode_clt" && result.success) {
        // Xcode CLT installer is async (GUI popup) — poll for completion
        updateDep(key, { status: "installing", message: result.message })
        if (pollRef.current) clearInterval(pollRef.current)
        pollRef.current = setInterval(async () => {
          try {
            const results = await commands.checkDependencies()
            const xcode = results.find(r => r.name === "Xcode Command Line Tools")
            if (xcode?.installed) {
              if (pollRef.current) clearInterval(pollRef.current)
              pollRef.current = null
              updateDep(key, { status: "installed", message: undefined })
            }
          } catch { /* continue polling */ }
        }, 5000)
        // Stop polling after 10 minutes
        setTimeout(() => {
          if (pollRef.current) {
            clearInterval(pollRef.current)
            pollRef.current = null
          }
        }, 600000)
        return
      }

      if (result.success) {
        // Re-check to confirm installation
        await checkDeps()
      } else {
        updateDep(key, { status: "failed", message: result.message })
      }
    } catch (e) {
      updateDep(key, { status: "failed", message: String(e) })
    }
  }, [updateDep, checkDeps])

  const installAll = useCallback(async () => {
    setIsInstallingAll(true)
    const missing = deps.filter(d => d.status === "missing" || d.status === "failed")
    for (const dep of missing) {
      await installSingle(dep.key)
      // Small delay between installs for shell cache to settle
      await new Promise(r => setTimeout(r, 500))
    }
    // Final recheck
    await checkDeps()
    setIsInstallingAll(false)
  }, [deps, installSingle, checkDeps])

  const requiredDeps = deps.filter(d => d.required)
  const allInstalled = requiredDeps.length > 0 && requiredDeps.every(d => d.status === "installed")
  const hasMissing = deps.some(d => d.status === "missing" || d.status === "failed")
  const isAnyInstalling = deps.some(d => d.status === "installing")

  const finish = async () => {
    await commands.completeOnboarding()
    useAppStore.getState().checkOnboarding()
  }

  return (
    <div className="flex flex-col items-center justify-center h-full px-8">
      <div
        className="flex flex-col items-center w-full max-w-[400px] transition-all duration-500"
        style={{ opacity: appeared ? 1 : 0, transform: appeared ? "translateY(0)" : "translateY(8px)" }}
      >
        {/* Step: Welcome */}
        {step === "welcome" && (
          <div className="flex flex-col items-center gap-6 text-center">
            <FoundryLogo height={48} className="text-muted-foreground" />
            <div className="flex flex-col gap-2">
              <h1 className="text-xl font-medium">Set up your environment</h1>
              <p className="text-[13px] text-muted-foreground leading-relaxed">
                Foundry needs a few tools to generate audio plugins.
                <br />
                We'll check and install everything automatically.
              </p>
            </div>
            <Button size="lg" onClick={() => setStep("dependencies")}>
              Get Started
            </Button>
          </div>
        )}

        {/* Step: Dependencies */}
        {step === "dependencies" && (
          <div className="flex flex-col gap-5 w-full">
            <div className="flex flex-col gap-1">
              <h2 className="text-lg font-medium">Dependencies</h2>
              <p className="text-[12px] text-muted-foreground">
                {allInstalled
                  ? "All required tools are installed. You're ready to go."
                  : "Install the required tools to get started."}
              </p>
            </div>

            <div className="flex flex-col divide-y divide-muted rounded-lg overflow-hidden">
              {deps.map(dep => (
                <div key={dep.key} className="flex items-center gap-3 px-4 py-3 bg-muted/50">
                  <StatusDot status={dep.status} />
                  <div className="flex-1 min-w-0">
                    <div className="text-[13px] text-foreground font-medium">
                      {dep.name}
                      {!dep.required && <span className="ml-2 text-[10px] uppercase tracking-[1px] text-muted-foreground/60">Optional</span>}
                    </div>
                    {dep.message ? (
                      <div className="text-[11px] text-amber-500 mt-0.5">{dep.message}</div>
                    ) : (
                      <div className="text-[11px] text-muted-foreground mt-0.5">
                        {DEP_DESCRIPTIONS[dep.name] ?? "Required to generate and compile plugins."}
                      </div>
                    )}
                  </div>
                  {dep.status === "missing" && (
                    <Button
                      size="sm"
                      variant="secondary"
                      disabled={isInstallingAll}
                      onClick={() => installSingle(dep.key)}
                      className="text-[11px] h-7 px-3"
                    >
                      Install
                    </Button>
                  )}
                  {dep.status === "failed" && (
                    <Button
                      size="sm"
                      variant="secondary"
                      disabled={isInstallingAll}
                      onClick={() => installSingle(dep.key)}
                      className="text-[11px] h-7 px-3"
                    >
                      Retry
                    </Button>
                  )}
                  {dep.status === "installed" && (
                    <span className="text-[11px] text-emerald-500 font-mono">Installed</span>
                  )}
                  {dep.status === "installing" && (
                    <span className="text-[11px] text-muted-foreground font-mono">Installing...</span>
                  )}
                  {dep.status === "checking" && (
                    <span className="text-[11px] text-muted-foreground font-mono">Checking...</span>
                  )}
                </div>
              ))}
            </div>

            <div className="flex items-center gap-3">
              {hasMissing && !isAnyInstalling && (
                <Button
                  onClick={installAll}
                  disabled={isInstallingAll || isAnyInstalling}
                >
                  {isInstallingAll ? "Installing..." : "Install All Missing"}
                </Button>
              )}
              {allInstalled && (
                <Button onClick={() => setStep("ready")}>
                  Continue
                </Button>
              )}
              <Button
                variant="ghost"
                onClick={checkDeps}
                disabled={isAnyInstalling}
                className="text-[12px]"
              >
                Re-check
              </Button>
            </div>
          </div>
        )}

        {/* Step: Ready */}
        {step === "ready" && (
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
              <h1 className="text-xl font-medium">You're all set</h1>
              <p className="text-[13px] text-muted-foreground leading-relaxed">
                Your environment is ready. Describe a plugin and Foundry will build it for you.
              </p>
            </div>
            <Button size="lg" onClick={finish}>
              Start Building
            </Button>
          </div>
        )}

        {/* Step indicator */}
        <div className="mt-8">
          <StepIndicator current={step} />
        </div>
      </div>
    </div>
  )
}
