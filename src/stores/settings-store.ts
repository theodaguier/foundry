import { create } from "zustand"
import type { AgentProvider, BuildEnvironmentStatus } from "@/lib/types"
import type { InstallPathsConfig } from "@/lib/commands"
import * as commands from "@/lib/commands"

type Appearance = "system" | "light" | "dark"

function applyTheme(appearance: Appearance) {
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
  const isDark = appearance === "dark" || (appearance === "system" && prefersDark)
  document.documentElement.classList.toggle("dark", isDark)
}

interface SettingsStore {
  appearance: Appearance
  modelCatalog: AgentProvider[]
  buildEnvironment: BuildEnvironmentStatus | null
  installPaths: InstallPathsConfig | null
  lastModelUpdate: string | null
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
}

export const useSettingsStore = create<SettingsStore>((set, get) => ({
  appearance: "dark",
  modelCatalog: [],
  buildEnvironment: null,
  installPaths: null,
  lastModelUpdate: null,
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
}))
