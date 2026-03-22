import { create } from "zustand";
import type { Plugin, AuthState, UserProfile, PluginFilter } from "../lib/types";
import * as commands from "../lib/commands";

interface AppStore {
  authState: AuthState;
  userProfile: UserProfile | null;
  plugins: Plugin[];
  filter: PluginFilter;
  selectedPlugin: Plugin | null;
  showSetup: boolean;

  setAuthState: (state: AuthState) => void;
  setUserProfile: (profile: UserProfile | null) => void;
  setFilter: (filter: PluginFilter) => void;
  setSelectedPlugin: (plugin: Plugin | null) => void;
  setShowSetup: (show: boolean) => void;
  loadPlugins: () => Promise<void>;
  deletePlugin: (id: string) => Promise<void>;
  renamePlugin: (id: string, newName: string) => Promise<void>;
  signOut: () => Promise<void>;
  checkSession: () => Promise<void>;
  filteredPlugins: () => Plugin[];
}

export const useAppStore = create<AppStore>((set, get) => ({
  authState: "checking",
  userProfile: null,
  plugins: [],
  filter: "ALL",
  selectedPlugin: null,
  showSetup: false,

  setAuthState: (authState) => set({ authState }),
  setUserProfile: (userProfile) => set({ userProfile }),
  setFilter: (filter) => set({ filter }),
  setSelectedPlugin: (selectedPlugin) => set({ selectedPlugin }),
  setShowSetup: (showSetup) => set({ showSetup }),

  loadPlugins: async () => {
    try {
      const plugins = await commands.loadPlugins();
      set({ plugins });
    } catch (e) {
      console.error("Failed to load plugins:", e);
    }
  },

  deletePlugin: async (id) => {
    try {
      await commands.deletePlugin(id);
      set((s) => ({ plugins: s.plugins.filter((p) => p.id !== id) }));
    } catch (e) {
      console.error("Failed to delete plugin:", e);
    }
  },

  renamePlugin: async (id, newName) => {
    try {
      await commands.renamePlugin(id, newName);
      set((s) => ({
        plugins: s.plugins.map((p) => (p.id === id ? { ...p, name: newName } : p)),
      }));
    } catch (e) {
      console.error("Failed to rename plugin:", e);
    }
  },

  signOut: async () => {
    try { await commands.signOut(); } catch {}
    set({ authState: "unauthenticated", userProfile: null });
  },

  checkSession: async () => {
    set({ authState: "checking" });
    try {
      const userId = await commands.checkSession();
      if (userId) {
        set({ authState: "authenticated" });
        const profile = await commands.getProfile(userId);
        if (profile) set({ userProfile: profile });
      } else {
        // Auth not yet implemented — auto-authenticate for development
        set({ authState: "authenticated" });
      }
    } catch {
      // Auth not yet implemented — auto-authenticate for development
      set({ authState: "authenticated" });
    }
  },

  filteredPlugins: () => {
    const { plugins, filter } = get();
    let result = [...plugins];
    switch (filter) {
      case "INSTRUMENTS": result = result.filter((p) => p.type === "instrument"); break;
      case "EFFECTS": result = result.filter((p) => p.type === "effect"); break;
      case "UTILITIES": result = result.filter((p) => p.type === "utility"); break;
    }
    return result.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
  },
}));
