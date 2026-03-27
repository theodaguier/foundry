import { describe, it, expect, vi, beforeEach } from "vitest"
import { useBuildStore } from "@/stores/build-store"

// Mock Tauri invoke
vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn().mockResolvedValue(undefined),
}))

// Mock commands
vi.mock("@/lib/commands", () => ({
  prepareBuildEnvironment: vi.fn().mockResolvedValue({ state: "ready" }),
  startGeneration: vi.fn().mockResolvedValue(undefined),
  startRefine: vi.fn().mockResolvedValue(undefined),
  cancelBuild: vi.fn().mockResolvedValue(undefined),
  rateGeneration: vi.fn().mockResolvedValue(undefined),
}))

describe("build-store", () => {
  beforeEach(() => {
    useBuildStore.getState().reset()
  })

  describe("handleComplete", () => {
    it("sets isRunning to false", () => {
      useBuildStore.setState({ isRunning: true })
      const plugin = makePlugin()
      useBuildStore.getState().handleComplete(plugin)
      expect(useBuildStore.getState().isRunning).toBe(false)
    })

    it("captures telemetryId from last plugin version", () => {
      const plugin = makePlugin({ telemetryId: "telem-123" })
      useBuildStore.getState().handleComplete(plugin)
      expect(useBuildStore.getState().lastCompletedTelemetryId).toBe("telem-123")
    })

    it("sets lastCompletedTelemetryId to null when plugin has no versions", () => {
      const plugin = makePlugin({ telemetryId: undefined })
      useBuildStore.getState().handleComplete({ ...plugin, versions: [] })
      expect(useBuildStore.getState().lastCompletedTelemetryId).toBeNull()
    })

    it("resets userRating to null on new completion", () => {
      useBuildStore.setState({ userRating: 1 })
      useBuildStore.getState().handleComplete(makePlugin())
      expect(useBuildStore.getState().userRating).toBeNull()
    })

    it("sets progress to 1", () => {
      useBuildStore.getState().handleComplete(makePlugin())
      expect(useBuildStore.getState().progress).toBe(1)
    })
  })

  describe("setUserRating", () => {
    it("stores the rating", async () => {
      useBuildStore.setState({ lastCompletedTelemetryId: "telem-abc" })
      useBuildStore.getState().setUserRating(1)
      expect(useBuildStore.getState().userRating).toBe(1)
    })

    it("calls rateGeneration with correct args", async () => {
      const { rateGeneration } = await import("@/lib/commands")
      useBuildStore.setState({ lastCompletedTelemetryId: "telem-xyz" })
      useBuildStore.getState().setUserRating(-1)
      expect(rateGeneration).toHaveBeenCalledWith("telem-xyz", -1)
    })

    it("does nothing when there is no telemetryId", () => {
      useBuildStore.setState({ lastCompletedTelemetryId: null })
      useBuildStore.getState().setUserRating(1)
      expect(useBuildStore.getState().userRating).toBeNull()
    })
  })

  describe("reset", () => {
    it("clears lastCompletedTelemetryId and userRating", () => {
      useBuildStore.setState({
        lastCompletedTelemetryId: "telem-123",
        userRating: 1,
      })
      useBuildStore.getState().reset()
      expect(useBuildStore.getState().lastCompletedTelemetryId).toBeNull()
      expect(useBuildStore.getState().userRating).toBeNull()
    })
  })
})

// ── Helpers ──────────────────────────────────────────────────────────────────

function makePlugin(opts: { telemetryId?: string } = {}) {
  return {
    id: "plugin-1",
    name: "TestPlugin",
    type: "effect" as const,
    prompt: "a warm reverb",
    createdAt: new Date().toISOString(),
    formats: ["AU" as const],
    installPaths: {},
    iconColor: "#ff0000",
    status: "installed" as const,
    currentVersion: 1,
    versions: opts.telemetryId !== undefined
      ? [{ id: "v1", pluginId: "plugin-1", versionNumber: 1, prompt: "a warm reverb",
           createdAt: new Date().toISOString(), installPaths: {}, iconColor: "#ff0000",
           isActive: true, telemetryId: opts.telemetryId }]
      : [],
  }
}
