import { create } from "zustand";
import type {
  GenerationStep,
  PipelineLogLine,
  Plugin,
  GenerationConfig,
  RefineConfig,
} from "@/lib/types";
import * as commands from "@/lib/commands";

interface BuildStore {
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

  startGeneration: (config: GenerationConfig) => Promise<void>;
  startRefine: (config: RefineConfig) => Promise<void>;
  cancel: () => Promise<void>;
  setShowConsole: (show: boolean) => void;
  tick: () => void;
  reset: () => void;
  handleStep: (step: GenerationStep) => void;
  handleLog: (line: PipelineLogLine) => void;
  handleStreaming: (text: string) => void;
  handleName: (name: string) => void;
  handleProgress: (progress: number) => void;
  handleBuildAttempt: (attempt: number) => void;
  handleComplete: (plugin: Plugin) => void;
  handleError: (message: string) => void;
}

const stepIndex: Record<GenerationStep, number> = {
  preparingEnvironment: 0,
  preparingProject: 1,
  generatingDSP: 2,
  generatingUI: 3,
  compiling: 4,
  installing: 5,
};

const generationVisibleIndex: Record<GenerationStep, number> = {
  preparingEnvironment: 0,
  preparingProject: 1,
  generatingDSP: 2,
  generatingUI: 3,
  compiling: 4,
  installing: 5,
};

const refineVisibleIndex: Record<GenerationStep, number> = {
  preparingEnvironment: 0,
  preparingProject: 0,
  generatingDSP: 1,
  generatingUI: 1,
  compiling: 2,
  installing: 3,
};

export const useBuildStore = create<BuildStore>((set, get) => ({
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

  startGeneration: async (config) => {
    set({
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
      config,
      refineConfig: null,
    });
    try {
      const environment = await commands.prepareBuildEnvironment(true);
      if (environment.state !== "ready") {
        set({ isRunning: false });
        return;
      }
      await commands.startGeneration(config);
    } catch (error) {
      console.error("Failed to start generation:", error);
      set({ isRunning: false });
    }
  },

  startRefine: async (config) => {
    set({
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
    });
    try {
      const environment = await commands.prepareBuildEnvironment(true);
      if (environment.state !== "ready") {
        set({ isRunning: false });
        return;
      }
      await commands.startRefine(config);
    } catch (error) {
      console.error("Failed to start refine:", error);
      set({ isRunning: false });
    }
  },

  cancel: async () => {
    await commands.cancelBuild();
    set({ isRunning: false });
  },
  setShowConsole: (show) => set({ showConsole: show }),
  tick: () => set((s) => ({ elapsedSeconds: s.elapsedSeconds + 1 })),
  reset: () =>
    set({
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
  handleProgress: (progress) => set({ progress }),
  handleBuildAttempt: (attempt) => set({ buildAttempt: attempt }),
  handleComplete: () => set({ isRunning: false, progress: 1 }),
  handleError: () => set({ isRunning: false }),
}));
