# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Foundry is a macOS app (SwiftUI) that lets users create custom audio plugins (AU/VST3) by describing them in natural language. It generates real, compilable JUCE plugins locally using Claude Code CLI as an autonomous subprocess. No coding required from the end user.

**Status:** Active development — core pipeline, refine flow, and plugin logo generation are implemented.

## Architecture

Five modules inside a SwiftUI app:

1. **Prompt View** — Text input + quick options (format, stereo/mono, preset count)
2. **Project Assembler** — Writes JUCE project files programmatically to `/tmp/foundry-build-<uuid>/`, injects context via `CLAUDE.md` written into the project dir
3. **Claude Code CLI** — Subprocess (`claude -p ... --dangerously-skip-permissions --output-format stream-json --verbose --max-turns 30`) running in agentic mode, edits C++/JUCE files
4. **Build Runner** — CMake + Xcode build with error parsing, 3 retries, smoke test (bundle existence check — see issue #7 for planned `auval` upgrade)
5. **Plugin Library** — Grid view of generated plugins with metadata stored in `~/Library/Application Support/Foundry/plugins.json`

## Tech Stack

- **App:** Swift / SwiftUI (macOS only)
- **Plugins:** C++ / JUCE framework
- **Build:** CMake → Xcode
- **AI:** Claude Code CLI as subprocess (non-interactive, stdout stream-json parsing)
- **Plugin formats:** AU + VST3, installed to `/Library/Audio/Plug-Ins/` (system-level, requires admin via AppleScript)
- **Logo generation:** Apple CoreML Stable Diffusion (local, on-device)

## Key Design Decisions

- **Programmatic templates:** No bundle assets — `ProjectAssembler.swift` writes all JUCE template files (CMakeLists.txt, PluginProcessor, PluginEditor, FoundryLookAndFeel.h) in Swift at generation time. This makes templates versionable and editable without Xcode asset management.
- **Claude via project CLAUDE.md:** The system prompt is written as `CLAUDE.md` into the temp project dir rather than passed via `--system-prompt`. This allows the prompt to reference actual file paths and be inspected post-generation.
- **Hybrid generation:** JUCE templates provide compilable skeletons; Claude generates DSP logic, UI layout, presets, and parameters.
- **One-shot + Refine model:** Initial generation is one-shot. The Refine flow (`RefineView` → `RefineProgressView` → `executeRefine()`) allows targeted modifications to an existing plugin using the preserved `buildDirectory`.
- **Build-fix loop:** Max 3 build retries. On failure after retries, show error screen.
- **Quality enforcement:** `GeneratedPluginValidator` checks that Claude actually modified the template (detects placeholder markers, validates parameter↔control pairing). If validation fails, a rewrite pass is triggered before returning the plugin.
- **Install path:** Plugins are installed to `/Library/Audio/Plug-Ins/` (not `~/Library`) so they are visible to all DAWs without per-app sandbox exceptions. Requires admin privileges (AppleScript prompt).
- **Timeouts:** 5 min generation, 6 min per build attempt (see issue #10 — should be reduced to 2 min).
- **Dependencies:** Xcode CLI Tools, CMake (brew), JUCE SDK (~200MB cached in `~/Library/Application Support/Foundry/JUCE/`), Claude Code CLI (manual npm install)

## Plugin Types

Three archetypes are supported:

| Type | Keyword examples | Template |
|---|---|---|
| `instrument` | synth, keys, pad, oscillator, arpeggiator | Polyphonic JUCE Synthesiser with ADSR voices |
| `effect` | reverb, delay, distortion, filter, chorus | Stereo/mono processor with gain + mix |
| `utility` | analyzer, meter, width, gain staging | Pass-through with input/output gain + stereo width |

## Data Model

```swift
struct Plugin: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: PluginType          // .instrument | .effect | .utility
    var prompt: String
    var createdAt: Date
    var formats: [PluginFormat]   // .au | .vst3
    var installPaths: InstallPaths
    var iconColor: String         // hex e.g. "#C8C4BC"
    var logoAssetPath: String?    // path to generated PNG, nil = use type icon
    var status: PluginStatus      // .installed | .failed | .building
    var buildDirectory: String?   // path to /tmp/foundry-build-* for refine
}
```

Persisted to: `~/Library/Application Support/Foundry/plugins.json`

## Storage Layout

```
~/Library/Application Support/Foundry/
├── plugins.json
├── JUCE/                          # JUCE SDK cache
├── PluginLogos/
│   └── <plugin-id>/
│       └── logo.png
└── ImageModels/
    └── coreml-stable-diffusion-2-1-base-palettized/
        └── original_compiled/

/tmp/foundry-build-<uuid>/         # Temp build dirs (cleaned after install — see issue #9)
├── CLAUDE.md                      # System prompt for this generation
├── CMakeLists.txt
└── Source/
    ├── PluginProcessor.h/cpp
    ├── PluginEditor.h/cpp
    └── FoundryLookAndFeel.h
```

## Known Issues

See GitHub Issues for active work items:

- **#7** — Smoke test only checks bundle existence, not audio validity (`auval` upgrade planned)
- **#8** — Build-fix loop is duplicated between generate and refine pipelines
- **#9** — Temp build directories are not cleaned up after generation
- **#10** — Build timeout is 360s; should be 120s per attempt
- **#11** — Some spec documentation still reflects pre-implementation state

## Development Notes

- Do not modify `CMakeLists.txt` in generated projects — it is correct and must not be touched during build-fix iterations
- The `templateMarker` string (`FOUNDRY_TEMPLATE_PLACEHOLDER`) is used to detect unmodified template code; if it remains after generation, `GeneratedPluginValidator` will trigger a rewrite pass
- Claude Code runs with `--max-turns 30`; adjust in `ClaudeCodeService.swift` if generations are truncating
- Logo generation requires Apple Silicon and downloads a ~1.5GB CoreML model on first use
