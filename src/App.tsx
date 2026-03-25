import { useEffect, useCallback, useRef } from "react"
import { useAppStore } from "@/stores/app-store"
import { useSettingsStore } from "@/stores/settings-store"
import { useBuildStore } from "@/stores/build-store"
import { useTauriEvent } from "@/hooks/use-tauri-event"
import { FoundryLogo } from "@/components/app/foundry-logo"
import { AppSidebar } from "@/components/app/sidebar"
import { SidebarProvider, SidebarInset } from "@/components/ui/sidebar"
import { Button } from "@/components/ui/button"
import { PluginDetailView } from "@/components/app/plugin-detail-view"
import AuthContainer from "@/pages/auth/auth-container"
import Onboarding from "@/pages/onboarding"
import Prompt from "@/pages/Prompt"
import GenerationProgress from "@/pages/generation-progress"
import ErrorPage from "@/pages/Error"
import Refine from "@/pages/Refine"
import Settings from "@/pages/Settings"
import BuildQueue from "@/pages/build-queue"
import Profile from "@/pages/profile"
import type { GenerationStep, PipelineLogLine } from "@/lib/types"

function LaunchScreen() {
  return (
    <div className="flex flex-col items-center justify-center h-full gap-4">
      <FoundryLogo height={48} className="text-muted-foreground" />
      <div className="w-4 h-4 border-2 border-muted-foreground/60 border-t-transparent rounded-full animate-spin" />
    </div>
  )
}

function EmptyState() {
  const plugins = useAppStore((s) => s.plugins)
  const setMainView = useAppStore((s) => s.setMainView)

  if (plugins.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-5">
        <FoundryLogo height={48} className="text-muted-foreground" />
        <div className="flex flex-col items-center gap-1.5">
          <h2 className="text-xl font-medium">Welcome to Foundry</h2>
          <p className="text-sm text-muted-foreground text-center">
            AI-powered audio plugin generator.<br />Describe it, build it, play it.
          </p>
        </div>
        <Button
          onClick={() => setMainView({ kind: "prompt" })}
          size="sm"
        >
          Build Your First Plugin
        </Button>
      </div>
    )
  }

  return (
    <div className="flex flex-col items-center justify-center h-full gap-3">
      <FoundryLogo height={36} className="text-muted-foreground/30" />
      <p className="text-sm text-muted-foreground/50">
        Select a plugin from the sidebar
      </p>
    </div>
  )
}

function MainContent() {
  const mainView = useAppStore((s) => s.mainView)
  const plugins = useAppStore((s) => s.plugins)

  switch (mainView.kind) {
    case "empty":
      return <EmptyState />

    case "detail": {
      const plugin = plugins.find((p) => p.id === mainView.pluginId)
      if (!plugin) return <EmptyState />
      return <PluginDetailView plugin={plugin} />
    }

    case "prompt":
      return <Prompt />

    case "generation":
      return <GenerationProgress mode="generation" />

    case "refinement":
      return <GenerationProgress mode="refinement" />

    case "refine": {
      const plugin = plugins.find((p) => p.id === mainView.pluginId)
      if (!plugin) return <EmptyState />
      return <Refine plugin={plugin} />
    }

    case "error":
      return <ErrorPage message={mainView.message} />

    case "settings":
      return <Settings />

    case "build-queue":
      return <BuildQueue />

    case "profile":
      return <Profile />

    default:
      return <EmptyState />
  }
}

/** Always-mounted component that listens to all pipeline Tauri events and updates the build store. */
function GlobalPipelineListener() {
  const handleStepAction = useBuildStore((s) => s.handleStep)
  const handleLogAction = useBuildStore((s) => s.handleLog)
  const handleNameAction = useBuildStore((s) => s.handleName)
  const handleErrorAction = useBuildStore((s) => s.handleError)
  const handleCompleteAction = useBuildStore((s) => s.handleComplete)
  const handleBuildAttemptAction = useBuildStore((s) => s.handleBuildAttempt)
  const isRunning = useBuildStore((s) => s.isRunning)
  const tick = useBuildStore((s) => s.tick)

  // Global elapsed timer
  useEffect(() => {
    if (!isRunning) return
    const interval = setInterval(() => tick(), 1000)
    return () => clearInterval(interval)
  }, [isRunning, tick])

  const handleStep = useCallback(
    (payload: { step: GenerationStep }) => handleStepAction(payload.step),
    [handleStepAction],
  )
  const handleLog = useCallback(
    (payload: PipelineLogLine) => handleLogAction(payload),
    [handleLogAction],
  )
  const handleName = useCallback(
    (payload: { name: string }) => handleNameAction(payload.name),
    [handleNameAction],
  )
  const handleStreaming = useCallback((payload: { text: string }) => {
    useBuildStore.getState().handleStreaming(payload.text)
  }, [])
  const handleError = useCallback(
    (payload: { message: string }) => {
      handleErrorAction(payload.message)
      useAppStore.getState().setMainView({ kind: "error", message: payload.message })
    },
    [handleErrorAction],
  )
  const handleComplete = useCallback(
    (payload: { plugin: any }) => {
      handleCompleteAction(payload.plugin)
      useAppStore.getState().loadPlugins()
      useAppStore.getState().setMainView({ kind: "detail", pluginId: payload.plugin.id })
    },
    [handleCompleteAction],
  )
  const handleBuildAttempt = useCallback(
    (payload: { attempt: number }) => handleBuildAttemptAction(payload.attempt),
    [handleBuildAttemptAction],
  )

  useTauriEvent("pipeline:step", handleStep)
  useTauriEvent("pipeline:log", handleLog)
  useTauriEvent("pipeline:name", handleName)
  useTauriEvent("pipeline:streaming", handleStreaming)
  useTauriEvent("pipeline:error", handleError)
  useTauriEvent("pipeline:complete", handleComplete)
  useTauriEvent("pipeline:build_attempt", handleBuildAttempt)

  return null
}

function GlobalAppUpdateManager() {
  const authState = useAppStore((s) => s.authState)
  const loadAppVersion = useSettingsStore((s) => s.loadAppVersion)
  const checkForAppUpdate = useSettingsStore((s) => s.checkForAppUpdate)
  const didAutoCheck = useRef(false)

  useEffect(() => {
    void loadAppVersion()
  }, [loadAppVersion])

  useEffect(() => {
    if (authState === "checking" || didAutoCheck.current) return
    didAutoCheck.current = true
    void checkForAppUpdate(false)
  }, [authState, checkForAppUpdate])

  return null
}

export default function App() {
  const authState = useAppStore((s) => s.authState)
  const checkSession = useAppStore((s) => s.checkSession)
  const loadPlugins = useAppStore((s) => s.loadPlugins)
  const onboardingComplete = useAppStore((s) => s.onboardingComplete)
  const checkOnboarding = useAppStore((s) => s.checkOnboarding)

  const initTheme = useSettingsStore((s) => s.initTheme)
  const loadBuildEnvironment = useSettingsStore((s) => s.loadBuildEnvironment)
  const loadCatalog = useSettingsStore((s) => s.loadCatalog)
  const loadInstallPaths = useSettingsStore((s) => s.loadInstallPaths)
  const installPaths = useSettingsStore((s) => s.installPaths)
  const titlebarInset = installPaths?.platform === "macos" ? 52 : 0

  useEffect(() => { initTheme() }, [initTheme])
  useEffect(() => { loadBuildEnvironment() }, [loadBuildEnvironment])
  useEffect(() => { loadCatalog() }, [loadCatalog])
  useEffect(() => { loadInstallPaths() }, [loadInstallPaths])
  useEffect(() => { checkSession() }, [checkSession])

  useEffect(() => {
    if (authState === "authenticated") {
      checkOnboarding()
      loadPlugins()
    }
  }, [authState, checkOnboarding, loadPlugins])

  if (authState === "checking") {
    return <LaunchScreen />
  }

  if (authState === "unauthenticated") {
    return <AuthContainer />
  }

  if (onboardingComplete === null) {
    return <LaunchScreen />
  }

  if (!onboardingComplete) {
    return (
      <div className="flex flex-col h-full">
        <div
          data-tauri-drag-region
          className="shrink-0 select-none"
          style={{ height: titlebarInset }}
        >
          {titlebarInset > 0 && <div className="w-[78px] h-full shrink-0" data-tauri-drag-region />}
        </div>
        <div className="flex-1 overflow-hidden">
          <Onboarding />
        </div>
      </div>
    )
  }

  return (
    <SidebarProvider open={true}>
      <GlobalPipelineListener />
      <GlobalAppUpdateManager />
      <AppSidebar />
      <SidebarInset>
        {/* Drag region for main content area */}
        <div
          data-tauri-drag-region
          className="shrink-0 select-none"
          style={{ height: titlebarInset }}
        />
        <div className="flex-1 overflow-hidden">
          <MainContent />
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
