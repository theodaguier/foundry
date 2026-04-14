import { z } from "zod";

// ---------------------------------------------------------------------------
// Dependency & onboarding schemas — validate data at the Tauri IPC boundary
// ---------------------------------------------------------------------------

export const DependencyStatusSchema = z.object({
  name: z.string().min(1),
  installed: z.boolean(),
  authRequired: z.boolean(),
  detail: z.string().nullish(),
  version: z.string().nullish(),
});

export const DependencyStatusArraySchema = z.array(DependencyStatusSchema);

export const BuildEnvironmentIssueSchema = z.object({
  code: z.string(),
  title: z.string(),
  detail: z.string(),
  recoverable: z.boolean(),
  actionLabel: z.string().nullish(),
});

export const BuildEnvironmentStatusSchema = z.object({
  state: z.enum(["ready", "repairing", "blocked"]),
  issues: z.array(BuildEnvironmentIssueSchema),
  juceSource: z.enum(["managed", "override"]).nullish(),
  jucePath: z.string().nullish(),
  juceVersion: z.string(),
});

export const OnboardingStateSchema = z.object({
  completed: z.boolean(),
  completedAt: z.string().nullish(),
});

export const DependencyInstallResultSchema = z.object({
  success: z.boolean(),
  message: z.string(),
  verification: z.enum([
    "verified",
    "auth_required",
    "pending",
    "not_detected",
  ]),
  status: DependencyStatusSchema.nullish(),
  detectedPath: z.string().nullish(),
});

export const DependencyResetItemSchema = z.object({
  name: z.string().min(1),
  status: z.enum(["removed", "skipped", "failed"]),
  detail: z.string(),
});

export const DependencyResetResultSchema = z.object({
  items: z.array(DependencyResetItemSchema),
  summary: z.string(),
});

export const ProviderSetupStatusSchema = z.enum([
  "installed_and_authenticated",
  "installed_needs_auth",
  "not_installed",
]);

export const ProviderSummarySchema = z.object({
  id: z.string(),
  name: z.string(),
  status: ProviderSetupStatusSchema,
  version: z.string().nullish(),
  authUrl: z.string().nullish(),
});

export const SetupStateSchema = z.object({
  ready: z.boolean(),
  buildEnvironmentReady: z.boolean(),
  providers: z.array(ProviderSummarySchema),
  hasAuthenticatedProvider: z.boolean(),
  blockedReason: z.string().nullish(),
  remoteCompletedAt: z.string().nullish(),
});

// ---------------------------------------------------------------------------
// Inferred types — use these instead of the manual interfaces
// ---------------------------------------------------------------------------

export type DependencyStatus = z.infer<typeof DependencyStatusSchema>;
export type BuildEnvironmentIssue = z.infer<typeof BuildEnvironmentIssueSchema>;
export type BuildEnvironmentStatus = z.infer<
  typeof BuildEnvironmentStatusSchema
>;
export type OnboardingState = z.infer<typeof OnboardingStateSchema>;
export type DependencyInstallResult = z.infer<
  typeof DependencyInstallResultSchema
>;
export type DependencyResetItem = z.infer<typeof DependencyResetItemSchema>;
export type DependencyResetResult = z.infer<typeof DependencyResetResultSchema>;
export type SetupState = z.infer<typeof SetupStateSchema>;
export type ProviderSummary = z.infer<typeof ProviderSummarySchema>;
