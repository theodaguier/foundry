import { useEffect, useCallback } from "react"
import { Routes, Route, useNavigate, useLocation } from "react-router-dom"
import { useAppStore } from "@/stores/app-store"
import { useSettingsStore } from "@/stores/settings-store"
import { useBuildStore } from "@/stores/build-store"
import { useTauriEvent } from "@/hooks/use-tauri-event"
import { FoundryLogo } from "@/components/app/foundry-logo"
import AuthContainer from "@/pages/auth/auth-container"
import Welcome from "@/pages/welcome"
import PluginLibrary from "@/pages/plugin-library"
import Prompt from "@/pages/prompt"
import QuickOptions from "@/pages/quick-options"
import GenerationProgress from "@/pages/generation-progress"
import Result from "@/pages/result"
import ErrorPage from "@/pages/error"
import Refine from "@/pages/refine"
import Settings from "@/pages/settings"
import BuildQueue from "@/pages/build-queue"
import type { GenerationStep, PipelineLogLine } from "@/lib/types"

function LaunchScreen() {
  return (
    <div className="flex flex-col items-center justify-center h-full gap-4">
      <FoundryLogo height={48} className="text-muted-foreground" />
      <div className="w-4 h-4 border-2 border-muted-foreground/60 border-t-transparent rounded-full animate-spin" />
    </div>
  )
}

/** Always-mounted component that listens to all pipeline Tauri events and updates the build store. */
function GlobalPipelineListener() {
  const navigate = useNavigate()
  const handleStepAction = useBuildStore((s) => s.handleStep)
  const handleLogAction = useBuildStore((s) => s.handleLog)
  const handleNameAction = useBuildStore((s) => s.handleName)
  const handleErrorAction = useBuildStore((s) => s.handleError)
  const handleCompleteAction = useBuildStore((s) => s.handleComplete)
  const handleBuildAttemptAction = useBuildStore((s) => s.handleBuildAttempt)
  const isRunning = useBuildStore((s) => s.isRunning)
  const tick = useBuildStore((s) => s.tick)

  // Global elapsed timer — runs regardless of which page is visible
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
      navigate("/error", { state: { message: payload.message } })
    },
    [handleErrorAction, navigate],
  )
  const handleComplete = useCallback(
    (payload: { plugin: any }) => {
      handleCompleteAction(payload.plugin)
      useAppStore.getState().loadPlugins()
      navigate(`/result/${payload.plugin.id}`)
    },
    [handleCompleteAction, navigate],
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

const noBackRoutes = new Set(["/"])

function TitleBar() {
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const showBack = !noBackRoutes.has(pathname)

  return (
    <div
      data-tauri-drag-region
      className="titlebar h-[52px] shrink-0 select-none flex items-center"
    >
      {/* Space for macOS traffic lights */}
      <div className="w-[78px] shrink-0" data-tauri-drag-region />

      {showBack && (
        <button
          onClick={() => navigate(-1)}
          className="titlebar-back-btn"
        >
          <svg width="10" height="16" viewBox="0 0 10 16" fill="none">
            <path
              d="M8.5 1L1.5 8L8.5 15"
              stroke="currentColor"
              strokeWidth="1.8"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </button>
      )}
    </div>
  )
}

export default function App() {
  const authState = useAppStore((s) => s.authState)
  const checkSession = useAppStore((s) => s.checkSession)
  const loadPlugins = useAppStore((s) => s.loadPlugins)
  const plugins = useAppStore((s) => s.plugins)
  const initTheme = useSettingsStore((s) => s.initTheme)
  const loadBuildEnvironment = useSettingsStore((s) => s.loadBuildEnvironment)

  useEffect(() => {
    initTheme()
  }, [initTheme])

  useEffect(() => {
    loadBuildEnvironment()
  }, [loadBuildEnvironment])

  useEffect(() => {
    checkSession()
  }, [checkSession])

  useEffect(() => {
    if (authState === "authenticated") {
      loadPlugins()
    }
  }, [authState, loadPlugins])

  if (authState === "checking") {
    return <LaunchScreen />
  }

  if (authState === "unauthenticated") {
    return <AuthContainer />
  }

  return (
    <div className="flex flex-col h-full">
      <GlobalPipelineListener />
      <TitleBar />

      <div className="flex-1 overflow-hidden">
        <Routes>
          <Route
            path="/"
            element={
              plugins.length === 0 ? <Welcome /> : <PluginLibrary />
            }
          />
          <Route path="/prompt" element={<Prompt />} />
          <Route path="/quick-options" element={<QuickOptions />} />
          <Route path="/generation" element={<GenerationProgress mode="generation" />} />
          <Route path="/refinement" element={<GenerationProgress mode="refinement" />} />
          <Route path="/refine/:pluginId" element={<Refine />} />
          <Route path="/result/:pluginId" element={<Result />} />
          <Route path="/error" element={<ErrorPage />} />
          <Route path="/queue" element={<BuildQueue />} />
          <Route path="/settings" element={<Settings />} />
        </Routes>
      </div>
    </div>
  )
}
