export type PluginType = "instrument" | "effect" | "utility";
export type PluginFormat = "AU" | "VST3";
export type PluginStatus = "installed" | "failed" | "building";

export interface InstallPaths {
  au?: string;
  vst3?: string;
}

export interface PluginVersion {
  id: string;
  pluginId: string;
  versionNumber: number;
  prompt: string;
  createdAt: string;
  buildDirectory?: string;
  installPaths: InstallPaths;
  iconColor: string;
  isActive: boolean;
  agent?: string;
  model?: AgentModel;
  telemetryId?: string;
}

export interface Plugin {
  id: string;
  name: string;
  type: PluginType;
  prompt: string;
  createdAt: string;
  formats: PluginFormat[];
  installPaths: InstallPaths;
  iconColor: string;
  logoAssetPath?: string;
  status: PluginStatus;
  buildDirectory?: string;
  generationLogPath?: string;
  agent?: string;
  model?: AgentModel;
  currentVersion: number;
  versions: PluginVersion[];
}

export interface AgentModel {
  id: string;
  name: string;
  subtitle: string;
  flag: string;
  default?: boolean;
}

export interface AgentProvider {
  id: string;
  name: string;
  icon: string;
  command: string;
  models: AgentModel[];
}

export type FormatOption = "AU" | "VST3" | "Both";
export type ChannelLayout = "Mono" | "Stereo";
export type PresetCount = 0 | 3 | 5 | 10;

export interface GenerationConfig {
  prompt: string;
  format: FormatOption;
  channelLayout: ChannelLayout;
  presetCount: PresetCount;
  agent: string;
  model: string;
}

export interface RefineConfig {
  plugin: Plugin;
  modification: string;
}

export type GenerationStep =
  | "preparingEnvironment"
  | "preparingProject"
  | "generatingDSP"
  | "generatingUI"
  | "compiling"
  | "installing";

export interface PipelineLogLine {
  timestamp: string;
  message: string;
  style?: string;
}

export type AuthState = "checking" | "unauthenticated" | "authenticated";

export type CardVariant = "default" | "gold" | "diamond" | "ambassador";

export interface UserProfile {
  id: string;
  email: string;
  displayName?: string;
  avatarUrl?: string;
  plan: "free" | "pro";
  pluginsGenerated: number;
  createdAt: string;
  onboardingCompletedAt?: string;
  cardVariant?: CardVariant;
}

export interface DependencyStatus {
  name: string;
  installed: boolean;
  detail?: string;
  version?: string;
}

export interface BuildEnvironmentIssue {
  code: string;
  title: string;
  detail: string;
  recoverable: boolean;
  actionLabel?: string;
}

export interface BuildEnvironmentStatus {
  state: "ready" | "repairing" | "blocked";
  issues: BuildEnvironmentIssue[];
  juceSource?: "managed" | "override";
  jucePath?: string;
  juceVersion: string;
}

export type PluginFilter = "ALL" | "INSTRUMENTS" | "EFFECTS" | "UTILITIES";

export interface GenerationTelemetry {
  id: string;
  pluginId: string;
  stage: string;
  success: boolean;
  totalDuration: number;
  generationDuration?: number;
  auditDuration?: number;
  buildDuration?: number;
  installDuration?: number;
  buildAttempts: number;
  buildAttemptLogs: BuildAttemptLog[];
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  estimatedCost?: number;
  agent?: string;
  model?: string;
  prompt?: string;
  enhancedPrompt?: string;
  errorMessage?: string;
  errorDetails?: string;
  createdAt: string;
}

export interface BuildAttemptLog {
  attempt: number;
  success: boolean;
  duration: number;
  errorSnippet?: string;
}

export interface OnboardingState {
  completed: boolean;
  completedAt?: string;
}

export interface DependencyInstallResult {
  success: boolean;
  message: string;
}
