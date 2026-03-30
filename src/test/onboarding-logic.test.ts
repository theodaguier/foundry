import { describe, it, expect } from "vitest"
import type { DependencyStatus } from "@/lib/schemas"

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

describe("onboarding readiness logic", () => {
  function computeReadiness(deps: Dep[]) {
    const requiredDeps = deps.filter(d => d.required)
    const providerDeps = deps.filter(d => PROVIDER_DEPS.has(d.key))
    const hasProvider = providerDeps.some(d => d.status === "installed")
    const allRequiredReady = requiredDeps.length > 0 && requiredDeps.every(d => d.status === "installed")
    const allReady = allRequiredReady && hasProvider
    const hasAuthRequired = deps.some(d => d.status === "auth_required")
    const hasFailed = deps.some(d => d.status === "failed" && d.required)
    return { allReady, hasProvider, allRequiredReady, hasAuthRequired, hasFailed }
  }

  it("reports allReady when all required installed + provider ready", () => {
    const deps: Dep[] = [
      mapDependency({ name: "Xcode Command Line Tools", installed: true, authRequired: false }),
      mapDependency({ name: "CMake", installed: true, authRequired: false }),
      mapDependency({ name: "Claude Code CLI", installed: true, authRequired: false }),
      mapDependency({ name: "Codex CLI", installed: false, authRequired: false }),
    ]
    const r = computeReadiness(deps)
    expect(r.allReady).toBe(true)
    expect(r.hasProvider).toBe(true)
  })

  it("reports NOT ready when provider has auth_required", () => {
    const deps: Dep[] = [
      mapDependency({ name: "Xcode Command Line Tools", installed: true, authRequired: false }),
      mapDependency({ name: "CMake", installed: true, authRequired: false }),
      mapDependency({ name: "Claude Code CLI", installed: true, authRequired: true }),
    ]
    const r = computeReadiness(deps)
    expect(r.allReady).toBe(false)
    expect(r.hasProvider).toBe(false) // auth_required ≠ installed
    expect(r.hasAuthRequired).toBe(true)
  })

  it("reports NOT ready when required dep missing", () => {
    const deps: Dep[] = [
      mapDependency({ name: "Xcode Command Line Tools", installed: true, authRequired: false }),
      mapDependency({ name: "CMake", installed: false, authRequired: false }),
      mapDependency({ name: "Claude Code CLI", installed: true, authRequired: false }),
    ]
    const r = computeReadiness(deps)
    expect(r.allReady).toBe(false)
    expect(r.allRequiredReady).toBe(false)
  })

  it("reports NOT ready when no provider installed", () => {
    const deps: Dep[] = [
      mapDependency({ name: "Xcode Command Line Tools", installed: true, authRequired: false }),
      mapDependency({ name: "CMake", installed: true, authRequired: false }),
      mapDependency({ name: "Claude Code CLI", installed: false, authRequired: false }),
      mapDependency({ name: "Codex CLI", installed: false, authRequired: false }),
    ]
    const r = computeReadiness(deps)
    expect(r.allReady).toBe(false)
    expect(r.hasProvider).toBe(false)
    expect(r.allRequiredReady).toBe(true)
  })

  it("hasFailed only for required deps", () => {
    const deps: Dep[] = [
      { name: "CMake", key: "cmake", label: "CMake", description: "", required: true, status: "failed", message: "error" },
      { name: "Codex CLI", key: "codex", label: "Codex", description: "", required: false, status: "failed", message: "error" },
    ]
    const r = computeReadiness(deps)
    expect(r.hasFailed).toBe(true)

    // Only optional failed — hasFailed should be false
    const deps2: Dep[] = [
      { name: "CMake", key: "cmake", label: "CMake", description: "", required: true, status: "installed" },
      { name: "Codex CLI", key: "codex", label: "Codex", description: "", required: false, status: "failed", message: "error" },
    ]
    expect(computeReadiness(deps2).hasFailed).toBe(false)
  })
})

describe("Settings dependency filtering", () => {
  const AI_PROVIDER_NAMES = new Set(["Claude Code CLI", "Codex CLI"])

  it("filters JUCE from deps list", () => {
    const deps: DependencyStatus[] = [
      { name: "Xcode Command Line Tools", installed: true, authRequired: false },
      { name: "CMake", installed: true, authRequired: false },
      { name: "Claude Code CLI", installed: true, authRequired: false },
      { name: "Codex CLI", installed: false, authRequired: false },
      { name: "JUCE SDK", installed: true, authRequired: false },
    ]
    const filtered = deps.filter(d => d.name !== "JUCE SDK")
    expect(filtered).toHaveLength(4)
    expect(filtered.find(d => d.name === "JUCE SDK")).toBeUndefined()
  })

  it("splits into build tools and providers", () => {
    const deps: DependencyStatus[] = [
      { name: "Xcode Command Line Tools", installed: true, authRequired: false },
      { name: "CMake", installed: true, authRequired: false },
      { name: "Claude Code CLI", installed: true, authRequired: false },
      { name: "Codex CLI", installed: false, authRequired: false },
    ]
    const buildTools = deps.filter(d => !AI_PROVIDER_NAMES.has(d.name))
    const providers = deps.filter(d => AI_PROVIDER_NAMES.has(d.name))
    expect(buildTools).toHaveLength(2)
    expect(providers).toHaveLength(2)
    expect(buildTools.map(d => d.name)).toEqual(["Xcode Command Line Tools", "CMake"])
    expect(providers.map(d => d.name)).toEqual(["Claude Code CLI", "Codex CLI"])
  })

  it("DEP_INSTALL_KEY maps all known deps", () => {
    const DEP_INSTALL_KEY: Record<string, string> = {
      "Xcode Command Line Tools": "xcode_clt",
      "CMake": "cmake",
      "Claude Code CLI": "claude_code",
      "Codex CLI": "codex",
    }
    const knownNames = ["Xcode Command Line Tools", "CMake", "Claude Code CLI", "Codex CLI"]
    for (const name of knownNames) {
      expect(DEP_INSTALL_KEY[name]).toBeDefined()
      expect(DEP_INSTALL_KEY[name].length).toBeGreaterThan(0)
    }
  })
})
