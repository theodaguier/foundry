import { invoke } from "@tauri-apps/api/core";
import {
  DependencyStatusArraySchema,
  BuildEnvironmentStatusSchema,
  OnboardingStateSchema,
  DependencyInstallResultSchema,
  DependencyResetResultSchema,
} from "@/lib/schemas";
import type {
  Plugin,
  GenerationConfig,
  RefineConfig,
  DependencyStatus,
  BuildEnvironmentStatus,
  AgentProvider,
  GenerationTelemetry,
  UserProfile,
  RawUserProfile,
  OnboardingState,
  DependencyInstallResult,
  DependencyResetResult,
} from "@/lib/types";

export const sendOtp = (email: string) => invoke<void>("send_otp", { email });
export const verifyOtp = (email: string, code: string, isSignup: boolean) =>
  invoke<void>("verify_otp", { email, code, isSignup });
export const signUp = (email: string, password: string) =>
  invoke<void>("sign_up", { email, password });
export const signOut = () => invoke<void>("sign_out");
export const checkSession = () => invoke<string | null>("check_session");
export const getProfile = (userId: string) =>
  invoke<RawUserProfile | null>("get_profile", { userId });
export const updateCardVariant = (userId: string, variant: string) =>
  invoke<void>("update_card_variant", { userId, variant });
export const assignCardVariantBatch = (emails: string[], variant: string) =>
  invoke<number>("assign_card_variant_batch", { emails, variant });

export const loadPlugins = () => invoke<Plugin[]>("load_plugins");
export const deletePlugin = (id: string) =>
  invoke<void>("delete_plugin", { id });
export const renamePlugin = (id: string, newName: string) =>
  invoke<void>("rename_plugin", { id, newName });
export const installVersion = (pluginId: string, versionNumber: number) =>
  invoke<Plugin>("install_version", { pluginId, versionNumber });
export const clearBuildCache = (pluginId: string, versionNumber: number) =>
  invoke<Plugin>("clear_build_cache", { pluginId, versionNumber });

export const startGeneration = (config: GenerationConfig) =>
  invoke<void>("start_generation", { config });
export const startRefine = (config: RefineConfig) =>
  invoke<void>("start_refine", { config });
export const cancelBuild = () => invoke<void>("cancel_build");

// ---------------------------------------------------------------------------
// Dependencies & onboarding — validated with Zod at the IPC boundary
// ---------------------------------------------------------------------------

export const checkDependencies = async (): Promise<DependencyStatus[]> =>
  DependencyStatusArraySchema.parse(await invoke("check_dependencies"));

export const invalidateAndCheckDependencies = async (): Promise<
  DependencyStatus[]
> =>
  DependencyStatusArraySchema.parse(
    await invoke("invalidate_and_check_dependencies"),
  );

export const installJuce = async (): Promise<BuildEnvironmentStatus> =>
  BuildEnvironmentStatusSchema.parse(await invoke("install_juce"));

export const getBuildEnvironment = async (): Promise<BuildEnvironmentStatus> =>
  BuildEnvironmentStatusSchema.parse(await invoke("get_build_environment"));

export const prepareBuildEnvironment = async (
  autoRepair: boolean,
): Promise<BuildEnvironmentStatus> =>
  BuildEnvironmentStatusSchema.parse(
    await invoke("prepare_build_environment", { autoRepair }),
  );

export const setJuceOverridePath = async (
  path: string,
): Promise<BuildEnvironmentStatus> =>
  BuildEnvironmentStatusSchema.parse(
    await invoke("set_juce_override_path", { path }),
  );

export const clearJuceOverridePath =
  async (): Promise<BuildEnvironmentStatus> =>
    BuildEnvironmentStatusSchema.parse(
      await invoke("clear_juce_override_path"),
    );

export const getOnboardingState = async (): Promise<OnboardingState> =>
  OnboardingStateSchema.parse(await invoke("get_onboarding_state"));

export const completeOnboarding = async (): Promise<OnboardingState> =>
  OnboardingStateSchema.parse(await invoke("complete_onboarding"));

export const installDependency = async (
  name: string,
): Promise<DependencyInstallResult> =>
  DependencyInstallResultSchema.parse(
    await invoke("install_dependency", { name }),
  );

export const resetDebugDependencies =
  async (): Promise<DependencyResetResult> =>
    DependencyResetResultSchema.parse(await invoke("reset_debug_dependencies"));

export const launchClaudeAuth = () => invoke<boolean>("launch_claude_auth");
export const launchCodexAuth = () => invoke<boolean>("launch_codex_auth");

// ---------------------------------------------------------------------------
// Models & install paths (no Zod — not in onboarding critical path)
// ---------------------------------------------------------------------------

export const getModelCatalog = () =>
  invoke<AgentProvider[]>("get_model_catalog");
export const refreshModelCatalog = () =>
  invoke<AgentProvider[]>("refresh_model_catalog");

export interface InstallPathsConfig {
  platform: "macos" | "windows" | "linux";
  supportedFormats: Array<"AU" | "VST3">;
  auPath?: string;
  vst3Path?: string;
  auIsDefault: boolean;
  vst3IsDefault: boolean;
}

export const getInstallPaths = () =>
  invoke<InstallPathsConfig>("get_install_paths");
export const setInstallPath = (format: string, path: string) =>
  invoke<InstallPathsConfig>("set_install_path", { format, path });
export const resetInstallPath = (format: string) =>
  invoke<InstallPathsConfig>("reset_install_path", { format });

export const rateGeneration = (id: string, rating: 1 | -1) =>
  invoke<void>("rate_generation", { id, rating });

export const submitPluginFeedback = (
  pluginId: string,
  speed: number,
  quality: number,
  design: number,
) =>
  invoke<void>("submit_plugin_feedback", { pluginId, speed, quality, design });

export const loadTelemetry = (id: string) =>
  invoke<GenerationTelemetry | null>("load_telemetry", { id });
export const loadAllTelemetry = () =>
  invoke<GenerationTelemetry[]>("load_all_telemetry");

export const showInFinder = (path: string) =>
  invoke<void>("show_in_finder", { path });
