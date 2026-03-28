import { create } from "zustand";
import type {
  GenerationStep,
  PipelineLogLine,
  Plugin,
  GenerationConfig,
  GenerationDebugContext,
  RefineConfig,
} from "@/lib/types";
import * as commands from "@/lib/commands"
import {
  trackGenerationStarted,
  trackGenerationCompleted,
  trackGenerationRated,
  trackRefineStarted,
} from "@/lib/analytics";
import { useAppStore } from "@/stores/app-store";

function stripDebugConfig(config: GenerationConfig): GenerationConfig {
  const { debugPipeline, debugContext, ...baseConfig } = config;
  return baseConfig;
}

function buildDebugContext(
  message: string | null,
  logLines: PipelineLogLine[],
): GenerationDebugContext {
  return {
    trigger: "retry-after-failure",
    previousError: message ?? "",
    recentLogs: logLines.slice(-12).map((line) => `${line.timestamp} ${line.message}`),
  };
}

interface BuildStore {
  activePluginId: string | null;
  isRunning: boolean;
  currentStep: GenerationStep;
  logLines: PipelineLogLine[];
  streamingText: string;
  generatedPluginName: string | null;
  buildAttempt: number;
  elapsedSeconds: number;
  completedSteps: Set<number>;
  highWaterStep: number;
  showConsole: boolean;
  progress: number;
  config: GenerationConfig | null;
  refineConfig: RefineConfig | null;
  lastErrorMessage: string | null;
  lastCompletedTelemetryId: string | null;
  userRating: 1 | -1 | null;
  setUserRating: (rating: 1 | -1) => void;

  startGeneration: (config: GenerationConfig) => Promise<void>;
  retryPlugin: (plugin: Plugin) => Promise<void>;
  retryGenerationWithDebug: () => Promise<void>;
  startRefine: (config: RefineConfig) => Promise<void>;
  cancel: () => Promise<void>;
  setShowConsole: (show: boolean) => void;
  tick: () => void;
  reset: () => void;
  handleStep: (step: GenerationStep) => void;
  handleLog: (line: PipelineLogLine) => void;
  handleStreaming: (text: string) => void;
  handleName: (name: string) => void;
  handleRegistered: (plugin: Plugin) => void;
  handleProgress: (progress: number) => void;
  handleBuildAttempt: (attempt: number) => void;
  handleComplete: (plugin: Plugin) => void;
  handleError: (message: string) => void;
}

const stepIndex: Record<GenerationStep, number> = {
  preparingEnvironment: 0,
  preparingProject: 1,
  generating: 2,
  compiling: 3,
  installing: 4,
};

const generationVisibleIndex: Record<GenerationStep, number> = {
  preparingEnvironment: 0,
  preparingProject: 1,
  generating: 2,
  compiling: 3,
  installing: 4,
};

const refineVisibleIndex: Record<GenerationStep, number> = {
  preparingEnvironment: 0,
  preparingProject: 0,
  generating: 1,
  compiling: 2,
  installing: 3,
};

function inferFormat(plugin: Plugin): GenerationConfig["format"] {
  const hasAu = plugin.formats.includes("AU");
  const hasVst3 = plugin.formats.includes("VST3");
  if (hasAu && hasVst3) return "Both";
  if (hasAu) return "AU";
  if (hasVst3) return "VST3";
  return "Both";
}

function inferAgent(plugin: Plugin): string {
  if (plugin.generationConfig?.agent) return plugin.generationConfig.agent;
  if (plugin.agent === "Codex") return "Codex";
  return "Claude Code";
}

function inferModel(plugin: Plugin): string {
  return plugin.generationConfig?.model || plugin.model?.flag || plugin.model?.id || "sonnet";
}

function buildRetryConfig(plugin: Plugin): GenerationConfig {
  const config = plugin.generationConfig;
  return {
    prompt: config?.prompt ?? plugin.prompt,
    pluginType: config?.pluginType ?? plugin.type,
    format: config?.format ?? inferFormat(plugin),
    channelLayout: config?.channelLayout ?? "Stereo",
    presetCount: config?.presetCount ?? 5,
    agent: inferAgent(plugin),
    model: inferModel(plugin),
    resumePluginId: plugin.id,
    resumePluginName: plugin.name,
  };
}

export const useBuildStore = create<BuildStore>((set, get) => ({
  activePluginId: null,
  isRunning: false,
  currentStep: "preparingEnvironment",
  logLines: [],
  streamingText: "",
  generatedPluginName: null,
  buildAttempt: 0,
  elapsedSeconds: 0,
  completedSteps: new Set(),
  highWaterStep: 0,
  showConsole: false,
  progress: 0,
  config: null,
  refineConfig: null,
  lastErrorMessage: null,
  lastCompletedTelemetryId: null,
  userRating: null,

  startGeneration: async (config) => {
    set({
      activePluginId: config.resumePluginId ?? null,
      isRunning: true,
      currentStep: "preparingEnvironment",
      logLines: [],
      streamingText: "",
      generatedPluginName: null,
      buildAttempt: 0,
      elapsedSeconds: 0,
      completedSteps: new Set(),
      highWaterStep: 0,
      progress: 0,
      config: stripDebugConfig(config),
      refineConfig: null,
      lastErrorMessage: null,
    });
    try {
      const environment = await commands.prepareBuildEnvironment(true);
      if (environment.state !== "ready") {
        set({ isRunning: false });
        return;
      }
      trackGenerationStarted({
        pluginType: config.pluginType ?? "unknown",
        agent: config.agent,
        model: config.model,
        format: config.format,
      });
      await commands.startGeneration(config);
    } catch (error) {
      console.error("Failed to start generation:", error);
      set({ isRunning: false });
    }
  },

  retryPlugin: async (plugin) => {
    await get().startGeneration(buildRetryConfig(plugin));
  },

  retryGenerationWithDebug: async () => {
    const { config, lastErrorMessage, logLines, startGeneration } = get();
    if (!config) return;

    await startGeneration({
      ...config,
      debugPipeline: true,
      debugContext: buildDebugContext(lastErrorMessage, logLines),
    });
  },

  startRefine: async (config) => {
    set({
      activePluginId: null,
      isRunning: true,
      currentStep: "preparingEnvironment",
      logLines: [],
      streamingText: "",
      generatedPluginName: config.plugin.name,
      buildAttempt: 0,
      elapsedSeconds: 0,
      completedSteps: new Set(),
      highWaterStep: 0,
      progress: 0,
      config: null,
      refineConfig: config,
      lastErrorMessage: null,
    });
    try {
      const environment = await commands.prepareBuildEnvironment(true);
      if (environment.state !== "ready") {
        set({ isRunning: false });
        return;
      }
      trackRefineStarted({ agent: config.plugin.agent ?? "unknown", model: config.plugin.model?.id ?? "unknown" });
      await commands.startRefine(config);
    } catch (error) {
      console.error("Failed to start refine:", error);
      set({ isRunning: false });
    }
  },

  cancel: async () => {
    await commands.cancelBuild();
    set({ isRunning: false });
    await useAppStore.getState().loadPlugins();
  },
  setShowConsole: (show) => set({ showConsole: show }),
  tick: () => set((s) => ({ elapsedSeconds: s.elapsedSeconds + 1 })),
  setUserRating: (rating) => {
    const { lastCompletedTelemetryId } = get();
    if (!lastCompletedTelemetryId) return;
    set({ userRating: rating });
    commands.rateGeneration(lastCompletedTelemetryId, rating).catch(console.error);
    trackGenerationRated({ rating, telemetryId: lastCompletedTelemetryId });
  },

  reset: () =>
    set({
      activePluginId: null,
      isRunning: false,
      currentStep: "preparingEnvironment",
      logLines: [],
      streamingText: "",
      generatedPluginName: null,
      buildAttempt: 0,
      elapsedSeconds: 0,
      completedSteps: new Set(),
      highWaterStep: 0,
      showConsole: false,
      progress: 0,
      config: null,
      refineConfig: null,
      lastErrorMessage: null,
      lastCompletedTelemetryId: null,
      userRating: null,
    }),

  handleStep: (step) => {
    const idx = stepIndex[step];
    set((s) => {
      const newCompleted = new Set(s.completedSteps);
      if (idx > s.highWaterStep) newCompleted.add(stepIndex[s.currentStep]);
      const visibleSteps = s.refineConfig ? 4 : 6;
      const visibleIndex = s.refineConfig
        ? refineVisibleIndex[step]
        : generationVisibleIndex[step];
      return {
        currentStep: step,
        highWaterStep: Math.max(s.highWaterStep, idx),
        completedSteps: newCompleted,
        progress: visibleIndex / Math.max(visibleSteps - 1, 1),
      };
    });
  },

  handleLog: (line) =>
    set((s) => {
      const lastLine = s.logLines[s.logLines.length - 1];
      if (
        lastLine &&
        lastLine.timestamp === line.timestamp &&
        lastLine.message === line.message
      ) {
        return s;
      }
      return { logLines: [...s.logLines, line] };
    }),
  handleStreaming: (text) =>
    set((s) => ({
      streamingText: text === "" ? "" : `${s.streamingText}${text}`,
    })),
  handleName: (name) => set({ generatedPluginName: name }),
  handleRegistered: (plugin) =>
    set((s) => ({
      activePluginId: plugin.id,
      generatedPluginName: plugin.name,
      config: s.config
        ? {
            ...s.config,
            resumePluginId: plugin.id,
            resumePluginName: plugin.name,
          }
        : s.config,
    })),
  handleProgress: (progress) => set({ progress }),
  handleBuildAttempt: (attempt) => set({ buildAttempt: attempt }),
  handleComplete: (plugin) => {
    const lastVersion = plugin?.versions?.[plugin.versions.length - 1];
    const telemetryId = lastVersion?.telemetryId ?? null;
    const { elapsedSeconds, buildAttempt, config } = get();
    set({
      activePluginId: null,
      isRunning: false,
      progress: 1,
      lastErrorMessage: null,
      lastCompletedTelemetryId: telemetryId,
      userRating: null,
    });
    trackGenerationCompleted({
      pluginType: config?.pluginType ?? "unknown",
      agent: config?.agent ?? "unknown",
      model: config?.model ?? "unknown",
      outcome: "success",
      durationSeconds: elapsedSeconds,
      buildAttempts: buildAttempt,
    });
  },
  handleError: (message) => {
    const { config, elapsedSeconds, buildAttempt } = get();
    set({ isRunning: false, lastErrorMessage: message });
    trackGenerationCompleted({
      pluginType: config?.pluginType ?? "unknown",
      agent: config?.agent ?? "unknown",
      model: config?.model ?? "unknown",
      outcome: "failed",
      durationSeconds: elapsedSeconds,
      buildAttempts: buildAttempt,
    });
  },
}));
