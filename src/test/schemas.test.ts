import { describe, it, expect } from "vitest"
import {
  DependencyStatusSchema,
  DependencyStatusArraySchema,
  BuildEnvironmentStatusSchema,
  OnboardingStateSchema,
  DependencyInstallResultSchema,
} from "@/lib/schemas"

// ---------------------------------------------------------------------------
// DependencyStatus
// ---------------------------------------------------------------------------

describe("DependencyStatusSchema", () => {
  it("parses a valid installed dependency", () => {
    const data = {
      name: "CMake",
      installed: true,
      authRequired: false,
      detail: "cmake version 3.28.1",
      version: "cmake version 3.28.1",
    }
    expect(DependencyStatusSchema.parse(data)).toEqual(data)
  })

  it("parses a missing dependency with null fields", () => {
    const data = {
      name: "Codex CLI",
      installed: false,
      authRequired: false,
      detail: null,
      version: null,
    }
    const result = DependencyStatusSchema.parse(data)
    expect(result.name).toBe("Codex CLI")
    expect(result.installed).toBe(false)
    expect(result.detail).toBeNull()
  })

  it("parses auth_required state", () => {
    const data = {
      name: "Claude Code CLI",
      installed: true,
      authRequired: true,
      detail: "/usr/local/bin/claude",
      version: "1.0.0",
    }
    const result = DependencyStatusSchema.parse(data)
    expect(result.installed).toBe(true)
    expect(result.authRequired).toBe(true)
  })

  it("accepts omitted optional fields", () => {
    const data = {
      name: "CMake",
      installed: false,
      authRequired: false,
    }
    const result = DependencyStatusSchema.parse(data)
    expect(result.detail).toBeUndefined()
    expect(result.version).toBeUndefined()
  })

  it("rejects empty name", () => {
    expect(() =>
      DependencyStatusSchema.parse({
        name: "",
        installed: true,
        authRequired: false,
      })
    ).toThrow()
  })

  it("rejects missing installed field", () => {
    expect(() =>
      DependencyStatusSchema.parse({
        name: "CMake",
        authRequired: false,
      })
    ).toThrow()
  })

  it("rejects wrong type for installed", () => {
    expect(() =>
      DependencyStatusSchema.parse({
        name: "CMake",
        installed: "yes",
        authRequired: false,
      })
    ).toThrow()
  })
})

describe("DependencyStatusArraySchema", () => {
  it("parses a typical macOS dependency list", () => {
    const data = [
      { name: "Xcode Command Line Tools", installed: true, authRequired: false, detail: "/Library/Developer/CommandLineTools", version: null },
      { name: "CMake", installed: true, authRequired: false, detail: "cmake version 3.28.1", version: "cmake version 3.28.1" },
      { name: "Claude Code CLI", installed: true, authRequired: true, detail: "/usr/local/bin/claude", version: "1.0.0" },
      { name: "Codex CLI", installed: false, authRequired: false, detail: null, version: null },
      { name: "JUCE SDK", installed: true, authRequired: false, detail: "/Users/me/Library/Application Support/Foundry/JUCE/8.0.12 (managed)", version: "8.0.12" },
    ]
    const result = DependencyStatusArraySchema.parse(data)
    expect(result).toHaveLength(5)
    expect(result[2].authRequired).toBe(true)
    expect(result[3].installed).toBe(false)
  })

  it("parses an empty array", () => {
    expect(DependencyStatusArraySchema.parse([])).toEqual([])
  })

  it("rejects if any element is invalid", () => {
    expect(() =>
      DependencyStatusArraySchema.parse([
        { name: "CMake", installed: true, authRequired: false },
        { name: 123, installed: true, authRequired: false },
      ])
    ).toThrow()
  })
})

// ---------------------------------------------------------------------------
// BuildEnvironmentStatus
// ---------------------------------------------------------------------------

describe("BuildEnvironmentStatusSchema", () => {
  it("parses a ready environment", () => {
    const data = {
      state: "ready",
      issues: [],
      juceSource: "managed",
      jucePath: "/Users/me/Library/Application Support/Foundry/JUCE/8.0.12",
      juceVersion: "8.0.12",
    }
    const result = BuildEnvironmentStatusSchema.parse(data)
    expect(result.state).toBe("ready")
    expect(result.issues).toEqual([])
  })

  it("parses a blocked environment with issues", () => {
    const data = {
      state: "blocked",
      issues: [
        {
          code: "JUCE_MISSING",
          title: "JUCE SDK not found",
          detail: "Install JUCE 8.0.12 or set a custom path.",
          recoverable: true,
          actionLabel: "Install",
        },
      ],
      juceSource: null,
      jucePath: null,
      juceVersion: "8.0.12",
    }
    const result = BuildEnvironmentStatusSchema.parse(data)
    expect(result.state).toBe("blocked")
    expect(result.issues).toHaveLength(1)
    expect(result.issues[0].recoverable).toBe(true)
  })

  it("rejects invalid state value", () => {
    expect(() =>
      BuildEnvironmentStatusSchema.parse({
        state: "unknown",
        issues: [],
        juceVersion: "8.0.12",
      })
    ).toThrow()
  })

  it("rejects missing juceVersion", () => {
    expect(() =>
      BuildEnvironmentStatusSchema.parse({
        state: "ready",
        issues: [],
      })
    ).toThrow()
  })
})

// ---------------------------------------------------------------------------
// OnboardingState
// ---------------------------------------------------------------------------

describe("OnboardingStateSchema", () => {
  it("parses completed onboarding", () => {
    const data = { completed: true, completedAt: "2026-03-30T12:00:00Z" }
    const result = OnboardingStateSchema.parse(data)
    expect(result.completed).toBe(true)
    expect(result.completedAt).toBe("2026-03-30T12:00:00Z")
  })

  it("parses incomplete onboarding", () => {
    const data = { completed: false, completedAt: null }
    const result = OnboardingStateSchema.parse(data)
    expect(result.completed).toBe(false)
    expect(result.completedAt).toBeNull()
  })

  it("accepts omitted completedAt", () => {
    const result = OnboardingStateSchema.parse({ completed: false })
    expect(result.completedAt).toBeUndefined()
  })

  it("rejects missing completed field", () => {
    expect(() => OnboardingStateSchema.parse({})).toThrow()
  })

  it("rejects non-boolean completed", () => {
    expect(() =>
      OnboardingStateSchema.parse({ completed: "true" })
    ).toThrow()
  })
})

// ---------------------------------------------------------------------------
// DependencyInstallResult
// ---------------------------------------------------------------------------

describe("DependencyInstallResultSchema", () => {
  it("parses a successful install", () => {
    const data = { success: true, message: "CMake installed successfully via Homebrew." }
    const result = DependencyInstallResultSchema.parse(data)
    expect(result.success).toBe(true)
    expect(result.message).toBe("CMake installed successfully via Homebrew.")
  })

  it("parses a failed install", () => {
    const data = {
      success: false,
      message: "npm install succeeded but the codex binary was not found on PATH. Try restarting your shell.",
    }
    const result = DependencyInstallResultSchema.parse(data)
    expect(result.success).toBe(false)
  })

  it("rejects missing message", () => {
    expect(() =>
      DependencyInstallResultSchema.parse({ success: true })
    ).toThrow()
  })

  it("rejects missing success", () => {
    expect(() =>
      DependencyInstallResultSchema.parse({ message: "ok" })
    ).toThrow()
  })
})
