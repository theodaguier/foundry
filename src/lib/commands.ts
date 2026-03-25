import { invoke } from "@tauri-apps/api/core";
import type {
  Plugin,
  GenerationConfig,
  RefineConfig,
  DependencyStatus,
  BuildEnvironmentStatus,
  AgentProvider,
  GenerationTelemetry,
  UserProfile,
  OnboardingState,
  DependencyInstallResult,
} from "@/lib/types"

export const sendOtp = (email: string) => invoke<void>("send_otp", { email });
export const verifyOtp = (email: string, code: string, isSignup: boolean) =>
  invoke<void>("verify_otp", { email, code, isSignup });
export const signUp = (email: string, password: string) =>
  invoke<void>("sign_up", { email, password });
export const signOut = () => invoke<void>("sign_out");
export const checkSession = () => invoke<string | null>("check_session");
export const getProfile = (userId: string) =>
  invoke<UserProfile | null>("get_profile", { userId });
export const updateCardVariant = (userId: string, variant: string) =>
  invoke<void>("update_card_variant", { userId, variant });
export const assignCardVariantBatch = (emails: string[], variant: string) =>
  invoke<number>("assign_card_variant_batch", { emails, variant });

export const loadPlugins = () => invoke<Plugin[]>("load_plugins");
export const deletePlugin = (id: string) => invoke<void>("delete_plugin", { id });
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

export const checkDependencies = () => invoke<DependencyStatus[]>("check_dependencies");
export const installJuce = () => invoke<BuildEnvironmentStatus>("install_juce");
export const getBuildEnvironment = () =>
  invoke<BuildEnvironmentStatus>("get_build_environment");
export const prepareBuildEnvironment = (autoRepair: boolean) =>
  invoke<BuildEnvironmentStatus>("prepare_build_environment", { autoRepair });
export const setJuceOverridePath = (path: string) =>
  invoke<BuildEnvironmentStatus>("set_juce_override_path", { path });
export const clearJuceOverridePath = () =>
  invoke<BuildEnvironmentStatus>("clear_juce_override_path");

export const getModelCatalog = () => invoke<AgentProvider[]>("get_model_catalog");
export const refreshModelCatalog = () => invoke<AgentProvider[]>("refresh_model_catalog");

export interface InstallPathsConfig {
  auPath: string;
  vst3Path: string;
  auIsDefault: boolean;
  vst3IsDefault: boolean;
}

export const getInstallPaths = () => invoke<InstallPathsConfig>("get_install_paths");
export const setInstallPath = (format: string, path: string) =>
  invoke<InstallPathsConfig>("set_install_path", { format, path });
export const resetInstallPath = (format: string) =>
  invoke<InstallPathsConfig>("reset_install_path", { format });

export const loadTelemetry = (id: string) =>
  invoke<GenerationTelemetry | null>("load_telemetry", { id });
export const loadAllTelemetry = () => invoke<GenerationTelemetry[]>("load_all_telemetry");

export const showInFinder = (path: string) => invoke<void>("show_in_finder", { path });

export const getOnboardingState = () => invoke<OnboardingState>("get_onboarding_state");
export const completeOnboarding = () => invoke<OnboardingState>("complete_onboarding");
export const installDependency = (name: string) =>
  invoke<DependencyInstallResult>("install_dependency", { name });
