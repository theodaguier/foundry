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
| `ProjectAssembler` | Writes minimal C++ stubs + expert CLAUDE.md to `/tmp/foundry-build-<uuid>/` |
| `ClaudeCodeService` | Launches Claude CLI subprocess, parses stdout stream-json |
| `BuildLoop` | CMake build with retry loop and Claude fix passes |
| `BuildRunner` | Low-level CMake process runner + smoke test |
| `GenerationQualityEnforcer` | Validates generated code has real implementation, triggers rewrite if insufficient |
| `BuildDirectoryCleaner` | Cleans `/tmp/foundry-build-*` after install and on launch |
| `PluginManager` | Persists `plugins.json`, handles install/uninstall via AppleScript |
| `PluginLogoService` | Local Stable Diffusion logo generation (Apple CoreML) |
| `DependencyChecker` | Checks Xcode CLI Tools, CMake, JUCE SDK, Claude Code CLI |
| `FoundryPaths` | Canonical Application Support paths |
| `PluginBundleInspector` | Locates and validates AU/VST3 bundles in build output |

## Key Design Decisions

- **Agent-expert architecture:** `ProjectAssembler` writes minimal compilable C++ stubs (correct class names, empty method bodies) + an expert `CLAUDE.md` with JUCE skills. Claude writes all plugin code from scratch using expert knowledge — no templates to edit.
- **Expert knowledge via CLAUDE.md:** Written into the temp project dir per generation. Contains SKILL sections (Parameter System, DSP, Interface, Presets) with JUCE patterns and constraints.
- **Claude invocation:** `claude -p "<prompt>" --dangerously-skip-permissions --output-format stream-json --verbose --max-turns 50 --model sonnet --append-system-prompt "..."`
- **Refine flow:** Modifies an existing plugin using its preserved `buildDirectory`. Full build loop runs again.
- **Quality enforcement:** `GenerationQualityEnforcer` + `GeneratedPluginValidator` check content presence (parameters exist, DSP implemented, UI controls present). Triggers up to 2 rewrite passes if insufficient.
- **Install path:** `/Library/Audio/Plug-Ins/` (system-level) via AppleScript with admin. Ensures DAW visibility.
- **Cleanup:** `BuildDirectoryCleaner.cleanAfterInstall()` removes temp dirs 10s after install. `sweepStaleDirectories()` runs on launch for dirs older than 24h.

## Plugin Types

| Type | Keywords | Stub base |
|---|---|---|
| `instrument` | synth, keys, pad, oscillator | Processor + Voice/Sound classes with renderNextBlock |
| `effect` | reverb, delay, distortion, filter | Processor with processBlock stub |
| `utility` | analyzer, meter, width, gain staging | Processor with processBlock stub |

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
```

## Generation Pipeline (in order)

1. `ProjectAssembler.assemble()` → writes stubs + expert CLAUDE.md to `/tmp/foundry-build-<uuid>/`
2. `ClaudeCodeService.run()` → Claude writes plugin code from scratch using expert knowledge
3. `BuildLoop.run()` → cmake build, up to 3 attempts with Claude fix passes
4. `GenerationQualityEnforcer.enforce()` → validates implementation quality, rewrites if insufficient
5. `PluginManager.installPlugin()` → copies to `/Library`, codesigns
6. `BuildDirectoryCleaner.cleanAfterInstall()` → removes temp dir

## Timeouts

| Step | Timeout |
|---|---|
| Claude generation | 300s |
| Claude fix pass | 180s |
| Claude quality rewrite | 240s |
| CMake build | 360s per attempt |

## Known Issues

- **#7** Smoke test only checks bundle existence, not audio validity
- **#8** Build-fix loop refactor (done — `BuildLoop` extracted)
- **#10** Build timeout is 360s; target is 120s
- **#17** Fixed — agent-expert architecture, `--model sonnet`, `--max-turns 50`, `--append-system-prompt`
