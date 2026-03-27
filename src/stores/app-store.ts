import { create } from "zustand";
import type { Plugin, AuthState, UserProfile, PluginFilter, RawUserProfile } from "@/lib/types"
import * as commands from "@/lib/commands"
import { identifyUser, resetUser } from "@/lib/analytics"

export type MainView =
  | { kind: "empty" }
  | { kind: "detail"; pluginId: string }
  | { kind: "prompt" }
  | { kind: "refine"; pluginId: string }
  | { kind: "generation" }
  | { kind: "refinement" }
  | { kind: "error"; message: string }
  | { kind: "settings" }
  | { kind: "build-queue" }
  | { kind: "profile" }

interface AppStore {
  authState: AuthState;
  userProfile: UserProfile | null;
  plugins: Plugin[];
  filter: PluginFilter;
  selectedPlugin: Plugin | null;
  showSetup: boolean;
  onboardingComplete: boolean | null;
  mainView: MainView;
  sidebarCollapsed: boolean;

  setAuthState: (state: AuthState) => void;
  setUserProfile: (profile: UserProfile | null) => void;
  setFilter: (filter: PluginFilter) => void;
  setSelectedPlugin: (plugin: Plugin | null) => void;
  setShowSetup: (show: boolean) => void;
  setMainView: (view: MainView) => void;
  toggleSidebar: () => void;
  loadPlugins: () => Promise<void>;
  deletePlugin: (id: string) => Promise<void>;
  renamePlugin: (id: string, newName: string) => Promise<void>;
  signOut: () => Promise<void>;
  checkSession: () => Promise<void>;
  checkOnboarding: () => Promise<void>;
  filteredPlugins: () => Plugin[];
}

export const useAppStore = create<AppStore>((set, get) => ({
  authState: "checking",
  userProfile: null,
  plugins: [],
  filter: "ALL",
  selectedPlugin: null,
  showSetup: false,
  onboardingComplete: null,
  mainView: { kind: "empty" },
  sidebarCollapsed: false,

  setAuthState: (authState) => set({ authState }),
  setUserProfile: (userProfile) => set({ userProfile }),
  setFilter: (filter) => set({ filter }),
  setSelectedPlugin: (selectedPlugin) => set({ selectedPlugin }),
  setShowSetup: (showSetup) => set({ showSetup }),
  setMainView: (mainView) => set({ mainView }),
  toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),

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
    resetUser();
  },

  checkSession: async () => {
    set({ authState: "checking" });
    try {
      const userId = await commands.checkSession();
      if (userId) {
        set({ authState: "authenticated" });
        const profile = await commands.getProfile(userId) as RawUserProfile | null;
        if (profile) {
          // Map snake_case from Supabase to camelCase
          const mapped: UserProfile = {
            ...profile,
            id: profile.id ?? userId,
            email: profile.email ?? "",
            plan: profile.plan ?? "free",
            displayName: profile.display_name ?? profile.displayName,
            avatarUrl: profile.avatar_url ?? profile.avatarUrl,
            pluginsGenerated: profile.plugins_generated ?? profile.pluginsGenerated ?? 0,
            createdAt: profile.created_at ?? profile.createdAt ?? new Date(0).toISOString(),
            onboardingCompletedAt: profile.onboarding_completed_at ?? profile.onboardingCompletedAt,
            cardVariant: profile.card_variant ?? profile.cardVariant ?? "default",
          };
          set({ userProfile: mapped });
          identifyUser(mapped.id, {
            email: mapped.email,
            plan: mapped.plan,
            plugins_generated: mapped.pluginsGenerated,
          });
        }
      } else {
        set({ authState: "unauthenticated" });
      }
    } catch {
      set({ authState: "unauthenticated" });
    }
  },

  checkOnboarding: async () => {
    try {
      const state = await commands.getOnboardingState();
      set({ onboardingComplete: state.completed });
    } catch (e) {
      console.error("Failed to check onboarding:", e);
      set({ onboardingComplete: false });
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
