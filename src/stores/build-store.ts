import { create } from "zustand";
import type { GenerationStep, PipelineLogLine, Plugin, GenerationConfig, RefineConfig } from "../lib/types";
import * as commands from "../lib/commands";

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
  preparingProject: 0, generatingDSP: 1, generatingUI: 2, compiling: 3, installing: 4,
};

export const useBuildStore = create<BuildStore>((set, get) => ({
  isRunning: false,
  currentStep: "preparingProject",
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
    set({ isRunning: true, currentStep: "preparingProject", logLines: [], streamingText: "", generatedPluginName: null, buildAttempt: 0, elapsedSeconds: 0, completedSteps: new Set(), highWaterStep: 0, progress: 0, config, refineConfig: null });
    await commands.startGeneration(config);
  },

  startRefine: async (config) => {
    set({ isRunning: true, currentStep: "generatingDSP", logLines: [], streamingText: "", generatedPluginName: config.plugin.name, buildAttempt: 0, elapsedSeconds: 0, completedSteps: new Set(), highWaterStep: 0, progress: 0, config: null, refineConfig: config });
    await commands.startRefine(config);
  },

  cancel: async () => { await commands.cancelBuild(); set({ isRunning: false }); },
  setShowConsole: (show) => set({ showConsole: show }),
  tick: () => set((s) => ({ elapsedSeconds: s.elapsedSeconds + 1 })),
  reset: () => set({ isRunning: false, currentStep: "preparingProject", logLines: [], streamingText: "", generatedPluginName: null, buildAttempt: 0, elapsedSeconds: 0, completedSteps: new Set(), highWaterStep: 0, showConsole: false, progress: 0, config: null, refineConfig: null }),

  handleStep: (step) => {
    const idx = stepIndex[step];
    set((s) => {
      const newCompleted = new Set(s.completedSteps);
      if (idx > s.highWaterStep) newCompleted.add(stepIndex[s.currentStep]);
      const totalSteps = s.refineConfig ? 3 : 5;
      return { currentStep: step, highWaterStep: Math.max(s.highWaterStep, idx), completedSteps: newCompleted, progress: idx / totalSteps };
    });
  },

  handleLog: (line) => set((s) => ({ logLines: [...s.logLines, line] })),
  handleStreaming: (text) => set({ streamingText: text }),
  handleName: (name) => set({ generatedPluginName: name }),
  handleProgress: (progress) => set({ progress }),
  handleBuildAttempt: (attempt) => set({ buildAttempt: attempt }),
  handleComplete: () => set({ isRunning: false, progress: 1 }),
  handleError: () => set({ isRunning: false }),
}));
