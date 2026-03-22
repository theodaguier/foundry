import { create } from "zustand";
import type { AgentProvider } from "../lib/types";
import * as commands from "../lib/commands";

type Appearance = "system" | "light" | "dark";

interface SettingsStore {
  appearance: Appearance;
  modelCatalog: AgentProvider[];
  lastModelUpdate: string | null;
  isRefreshing: boolean;
  setAppearance: (a: Appearance) => void;
  loadCatalog: () => Promise<void>;
  refreshModels: () => Promise<void>;
}

export const useSettingsStore = create<SettingsStore>((set) => ({
  appearance: "dark",
  modelCatalog: [],
  lastModelUpdate: null,
  isRefreshing: false,

  setAppearance: (appearance) => set({ appearance }),

  loadCatalog: async () => {
    try {
      const catalog = await commands.getModelCatalog();
      set({ modelCatalog: catalog });
    } catch (e) {
      console.error("Failed to load model catalog:", e);
    }
  },

  refreshModels: async () => {
    set({ isRefreshing: true });
    try {
      const catalog = await commands.refreshModelCatalog();
      set({ modelCatalog: catalog, lastModelUpdate: new Date().toISOString() });
    } catch (e) {
      console.error("Failed to refresh models:", e);
    }
    set({ isRefreshing: false });
  },
}));
