import { create } from "zustand"
import { getVersion } from "@tauri-apps/api/app"
import * as appUpdate from "@/lib/app-update"
import type {
  AgentProvider,
  AppUpdateInfo,
  AppUpdateStatus,
  BuildEnvironmentStatus,
} from "@/lib/types"
import type { InstallPathsConfig } from "@/lib/commands"
import { useBuildStore } from "@/stores/build-store"
import * as commands from "@/lib/commands"

type Appearance = "system" | "light" | "dark"

function applyTheme(appearance: Appearance) {
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
  const isDark = appearance === "dark" || (appearance === "system" && prefersDark)
  document.documentElement.classList.toggle("dark", isDark)
}

function toErrorMessage(error: unknown) {
  if (error instanceof Error) return error.message
  return String(error)
}

interface SettingsStore {
  appearance: Appearance
  modelCatalog: AgentProvider[]
  buildEnvironment: BuildEnvironmentStatus | null
  installPaths: InstallPathsConfig | null
  appVersion: string
  updateStatus: AppUpdateStatus
  availableUpdate: AppUpdateInfo | null
  lastModelUpdate: string | null
  lastUpdateCheck: string | null
  updateError: string | null
  downloadProgress: { downloaded: number; total: number | null } | null
  isRefreshing: boolean
  isLoadingBuildEnvironment: boolean
  isPreparingEnvironment: boolean
  setAppearance: (a: Appearance) => void
  initTheme: () => void
  loadCatalog: () => Promise<void>
  refreshModels: () => Promise<void>
  loadBuildEnvironment: () => Promise<BuildEnvironmentStatus | null>
  installManagedJuce: () => Promise<BuildEnvironmentStatus | null>
  setJuceOverride: (path: string) => Promise<BuildEnvironmentStatus | null>
  clearJuceOverride: () => Promise<BuildEnvironmentStatus | null>
  loadInstallPaths: () => Promise<void>
  setInstallPath: (format: string, path: string) => Promise<void>
  resetInstallPath: (format: string) => Promise<void>
  loadAppVersion: () => Promise<void>
  checkForAppUpdate: (manual?: boolean) => Promise<void>
  installAppUpdate: () => Promise<void>
  clearUpdateError: () => void
}

export const useSettingsStore = create<SettingsStore>((set, get) => ({
  appearance: "dark",
  modelCatalog: [],
  buildEnvironment: null,
  installPaths: null,
  appVersion: "",
  updateStatus: "idle",
  availableUpdate: null,
  lastModelUpdate: null,
  lastUpdateCheck: null,
  updateError: null,
  downloadProgress: null,
  isRefreshing: false,
  isLoadingBuildEnvironment: false,
  isPreparingEnvironment: false,

  setAppearance: (appearance) => {
    applyTheme(appearance)
    set({ appearance })
  },

  initTheme: () => {
    const { appearance } = get()
    applyTheme(appearance)

    // Listen for system theme changes when in "system" mode
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      const current = get().appearance
      if (current === "system") applyTheme("system")
    })
  },

  loadCatalog: async () => {
    try {
      const catalog = await commands.getModelCatalog()
      set({ modelCatalog: catalog })
    } catch (e) {
      console.error("Failed to load model catalog:", e)
    }
  },

  refreshModels: async () => {
    set({ isRefreshing: true })
    try {
      const catalog = await commands.refreshModelCatalog()
      set({ modelCatalog: catalog, lastModelUpdate: new Date().toISOString() })
    } catch (e) {
      console.error("Failed to refresh models:", e)
    }
    set({ isRefreshing: false })
  },

  loadBuildEnvironment: async () => {
    set({ isLoadingBuildEnvironment: true })
    try {
      const buildEnvironment = await commands.getBuildEnvironment()
      set({ buildEnvironment })
      return buildEnvironment
    } catch (e) {
      console.error("Failed to load build environment:", e)
      return null
    } finally {
      set({ isLoadingBuildEnvironment: false })
    }
  },

  installManagedJuce: async () => {
    set({ isPreparingEnvironment: true })
    try {
      const buildEnvironment = await commands.installJuce()
      set({ buildEnvironment })
      return buildEnvironment
    } catch (e) {
      console.error("Failed to install managed JUCE:", e)
      return null
    } finally {
      set({ isPreparingEnvironment: false })
    }
  },

  setJuceOverride: async (path) => {
    set({ isPreparingEnvironment: true })
    try {
      const buildEnvironment = await commands.setJuceOverridePath(path)
      set({ buildEnvironment })
      return buildEnvironment
    } catch (e) {
      console.error("Failed to set JUCE override:", e)
      return null
    } finally {
      set({ isPreparingEnvironment: false })
    }
  },

  clearJuceOverride: async () => {
    set({ isPreparingEnvironment: true })
    try {
      const buildEnvironment = await commands.clearJuceOverridePath()
      set({ buildEnvironment })
      return buildEnvironment
    } catch (e) {
      console.error("Failed to clear JUCE override:", e)
      return null
    } finally {
      set({ isPreparingEnvironment: false })
    }
  },

  loadInstallPaths: async () => {
    try {
      const installPaths = await commands.getInstallPaths()
      set({ installPaths })
    } catch (e) {
      console.error("Failed to load install paths:", e)
    }
  },

  setInstallPath: async (format, path) => {
    try {
      const installPaths = await commands.setInstallPath(format, path)
      set({ installPaths })
    } catch (e) {
      console.error("Failed to set install path:", e)
    }
  },

  resetInstallPath: async (format) => {
    try {
      const installPaths = await commands.resetInstallPath(format)
      set({ installPaths })
    } catch (e) {
      console.error("Failed to reset install path:", e)
    }
  },

  loadAppVersion: async () => {
    try {
      const appVersion = await getVersion()
      set({ appVersion })
    } catch (e) {
      console.error("Failed to load app version:", e)
    }
  },

  checkForAppUpdate: async (manual = false) => {
    const previousStatus = get().updateStatus
    const checkedAt = new Date().toISOString()

    set({
      updateStatus: "checking",
      updateError: null,
      downloadProgress: null,
    })

    try {
      const availableUpdate = await appUpdate.checkForPreparedUpdate()
      set({
        availableUpdate,
        lastUpdateCheck: checkedAt,
        updateStatus: availableUpdate ? "available" : "not-available",
        updateError: null,
        downloadProgress: null,
      })
    } catch (error) {
      const message = toErrorMessage(error)
      await appUpdate.clearPreparedUpdate().catch(() => {})

      if (manual) {
        set({
          lastUpdateCheck: checkedAt,
          updateStatus: "error",
          updateError: message,
          downloadProgress: null,
        })
        return
      }

      console.error("Automatic update check failed:", error)
      set({
        lastUpdateCheck: checkedAt,
        updateStatus: previousStatus === "checking" ? "idle" : previousStatus,
        updateError: null,
        downloadProgress: null,
      })
    }
  },

  installAppUpdate: async () => {
    if (useBuildStore.getState().isRunning) {
      set({
        updateStatus: "error",
        updateError: "Finish the current build before installing the app update.",
      })
      return
    }

    if (!get().availableUpdate) {
      set({
        updateStatus: "error",
        updateError: "No update is available to install.",
      })
      return
    }

    set({
      updateStatus: "downloading",
      updateError: null,
      downloadProgress: { downloaded: 0, total: null },
    })

    try {
      await appUpdate.installPreparedUpdate((event) => {
        switch (event.event) {
          case "Started":
            set({
              updateStatus: "downloading",
              downloadProgress: {
                downloaded: 0,
                total: event.data.contentLength ?? null,
              },
            })
            break
          case "Progress":
            set((state) => ({
              updateStatus: "downloading",
              downloadProgress: {
                downloaded:
                  (state.downloadProgress?.downloaded ?? 0) + event.data.chunkLength,
                total: state.downloadProgress?.total ?? null,
              },
            }))
            break
          case "Finished":
            set({
              updateStatus: "installing",
              downloadProgress: null,
            })
            break
        }
      })
    } catch (error) {
      console.error("Failed to install app update:", error)
      set({
        updateStatus: "error",
        updateError: toErrorMessage(error),
        downloadProgress: null,
      })
    }
  },

  clearUpdateError: () =>
    set((state) => ({
      updateError: null,
      updateStatus:
        state.updateStatus === "error"
          ? state.availableUpdate
            ? "available"
            : "idle"
          : state.updateStatus,
    })),
}))
