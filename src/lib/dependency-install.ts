import type { DependencyInstallResult } from "@/lib/types"

export type DependencyInstallOutcome =
  | {
      state: "verified"
      message: string
      shouldRefreshProviderState: true
    }
  | {
      state: "auth_required"
      message: string
      shouldRefreshProviderState: true
    }
  | {
      state: "pending"
      message: string
      shouldRefreshProviderState: false
    }
  | {
      state: "failed"
      message: string
      shouldRefreshProviderState: false
    }

export function interpretDependencyInstallResult(
  result: DependencyInstallResult,
): DependencyInstallOutcome {
  if (!result.success || result.verification === "not_detected") {
    return {
      state: "failed",
      message: result.message,
      shouldRefreshProviderState: false,
    }
  }

  switch (result.verification) {
    case "verified":
      return {
        state: "verified",
        message: result.message,
        shouldRefreshProviderState: true,
      }
    case "auth_required":
      return {
        state: "auth_required",
        message: result.message,
        shouldRefreshProviderState: true,
      }
    case "pending":
      return {
        state: "pending",
        message: result.message,
        shouldRefreshProviderState: false,
      }
  }
}

export function isProviderInstallKey(key: string) {
  return key === "claude_code" || key === "codex"
}
