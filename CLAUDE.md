# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

Foundry is a macOS app (SwiftUI) that generates real, compilable AU/VST3 audio plugins from a natural language description. It uses Claude Code CLI as a subprocess to write C++/JUCE code, then builds and installs the plugin locally.

**Status:** Active development. Core pipeline, refine flow, and plugin logo generation are implemented and working.

## Architecture

### App layer (SwiftUI)

```
Foundry/
├── App/           FoundryApp.swift, ContentView.swift
├── Models/        Plugin.swift, AppState.swift
├── Views/         All screens (Prompt, QuickOptions, GenerationProgress, Result, Error,
│                  PluginLibrary, PluginDetail, Refine, RefineProgress, Setup, Settings)
├── Components/    PluginCard, PluginArtworkView, StepListView, DependencyListModel
└── Services/      All business logic (see below)
```

### Service layer

| File | Role |
|---|---|
| `GenerationPipeline` | Orchestrates generate and refine flows |
| `ProjectAssembler` | Writes CMakeLists.txt + CLAUDE.md + juce-kit/ knowledge files to `/tmp/foundry-build-<uuid>/` |
| `ClaudeCodeService` | Launches Claude CLI subprocess, parses stdout stream-json, event-driven completion |
| `BuildLoop` | CMake build with unlimited retry loop and Claude fix passes |
| `BuildRunner` | Low-level CMake process runner + smoke test |
| `BuildDirectoryCleaner` | Cleans `/tmp/foundry-build-*` after install and on launch |
| `PluginManager` | Persists `plugins.json`, handles install/uninstall via AppleScript |
| `PluginLogoService` | Local Stable Diffusion logo generation (Apple CoreML) |
| `DependencyChecker` | Checks Xcode CLI Tools, CMake, JUCE SDK, Claude Code CLI |
| `FoundryPaths` | Canonical Application Support paths |
| `PluginBundleInspector` | Locates and validates AU/VST3 bundles in build output |

## Key Design Decisions

- **Knowledge kit architecture:** `ProjectAssembler` writes only `CMakeLists.txt` (build config) + `CLAUDE.md` (mission brief) + `juce-kit/*.md` (API reference, DSP patterns, UI patterns, build rules). No C++ stubs — Claude creates all source files from scratch.
- **JUCE knowledge kit:** Separate markdown files in `juce-kit/` directory: `juce-api.md`, `dsp-patterns.md`, `ui-patterns.md`, `look-and-feel.md`, `build-rules.md`, `presets.md`. Claude reads what it needs based on the plugin description.
- **Event-driven execution:** Claude CLI emits a `result` event when finished. The pipeline advances immediately on that event — no functional timeouts. Only a 15-minute watchdog remains as a safety net for silent crashes.
- **Audit pass before build:** After code generation, a second Claude invocation reviews the code for semantic issues (parameter/UI mismatches, architecture errors, missing includes) before the compiler sees it.
- **Build loop with no limit:** The build loop retries until success or user cancellation. No `maxAttempts` — the compiler is the only judge.
- **Claude invocation:** `claude -p "<prompt>" --dangerously-skip-permissions --output-format stream-json --verbose --max-turns 50 --model sonnet --append-system-prompt "..."`
- **Refine flow:** Modifies an existing plugin using its preserved `buildDirectory`. Full build loop runs again.
- **Install path:** `/Library/Audio/Plug-Ins/` (system-level) via AppleScript with admin. Ensures DAW visibility.
- **Cleanup:** `BuildDirectoryCleaner.cleanAfterInstall()` removes temp dirs 10s after install. `sweepStaleDirectories()` runs on launch for dirs older than 24h.

## Plugin Types

| Type | Keywords |
|---|---|
| `instrument` | synth, keys, pad, oscillator |
| `effect` | reverb, delay, distortion, filter |
| `utility` | analyzer, meter, width, gain staging |

## Data Model

```swift
struct Plugin: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: PluginType           // .instrument | .effect | .utility
    var prompt: String
    var createdAt: Date
    var formats: [PluginFormat]    // .au | .vst3
    var installPaths: InstallPaths
    var iconColor: String          // hex "#RRGGBB"
    var logoAssetPath: String?     // nil = use type icon fallback
    var status: PluginStatus       // .installed | .failed | .building
    var buildDirectory: String?    // /tmp/foundry-build-* for Refine
}
```

## Storage

```
~/Library/Application Support/Foundry/
├── plugins.json
├── JUCE/                      # SDK cache
├── PluginLogos/<id>/logo.png  # Generated logos
└── ImageModels/               # CoreML Stable Diffusion model

/tmp/foundry-build-<uuid>/     # Per-generation temp dir (auto-cleaned)
├── CMakeLists.txt             # Build config (never modified by Claude)
├── CLAUDE.md                  # Mission brief + kit references
├── juce-kit/                  # Knowledge kit (markdown reference files)
│   ├── juce-api.md
│   ├── dsp-patterns.md
│   ├── ui-patterns.md
│   ├── look-and-feel.md
│   ├── build-rules.md
│   └── presets.md
└── Source/                    # Created by Claude from scratch
    ├── PluginProcessor.h
    ├── PluginProcessor.cpp
    ├── PluginEditor.h
    ├── PluginEditor.cpp
    └── FoundryLookAndFeel.h
```

## Generation Pipeline (in order)

1. `ProjectAssembler.assemble()` → writes CMakeLists.txt + CLAUDE.md + juce-kit/ to `/tmp/foundry-build-<uuid>/`
2. `ClaudeCodeService.run()` → Claude reads knowledge kit, creates all source files from scratch
3. `ClaudeCodeService.audit()` → Claude reviews its own code for semantic issues before build
4. `BuildLoop.run()` → cmake build, unlimited retries with Claude fix passes until success
5. `PluginManager.installPlugin()` → copies to `/Library`, codesigns
6. `BuildDirectoryCleaner.cleanAfterInstall()` → removes temp dir

## Timeouts

| Step | Timeout | Type |
|---|---|---|
| All Claude invocations | 900s (15min) | Watchdog only — advances on `result` event |
| CMake configure | 60s | Hard timeout |
| CMake build | 120s per attempt | Hard timeout |

## Known Issues

- **#7** Smoke test only checks bundle existence, not audio validity
- **#8** Build-fix loop refactor (done — `BuildLoop` extracted)
- **#10** Build timeout is 120s (fixed)
- **#17** Fixed — agent-expert architecture, `--model sonnet`, `--max-turns 50`, `--append-system-prompt`
- **#27** Fixed — JUCE knowledge kit, event-driven flow, audit pass, no templates
