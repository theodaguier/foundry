import { useState, useEffect, useCallback, useRef } from "react"
import { Button } from "@/components/ui/button"
import { FoundryLogo } from "@/components/app/foundry-logo"
import { useAppStore } from "@/stores/app-store"
import { useSettingsStore } from "@/stores/settings-store"
import * as commands from "@/lib/commands"
import { interpretDependencyInstallResult } from "@/lib/dependency-install"
import * as analytics from "@/lib/analytics"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type DepStatus = "checking" | "installed" | "missing" | "installing" | "failed" | "auth_required"

type SetupStep = "checking" | "machine" | "provider" | "auth" | "done"

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
  "Git": "Git",
  "Claude Code CLI": "Claude Code",
  "Codex CLI": "Codex",
  "JUCE SDK": "Audio Framework",
}

const DEP_DESCRIPTIONS: Record<string, string> = {
  "Xcode Command Line Tools": "C++ compiler for building audio plugins",
  "C++ Build Tools": "C++ compiler for building audio plugins",
  "CMake": "Builds and compiles your plugin projects",
  "Git": "Required by Claude Code on Windows",
  "Claude Code CLI": "AI engine that writes the plugin code",
  "Codex CLI": "Alternative AI engine (optional)",
  "JUCE SDK": "Audio plugin framework by JUCE",
}

const DEP_KEY_BY_NAME: Record<string, string> = {
  "Xcode Command Line Tools": "xcode_clt",
  "C++ Build Tools": "cpp_build_tools",
  "CMake": "cmake",
  "Git": "git",
  "Claude Code CLI": "claude_code",
  "Codex CLI": "codex",
  "JUCE SDK": "juce",
}

const OPTIONAL_DEPS = new Set(["Codex CLI", "Claude Code CLI"])
const PROVIDER_DEPS = new Set(["claude_code", "codex"])
const PRIMARY_PROVIDER = "claude_code"

const DEP_ORDER = [
  "Xcode Command Line Tools",
  "C++ Build Tools",
  "CMake",
  "Git",
  "Claude Code CLI",
  "Codex CLI",
  "JUCE SDK",
]

/** Estimated install duration in seconds per dependency (used for progress) */
const ESTIMATED_DURATION: Record<string, number> = {
  xcode_clt: 180,      // ~3 min (GUI installer, polled)
  cpp_build_tools: 30,  // ~30s download, then MS installer takes over
  cmake: 30,
  git: 45,
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
  const [step, setStep] = useState<SetupStep>("checking")
  const [deps, setDeps] = useState<Dep[]>([])
  const [appeared, setAppeared] = useState(false)
  const [selectedProvider, setSelectedProvider] = useState<string>(PRIMARY_PROVIDER)
  const [installingDep, setInstallingDep] = useState<string | null>(null)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const authPollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const abortedRef = useRef(false)

  const installProgress = useInstallProgress(deps)

  // Entrance animation
  useEffect(() => {
    const t = setTimeout(() => setAppeared(true), 50)
    return () => clearTimeout(t)
  }, [])

  // Clean up polls on unmount
  useEffect(() => {
    return () => {
      abortedRef.current = true
      if (pollRef.current) clearInterval(pollRef.current)
      if (authPollRef.current) clearInterval(authPollRef.current)
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

    updateDep(dep.key, {
      status: "installing",
      message: dep.key === "cpp_build_tools"
        ? "Approve the Windows admin prompt if it appears."
        : undefined,
    })
    analytics.trackDependencyInstallStarted({ dependency: dep.key })

    try {
      if (dep.key === "juce") {
        const env = await commands.installJuce()
        if (env.jucePath) {
          updateDep(dep.key, { status: "installed", message: undefined })
          analytics.trackDependencyInstallCompleted({ dependency: dep.key, success: true })
        } else {
          const msg = env.issues[0]?.detail ?? "Could not download audio framework."
          updateDep(dep.key, { status: "failed", message: msg })
          analytics.trackDependencyInstallCompleted({ dependency: dep.key, success: false, message: msg })
        }
        return
      }

      const result = await commands.installDependency(dep.key)
      const outcome = interpretDependencyInstallResult(result)

      // Xcode CLT is still a GUI-based installer — poll until detected.
      const isGuiInstaller = dep.key === "xcode_clt" && outcome.state === "pending"
      if (isGuiInstaller) {
        const depName = "Xcode Command Line Tools"
        updateDep(dep.key, {
          status: "installing",
          message: outcome.message,
        })
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

      if (outcome.state === "verified") {
        updateDep(dep.key, { status: "installed", message: undefined })
        analytics.trackDependencyInstallCompleted({ dependency: dep.key, success: true })
        return
      }

      if (outcome.state === "auth_required") {
        const providerAuth: Record<string, { depName: string; launch: () => Promise<unknown> }> = {
          claude_code: { depName: "Claude Code CLI", launch: commands.launchClaudeAuth },
          codex: { depName: "Codex CLI", launch: commands.launchCodexAuth },
        }
        const auth = providerAuth[dep.key]
        updateDep(dep.key, { status: "auth_required", message: "Opening browser to sign in…" })
        analytics.trackDependencyInstallCompleted({ dependency: dep.key, success: true })
        if (auth) {
          analytics.trackDependencyAuthStarted({ provider: dep.key })
          try { await auth.launch() } catch {}
          if (authPollRef.current) clearInterval(authPollRef.current)
          authPollRef.current = setInterval(async () => {
            try {
              const results = await commands.checkDependencies()
              const found = results.find(r => r.name === auth.depName)
              if (found?.installed && !found.authRequired) {
                if (authPollRef.current) clearInterval(authPollRef.current)
                authPollRef.current = null
                updateDep(dep.key, { status: "installed", message: undefined })
                analytics.trackDependencyAuthCompleted({ provider: dep.key })
              }
            } catch { /* keep polling */ }
          }, 5000)
          setTimeout(() => {
            if (authPollRef.current) {
              clearInterval(authPollRef.current)
              authPollRef.current = null
            }
          }, 300_000)
        }
        return
      }

      if (outcome.state === "pending") {
        updateDep(dep.key, { status: "installing", message: outcome.message })
        analytics.trackDependencyInstallCompleted({ dependency: dep.key, success: true })
      } else {
        updateDep(dep.key, { status: "failed", message: outcome.message })
        analytics.trackDependencyInstallCompleted({ dependency: dep.key, success: false, message: outcome.message })
      }
    } catch (e) {
      updateDep(dep.key, { status: "failed", message: String(e) })
      analytics.trackDependencyInstallCompleted({ dependency: dep.key, success: false, message: String(e) })
    }
  }, [updateDep])

  // ---- Install all machine-level dependencies (serial) ----

  const installMachine = useCallback(async () => {
    analytics.trackOnboardingStarted()
    const fresh = await checkDeps()
    const machineDeps = fresh.filter(d => d.required && !PROVIDER_DEPS.has(d.key))
    for (const dep of machineDeps) {
      if (abortedRef.current) return
      setInstallingDep(dep.key)
      await installSingle(dep)
      setInstallingDep(null)
      await new Promise(r => setTimeout(r, 600))
    }
    // Refresh state to determine next step
    const recheck = await commands.getSetupState()
    const recheckDeps = await checkDeps()
    const machineReady = recheck.buildEnvironmentReady
    const needsAuth = recheck.providers.some(p => p.status === "installed_needs_auth")
    const hasInstalled = recheck.providers.some(p => p.status === "installed_and_authenticated")
    if (hasInstalled) {
      setStep("done")
    } else if (machineReady && needsAuth) {
      setStep("auth")
    } else if (machineReady) {
      setStep("provider")
    }
  }, [checkDeps, installSingle])

  // ---- Install the selected provider ----

  const installSelectedProvider = useCallback(async () => {
    analytics.trackOnboardingStarted()
    const fresh = await checkDeps()
    const providerDep = fresh.find(d => d.key === selectedProvider)
    if (!providerDep || providerDep.status !== "missing") return
    setInstallingDep(providerDep.key)
    await installSingle(providerDep)
    setInstallingDep(null)
    await new Promise(r => setTimeout(r, 600))
    // Refresh state — if installed and needs auth go to auth step, else done
    const recheck = await commands.getSetupState()
    const needsAuth = recheck.providers.some(p => p.status === "installed_needs_auth")
    const hasInstalled = recheck.providers.some(p => p.status === "installed_and_authenticated")
    if (hasInstalled) {
      setStep("done")
    } else if (needsAuth) {
      setStep("auth")
    }
  }, [checkDeps, installSingle, selectedProvider])

  // ---- Initial check on mount ----

  useEffect(() => {
    let mounted = true
    async function init() {
      try {
        const [setupResults, depsResults] = await Promise.all([
          commands.getSetupState(),
          checkDeps(),
        ])
        if (!mounted) return

        const machineReady = setupResults.buildEnvironmentReady
        const providers = setupResults.providers
        const hasInstalledProvider = providers.some(
          p => p.status === "installed_and_authenticated"
        )
        const needsAuthProvider = providers.some(
          p => p.status === "installed_needs_auth"
        )

        if (machineReady && hasInstalledProvider) {
          setStep("done")
        } else if (machineReady && needsAuthProvider) {
          setStep("auth")
        } else if (machineReady) {
          setStep("provider")
        } else {
          setStep("machine")
        }
      } catch {
        if (!mounted) return
        setStep("machine")
      }
    }
    init()
    return () => { mounted = false }
  }, [checkDeps])

  // ---- Derived state ----

  const hasAuthRequired = deps.some(d => d.status === "auth_required")
  const isInstalling = installingDep !== null

  // ---- Finish ----

  const finish = async () => {
    analytics.trackOnboardingCompleted()
    await commands.completeOnboarding()
    await useSettingsStore.getState().refreshModels()
    useAppStore.getState().checkSetup()
  }

  // ---- Auto-complete after brief delay when done ----

  useEffect(() => {
    if (step !== "done") return
    const t = setTimeout(() => finish(), 1500)
    return () => clearTimeout(t)
  }, [step])

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
        {step === "done" && (
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
        {step === "checking" && (
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

        {/* Step-based setup */}
        {(step === "machine" || step === "provider" || step === "auth") && (
          <div className="flex flex-col gap-6 w-full">
            {/* Header */}
            <div className="flex flex-col items-center gap-2 text-center">
              <FoundryLogo height={40} className="text-muted-foreground" />
              <h1 className="text-lg font-medium">
                {step === "machine" ? "Build tools" : step === "provider" ? "AI engine" : "Sign in"}
              </h1>
              <p className="text-[13px] text-muted-foreground leading-relaxed">
                {step === "machine"
                  ? "Install the C++ toolchain and JUCE framework."
                  : step === "provider"
                  ? "Choose an AI engine to generate plugin code."
                  : "Sign in to your AI engine to finish setup."}
              </p>
            </div>

            {/* Machine step: build tools + JUCE deps */}
            {step === "machine" && (
              <div className="flex flex-col gap-6 w-full">
                <div className="flex flex-col rounded-lg overflow-hidden border border-border/50">
                  {deps
                    .filter(d => !PROVIDER_DEPS.has(d.key))
                    .map((dep, i) => {
                      const pct = installProgress[dep.key]
                      return (
                        <div
                          key={dep.key}
                          className={`flex items-center gap-3 px-4 py-3 ${
                            i > 0 ? "border-t border-border/30" : ""
                          } ${installingDep === dep.key ? "bg-muted/60" : "bg-muted/30"}`}
                        >
                          <StatusIcon status={dep.status} progress={pct} />
                          <div className="flex-1 min-w-0">
                            <span className="text-[13px] font-medium text-foreground">
                              {dep.label}
                            </span>
                            {dep.status === "failed" && dep.message ? (
                              <div className="text-[11px] text-destructive/80 mt-0.5 break-words">
                                {dep.message}
                              </div>
                            ) : (
                              <div className="text-[11px] text-muted-foreground/70 mt-0.5">
                                {installingDep === dep.key
                                  ? dep.message ?? "Setting up…"
                                  : dep.description}
                              </div>
                            )}
                          </div>
                          <span className={`text-[11px] font-medium shrink-0 tabular-nums ${statusColor(dep.status)}`}>
                            {dep.status === "installed" && "Ready"}
                            {dep.status === "installing" && pct !== undefined && `${pct}%`}
                            {dep.status === "missing" && (
                              <Button
                                size="sm"
                                variant="secondary"
                                disabled={isInstalling}
                                onClick={async () => {
                                  setInstallingDep(dep.key)
                                  await installSingle(dep)
                                  setInstallingDep(null)
                                  await checkDeps()
                                }}
                                className="text-[11px] h-6 px-2"
                              >
                                Install
                              </Button>
                            )}
                            {dep.status === "failed" && (
                              <Button
                                size="sm"
                                variant="ghost"
                                disabled={isInstalling}
                                onClick={async () => {
                                  setInstallingDep(dep.key)
                                  await installSingle(dep)
                                  setInstallingDep(null)
                                  await checkDeps()
                                }}
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

                <div className="flex flex-col items-center gap-3">
                  {(() => {
                    const machineDeps = deps.filter(d => !PROVIDER_DEPS.has(d.key))
                    const allMachineReady = machineDeps.length > 0 && machineDeps.every(d => d.status === "installed")
                    if (!isInstalling) {
                      if (allMachineReady) {
                        return (
                          <Button
                            size="lg"
                            onClick={async () => {
                              // All machine deps ready — jump to the next relevant step.
                              // Recheck setup state to know whether to go provider or auth.
                              const s = await commands.getSetupState()
                              const needsAuth = s.providers.some(p => p.status === "installed_needs_auth")
                              if (needsAuth) setStep("auth")
                              else setStep("provider")
                            }}
                            className="w-full"
                          >
                            Continue
                          </Button>
                        )
                      }
                      return (
                        <Button
                          size="lg"
                          onClick={installMachine}
                          className="w-full"
                        >
                          Install tools
                        </Button>
                      )
                    }
                    return (
                      <Button size="lg" disabled className="w-full">
                        <div className="w-3.5 h-3.5 border-[1.5px] border-current border-t-transparent rounded-full animate-spin mr-2" />
                        Installing…
                      </Button>
                    )
                  })()}
                </div>
              </div>
            )}

            {/* Provider step: select and install Claude or Codex */}
            {step === "provider" && (
              <div className="flex flex-col gap-6 w-full">
                <div className="flex flex-col rounded-lg overflow-hidden border border-border/50">
                  {deps
                    .filter(d => PROVIDER_DEPS.has(d.key))
                    .map((dep, i) => {
                      const pct = installProgress[dep.key]
                      const isSelected = dep.key === selectedProvider
                      return (
                        <div
                          key={dep.key}
                          className={`flex items-center gap-3 px-4 py-3 ${
                            i > 0 ? "border-t border-border/30" : ""
                          } ${installingDep === dep.key ? "bg-muted/60" : "bg-muted/30"}`}
                        >
                          <StatusIcon status={dep.status} progress={pct} />
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2">
                              <span className="text-[13px] font-medium text-foreground">
                                {dep.label}
                              </span>
                              {dep.key === selectedProvider && (
                                <span className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">
                                  Selected
                                </span>
                              )}
                            </div>
                            {dep.status === "failed" && dep.message ? (
                              <div className="text-[11px] text-destructive/80 mt-0.5 break-words">
                                {dep.message}
                              </div>
                            ) : (
                              <div className="text-[11px] text-muted-foreground/70 mt-0.5">
                                {installingDep === dep.key
                                  ? dep.message ?? "Setting up…"
                                  : dep.description}
                              </div>
                            )}
                          </div>
                          <span className={`text-[11px] font-medium shrink-0 tabular-nums ${statusColor(dep.status)}`}>
                            {dep.status === "installed" && "Ready"}
                            {dep.status === "installing" && pct !== undefined && `${pct}%`}
                            {dep.status === "missing" && (
                              <Button
                                size="sm"
                                variant={isSelected ? "default" : "secondary"}
                                disabled={isInstalling}
                                onClick={() => setSelectedProvider(dep.key)}
                                className="text-[11px] h-6 px-2"
                              >
                                {isSelected ? "Selected" : "Select"}
                              </Button>
                            )}
                            {dep.status === "failed" && (
                              <Button
                                size="sm"
                                variant="ghost"
                                disabled={isInstalling}
                                onClick={async () => {
                                  setInstallingDep(dep.key)
                                  await installSingle(dep)
                                  setInstallingDep(null)
                                  await checkDeps()
                                }}
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

                <div className="flex flex-col items-center gap-3">
                  {!isInstalling && (
                    <Button
                      size="lg"
                      onClick={installSelectedProvider}
                      className="w-full"
                      disabled={!deps.find(d => d.key === selectedProvider && d.status === "missing")}
                    >
                      Install {deps.find(d => d.key === selectedProvider)?.label ?? "engine"}
                    </Button>
                  )}
                  {isInstalling && (
                    <Button size="lg" disabled className="w-full">
                      <div className="w-3.5 h-3.5 border-[1.5px] border-current border-t-transparent rounded-full animate-spin mr-2" />
                      Installing…
                    </Button>
                  )}
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={async () => {
                      await checkDeps()
                      await commands.getSetupState().then(s => {
                        if (s.buildEnvironmentReady) setStep("machine")
                      })
                    }}
                  >
                    Back
                  </Button>
                </div>
              </div>
            )}

            {/* Auth step: sign in to the installed provider */}
            {step === "auth" && (
              <div className="flex flex-col gap-6 w-full">
                <div className="flex flex-col rounded-lg overflow-hidden border border-border/50">
                  {deps
                    .filter(d => PROVIDER_DEPS.has(d.key) && d.status !== "missing")
                    .map((dep, i) => (
                      <div
                        key={dep.key}
                        className={`flex items-center gap-3 px-4 py-3 ${
                          i > 0 ? "border-t border-border/30" : ""
                        } ${dep.status === "auth_required" ? "bg-muted/60" : "bg-muted/30"}`}
                      >
                        <StatusIcon status={dep.status} progress={undefined} />
                        <div className="flex-1 min-w-0">
                          <span className="text-[13px] font-medium text-foreground">
                            {dep.label}
                          </span>
                          {dep.status === "auth_required" && (
                            <div className="text-[11px] text-amber-500/80 mt-0.5">
                              Sign in with {dep.label} in your browser to finish setup
                            </div>
                          )}
                          {dep.status === "installed" && (
                            <div className="text-[11px] text-muted-foreground/60 mt-0.5">
                              Already signed in
                            </div>
                          )}
                        </div>
                        {dep.status === "auth_required" && (
                          <Button
                            size="sm"
                            variant="secondary"
                            onClick={async () => {
                              try {
                                if (dep.key === "codex") await commands.launchCodexAuth()
                                else await commands.launchClaudeAuth()
                              } catch {}
                            }}
                            className="text-[11px] h-6 px-2 text-amber-500 hover:text-amber-500"
                          >
                            Sign in
                          </Button>
                        )}
                        {dep.status === "installed" && (
                          <span className={`text-[11px] font-medium tabular-nums ${statusColor(dep.status)}`}>
                            Ready
                          </span>
                        )}
                      </div>
                    ))}
                </div>

                <div className="flex flex-col items-center gap-3">
                  {hasAuthRequired && !isInstalling && (
                    <div className="flex flex-col items-center gap-2 w-full">
                      <p className="text-[12px] text-muted-foreground text-center">
                        Complete the sign-in in your browser, then click Continue.
                      </p>
                      <Button
                        variant="secondary"
                        onClick={async () => {
                          await checkDeps()
                          const s = await commands.getSetupState()
                          if (s.providers.some(p => p.status === "installed_and_authenticated")) {
                            setStep("done")
                          }
                        }}
                        className="w-full"
                      >
                        Continue
                      </Button>
                    </div>
                  )}
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => setStep("provider")}
                  >
                    Back
                  </Button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
