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
| `ProjectAssembler` | Writes JUCE project files to `/tmp/foundry-build-<uuid>/` |
| `ClaudeCodeService` | Launches Claude CLI subprocess, parses stdout stream-json |
| `BuildLoop` | CMake build with retry loop and Claude fix passes |
| `BuildRunner` | Low-level CMake process runner + smoke test |
| `GenerationQualityEnforcer` | Validates generated code, triggers rewrite if too close to template |
| `BuildDirectoryCleaner` | Cleans `/tmp/foundry-build-*` after install and on launch |
| `PluginManager` | Persists `plugins.json`, handles install/uninstall via AppleScript |
| `PluginLogoService` | Local Stable Diffusion logo generation (Apple CoreML) |
| `DependencyChecker` | Checks Xcode CLI Tools, CMake, JUCE SDK, Claude Code CLI |
| `FoundryPaths` | Canonical Application Support paths |
| `PluginBundleInspector` | Locates and validates AU/VST3 bundles in build output |

## Key Design Decisions

- **Programmatic templates:** `ProjectAssembler` writes all JUCE files in Swift at runtime — no bundle assets. Templates are versionable in code.
- **System prompt via CLAUDE.md:** The system prompt for each generation is written as `CLAUDE.md` into the temp project dir, not via `--system-prompt`. Claude reads it automatically.
- **Claude invocation:** `claude -p "<prompt>" --dangerously-skip-permissions --output-format stream-json --verbose --max-turns 30`
- **Refine flow:** Modifies an existing plugin using its preserved `buildDirectory`. Full build loop runs again.
- **Quality enforcement:** `GenerationQualityEnforcer` + `GeneratedPluginValidator` check that Claude actually customised the template. Triggers up to 2 rewrite passes if not.
- **Install path:** `/Library/Audio/Plug-Ins/` (system-level) via AppleScript with admin. Ensures DAW visibility.
- **Cleanup:** `BuildDirectoryCleaner.cleanAfterInstall()` removes temp dirs 10s after install. `sweepStaleDirectories()` runs on launch for dirs older than 24h.

## Plugin Types

| Type | Keywords | Template base |
|---|---|---|
| `instrument` | synth, keys, pad, oscillator | Polyphonic Synthesiser with ADSR voices |
| `effect` | reverb, delay, distortion, filter | Processor with gain + mix |
| `utility` | analyzer, meter, width, gain staging | Pass-through with input/output gain + width |

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

1. `ProjectAssembler.assemble()` → writes files to `/tmp/foundry-build-<uuid>/`
2. `ClaudeCodeService.run()` → Claude edits the JUCE source files
3. `GenerationQualityEnforcer.enforce()` → validates quality, rewrites if needed
4. `BuildLoop.run()` → cmake build, up to 3 attempts with Claude fix passes
5. `PluginManager.installPlugin()` → copies to `/Library`, codesigns
6. `BuildDirectoryCleaner.cleanAfterInstall()` → removes temp dir

## Timeouts

| Step | Timeout |
|---|---|
| Claude generation | 300s |
| Claude fix pass | 180s |
| Claude quality rewrite | 240s |
| CMake build | 360s per attempt |

## Template Marker

`FOUNDRY_TEMPLATE_PLACEHOLDER` — appears in starter code to mark sections Claude must replace. If this string remains after generation, `GeneratedPluginValidator` rejects the plugin and triggers a rewrite pass.

## Known Issues

- **#7** Smoke test only checks bundle existence, not audio validity
- **#8** Build-fix loop refactor in progress
- **#10** Build timeout is 360s; target is 120s
