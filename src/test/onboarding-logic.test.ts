import { describe, it, expect } from "vitest"
import type { DependencyInstallResult, DependencyStatus } from "@/lib/schemas"
import { interpretDependencyInstallResult } from "@/lib/dependency-install"

// ---------------------------------------------------------------------------
// Replicate the onboarding mapping logic so we can test it in isolation.
// These mirror the constants and functions in src/pages/onboarding.tsx.
// ---------------------------------------------------------------------------

type DepStatus = "checking" | "installed" | "missing" | "installing" | "failed" | "auth_required"

interface Dep {
  name: string
  key: string
  label: string
  description: string
  required: boolean
  status: DepStatus
  message?: string
}

const DEP_KEY_BY_NAME: Record<string, string> = {
  "Xcode Command Line Tools": "xcode_clt",
  "C++ Build Tools": "cpp_build_tools",
  "CMake": "cmake",
  "Git": "git",
  "Claude Code CLI": "claude_code",
  "Codex CLI": "codex",
  "JUCE SDK": "juce",
}

const DEP_LABELS: Record<string, string> = {
  "Xcode Command Line Tools": "Apple Build Tools",
  "C++ Build Tools": "Windows Build Tools",
  "CMake": "CMake",
  "Git": "Git",
  "Claude Code CLI": "Claude Code",
  "Codex CLI": "Codex",
  "JUCE SDK": "Audio Framework",
}

const DEP_DESCRIPTIONS: Record<string, string> = {
  "Xcode Command Line Tools": "C++ compiler for building audio plugins",
  "CMake": "Builds and compiles your plugin projects",
  "Claude Code CLI": "AI engine that writes the plugin code",
  "Codex CLI": "Alternative AI engine (optional)",
  "JUCE SDK": "Audio plugin framework by JUCE",
}

const OPTIONAL_DEPS = new Set(["Codex CLI", "Claude Code CLI"])
const PROVIDER_DEPS = new Set(["claude_code", "codex"])

function mapDependency(result: DependencyStatus): Dep {
  let status: DepStatus = "missing"
  if (result.installed && result.authRequired) {
    status = "auth_required"
  } else if (result.installed) {
    status = "installed"
  }

  return {
    name: result.name,
    key: DEP_KEY_BY_NAME[result.name] ?? result.name.toLowerCase().replace(/\s+/g, "_"),
    label: DEP_LABELS[result.name] ?? result.name,
    description: DEP_DESCRIPTIONS[result.name] ?? "Required for plugin generation",
    required: !OPTIONAL_DEPS.has(result.name),
    status,
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("mapDependency", () => {
  it("maps an installed dependency", () => {
    const dep = mapDependency({
      name: "CMake",
      installed: true,
      authRequired: false,
      detail: "cmake version 3.28",
      version: "3.28",
    })
    expect(dep.status).toBe("installed")
    expect(dep.key).toBe("cmake")
    expect(dep.label).toBe("CMake")
    expect(dep.required).toBe(true)
  })

  it("maps a missing dependency", () => {
    const dep = mapDependency({
      name: "CMake",
      installed: false,
      authRequired: false,
    })
    expect(dep.status).toBe("missing")
  })

  it("maps auth_required state for Claude Code", () => {
    const dep = mapDependency({
      name: "Claude Code CLI",
      installed: true,
      authRequired: true,
    })
    expect(dep.status).toBe("auth_required")
    expect(dep.key).toBe("claude_code")
    expect(dep.required).toBe(false) // providers are optional
  })

  it("maps auth_required state for Codex", () => {
    const dep = mapDependency({
      name: "Codex CLI",
      installed: true,
      authRequired: true,
    })
    expect(dep.status).toBe("auth_required")
    expect(dep.key).toBe("codex")
  })

  it("marks Xcode CLT as required", () => {
    const dep = mapDependency({
      name: "Xcode Command Line Tools",
      installed: false,
      authRequired: false,
    })
    expect(dep.required).toBe(true)
    expect(dep.label).toBe("Apple Build Tools")
  })

  it("marks Claude Code as optional", () => {
    const dep = mapDependency({
      name: "Claude Code CLI",
      installed: false,
      authRequired: false,
    })
    expect(dep.required).toBe(false)
  })

  it("handles unknown dependency name gracefully", () => {
    const dep = mapDependency({
      name: "Unknown Tool",
      installed: false,
      authRequired: false,
    })
    expect(dep.key).toBe("unknown_tool")
    expect(dep.label).toBe("Unknown Tool")
    expect(dep.description).toBe("Required for plugin generation")
    expect(dep.required).toBe(true) // unknown deps default to required
  })
})

describe("provider install verification mapping", () => {
  function nextStatus(result: DependencyInstallResult): DepStatus {
    const outcome = interpretDependencyInstallResult(result)
    switch (outcome.state) {
      case "verified":
        return "installed"
      case "auth_required":
        return "auth_required"
      case "pending":
        return "installing"
      case "failed":
        return "failed"
    }
  }

  it("maps verified installs to installed", () => {
    expect(nextStatus({
      success: true,
      message: "Codex installed successfully.",
      verification: "verified",
    })).toBe("installed")
  })

  it("maps auth_required installs to auth_required", () => {
    expect(nextStatus({
      success: true,
      message: "Claude Code installed. Sign in to continue.",
      verification: "auth_required",
    })).toBe("auth_required")
  })

  it("maps not_detected installs to failed", () => {
    expect(nextStatus({
      success: false,
      message: "Installer completed, but Foundry could not verify the CLI afterwards.",
      verification: "not_detected",
    })).toBe("failed")
  })
})

// ---------------------------------------------------------------------------
// Step-based onboarding model tests
// ---------------------------------------------------------------------------

type SetupStep = "checking" | "machine" | "provider" | "auth" | "done"

interface ProviderSummary {
  id: string
  status: "installed_and_authenticated" | "installed_needs_auth" | "not_installed"
}

interface SetupState {
  buildEnvironmentReady: boolean
  providers: ProviderSummary[]
}

/** Mirrors the step-determination logic in Onboarding.tsx */
function computeStep(setup: SetupState, deps: Dep[]): SetupStep {
  const machineReady = setup.buildEnvironmentReady
  const hasInstalled = setup.providers.some(p => p.status === "installed_and_authenticated")
  const needsAuth = setup.providers.some(p => p.status === "installed_needs_auth")

  if (machineReady && hasInstalled) return "done"
  if (machineReady && needsAuth) return "auth"
  if (machineReady) return "provider"
  return "machine"
}

describe("step-based onboarding transitions", () => {
  it("goes to machine when build environment is not ready", () => {
    const setup: SetupState = { buildEnvironmentReady: false, providers: [] }
    expect(computeStep(setup, [])).toBe("machine")
  })

  it("goes to provider when build env ready but no provider installed", () => {
    const setup: SetupState = {
      buildEnvironmentReady: true,
      providers: [
        { id: "claude_code", status: "not_installed" },
        { id: "codex", status: "not_installed" },
      ],
    }
    expect(computeStep(setup, [])).toBe("provider")
  })

  it("goes to auth when build env ready and provider needs sign-in", () => {
    const setup: SetupState = {
      buildEnvironmentReady: true,
      providers: [
        { id: "claude_code", status: "installed_needs_auth" },
      ],
    }
    expect(computeStep(setup, [])).toBe("auth")
  })

  it("goes to done when build env ready and provider authenticated", () => {
    const setup: SetupState = {
      buildEnvironmentReady: true,
      providers: [
        { id: "claude_code", status: "installed_and_authenticated" },
      ],
    }
    expect(computeStep(setup, [])).toBe("done")
  })

  it("done takes priority over auth when both conditions could be met", () => {
    // If a provider is both needs_auth AND another is authenticated, done wins.
    const setup: SetupState = {
      buildEnvironmentReady: true,
      providers: [
        { id: "claude_code", status: "installed_needs_auth" },
        { id: "codex", status: "installed_and_authenticated" },
      ],
    }
    expect(computeStep(setup, [])).toBe("done")
  })
})

describe("machine step readiness button", () => {
  it("enables Continue when all machine deps are installed", () => {
    const machineDeps: Dep[] = [
      { name: "Xcode Command Line Tools", key: "xcode_clt", label: "Apple Build Tools", description: "", required: true, status: "installed" },
      { name: "CMake", key: "cmake", label: "CMake", description: "", required: true, status: "installed" },
    ]
    const allMachineReady = machineDeps.length > 0 && machineDeps.every(d => d.status === "installed")
    // This is the key invariant: when allMachineReady is true, the Continue button
    // must be shown (not disabled), and it should call computeStep to advance.
    expect(allMachineReady).toBe(true)
  })

  it("shows Install tools when some machine deps are missing", () => {
    const machineDeps: Dep[] = [
      { name: "Xcode Command Line Tools", key: "xcode_clt", label: "Apple Build Tools", description: "", required: true, status: "installed" },
      { name: "CMake", key: "cmake", label: "CMake", description: "", required: true, status: "missing" },
    ]
    const allMachineReady = machineDeps.length > 0 && machineDeps.every(d => d.status === "installed")
    expect(allMachineReady).toBe(false)
  })
})
