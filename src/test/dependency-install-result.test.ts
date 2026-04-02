import { describe, expect, it } from "vitest"

import { interpretDependencyInstallResult } from "@/lib/dependency-install"
import { DependencyInstallResultSchema } from "@/lib/schemas"

describe("DependencyInstallResultSchema", () => {
  it("parses the enriched provider install payload", () => {
    const parsed = DependencyInstallResultSchema.parse({
      success: true,
      message: "Codex installed successfully.",
      verification: "verified",
      detectedPath: "/opt/homebrew/bin/codex",
      status: {
        name: "Codex CLI",
        installed: true,
        authRequired: false,
        detail: "codex 1.0.0",
        version: "codex 1.0.0",
      },
    })

    expect(parsed.verification).toBe("verified")
    expect(parsed.detectedPath).toBe("/opt/homebrew/bin/codex")
    expect(parsed.status?.installed).toBe(true)
  })
})

describe("interpretDependencyInstallResult", () => {
  it("does not classify not_detected as success", () => {
    const outcome = interpretDependencyInstallResult({
      success: false,
      message: "Installer completed, but Foundry could not verify the CLI afterwards.",
      verification: "not_detected",
    })

    expect(outcome.state).toBe("failed")
    expect(outcome.shouldRefreshProviderState).toBe(false)
  })

  it("keeps auth_required distinct from verified", () => {
    const outcome = interpretDependencyInstallResult({
      success: true,
      message: "Claude Code installed. Sign in to continue.",
      verification: "auth_required",
    })

    expect(outcome.state).toBe("auth_required")
    expect(outcome.shouldRefreshProviderState).toBe(true)
  })

  it("marks verified installs as refreshable success", () => {
    const outcome = interpretDependencyInstallResult({
      success: true,
      message: "Codex installed successfully.",
      verification: "verified",
    })

    expect(outcome.state).toBe("verified")
    expect(outcome.shouldRefreshProviderState).toBe(true)
  })
})
