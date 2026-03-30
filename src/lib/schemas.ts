import { z } from "zod"

// ---------------------------------------------------------------------------
// Dependency & onboarding schemas — validate data at the Tauri IPC boundary
// ---------------------------------------------------------------------------

export const DependencyStatusSchema = z.object({
  name: z.string().min(1),
  installed: z.boolean(),
  authRequired: z.boolean(),
  detail: z.string().nullish(),
  version: z.string().nullish(),
})

export const DependencyStatusArraySchema = z.array(DependencyStatusSchema)

export const BuildEnvironmentIssueSchema = z.object({
  code: z.string(),
  title: z.string(),
  detail: z.string(),
  recoverable: z.boolean(),
  actionLabel: z.string().nullish(),
})

export const BuildEnvironmentStatusSchema = z.object({
  state: z.enum(["ready", "repairing", "blocked"]),
  issues: z.array(BuildEnvironmentIssueSchema),
  juceSource: z.enum(["managed", "override"]).nullish(),
  jucePath: z.string().nullish(),
  juceVersion: z.string(),
})

export const OnboardingStateSchema = z.object({
  completed: z.boolean(),
  completedAt: z.string().nullish(),
})

export const DependencyInstallResultSchema = z.object({
  success: z.boolean(),
  message: z.string(),
})

// ---------------------------------------------------------------------------
// Inferred types — use these instead of the manual interfaces
// ---------------------------------------------------------------------------

export type DependencyStatus = z.infer<typeof DependencyStatusSchema>
export type BuildEnvironmentIssue = z.infer<typeof BuildEnvironmentIssueSchema>
export type BuildEnvironmentStatus = z.infer<typeof BuildEnvironmentStatusSchema>
export type OnboardingState = z.infer<typeof OnboardingStateSchema>
export type DependencyInstallResult = z.infer<typeof DependencyInstallResultSchema>
