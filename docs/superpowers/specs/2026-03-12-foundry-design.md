# Foundry — Design Spec

> **Last updated:** 2026-03-18 (v3)
> **Status:** Reflects current implementation (agent-expert architecture).

## Vision

Foundry is a macOS app that lets music producers and sound designers create custom audio plugins (AU/VST3) by describing them in natural language. The app generates a real, compilable JUCE plugin locally using Claude Code as an autonomous audio developer. No coding required.

**Positioning:** "Glaze for audio plugins" — local-first, private, plugin creation from a sentence.

---

## Architecture

```
┌────────────────────────────────────────────────────┐
│                Foundry.app (SwiftUI)               │
│                                                    │
│  ┌──────────┐  ┌───────────┐  ┌─────────────────┐ │
│  │  Prompt  │→ │  Project  │→ │  ClaudeCode     │ │
│  │   View   │  │ Assembler │  │  Service (CLI)  │ │
│  └──────────┘  └───────────┘  └────────┬────────┘ │
│                                        │           │
│  ┌──────────┐  ┌───────────┐  ┌────────▼────────┐ │
│  │  Plugin  │← │  Plugin   │← │   BuildLoop     │ │
│  │ Library  │  │  Manager  │  │  + Quality      │ │
│  └──────────┘  └───────────┘  │    Enforcer     │ │
│                                └─────────────────┘ │
└────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
  /Library/Audio/               /tmp/foundry-build-*/
  Plug-Ins/{AU,VST3}            (cleaned after install)
```

### Service layer — actual files

| File | Role |
|---|---|
| `GenerationPipeline.swift` | Orchestrator — runs generate and refine flows end-to-end |
| `ProjectAssembler.swift` | Writes all JUCE project files to a temp dir at generation time |
| `ClaudeCodeService.swift` | Launches and communicates with the Claude Code CLI subprocess |
| `BuildLoop.swift` | CMake build with up to N retries and Claude fix passes |
| `BuildRunner.swift` | Low-level CMake process runner + smoke test |
| `GenerationQualityEnforcer.swift` | Validates generated code quality; triggers rewrite pass if needed |
| `BuildDirectoryCleaner.swift` | Cleans `/tmp/foundry-build-*` after install and on launch |
| `PluginManager.swift` | Persists and loads `plugins.json`; handles install and uninstall |
| `PluginLogoService.swift` | Local Stable Diffusion logo generation (Apple CoreML) |
| `DependencyChecker.swift` | Checks Xcode CLI Tools, CMake, JUCE SDK, Claude Code CLI |
| `FoundryPaths.swift` | Canonical paths for Application Support, logos, models |
| `PluginBundleInspector.swift` | Locates and validates AU/VST3 bundles in build output |

---

## User Flow

```
Home (Plugin Library)
  │
  ▼ [+ Create]
Prompt Screen
  │  "Describe the plugin you want..."
  ▼ Submit
Quick Options
  │  Format: AU / VST3 / Both  (default: Both)
  │  Layout: Stereo / Mono     (default: Stereo)
  │  Presets: 0 / 3 / 5 / 10  (default: 5)
  ▼ Confirm (or skip → defaults apply)
Generation Progress
  │  1. Preparing project   ✓
  │  2. Generating DSP...   ⟳
  │  3. Generating UI
  │  4. Compiling
  │  5. Installing
  ▼
Result Screen               Error Screen
  │  "Open in DAW"            │  Error summary
  │  "Regenerate"             │  Retry / Modify prompt
  ▼                           ▼
Back to Home               Back to Prompt

─── Refine Flow ────────────────────────────────────
Plugin Library → [Refine] → RefineView
  → enter modification text
  → RefineProgressView (same steps, no Preparing)
  → Result / Error
```

---

## Plugin Types

| Type | Keyword detection | Stub base |
|---|---|---|
| `instrument` | synth, keys, pad, oscillator, arpeggiator… | Processor + Voice/Sound classes with `renderNextBlock` |
| `effect` | reverb, delay, distortion, filter, chorus… | Processor with `processBlock` stub |
| `utility` | analyzer, meter, width, gain staging, tool… | Processor with `processBlock` stub |

Inferred by `ProjectAssembler.inferPluginType()` from the user prompt. Defaults to `effect`.

A secondary inference — `InterfaceStyle` (`Focused` / `Balanced` / `Exploratory`) — affects the CLAUDE.md UI direction hint.

---

## Agent-Expert System

`ProjectAssembler` writes minimal compilable C++ stubs and an expert `CLAUDE.md` to `/tmp/foundry-build-<uuid>/` at generation time. Claude then writes all plugin code from scratch using the expert knowledge — no templates to edit.

### Files written per generation

```
/tmp/foundry-build-<uuid>/
├── CLAUDE.md                  # Expert knowledge document with JUCE skills
├── CMakeLists.txt             # Pre-configured for AU + VST3
└── Source/
    ├── PluginProcessor.h      # Minimal stub (correct class names, empty methods)
    ├── PluginProcessor.cpp
    ├── PluginEditor.h
    ├── PluginEditor.cpp
    └── FoundryLookAndFeel.h   # Full design system (dark, knobs, sliders)
```

### Expert CLAUDE.md contains

The per-generation `CLAUDE.md` is an expert knowledge document with SKILL sections:

- **SKILL: Parameter System** — `AudioParameterFloat/Choice/Bool`, `NormalisableRange`, skewed ranges, `SmoothedValue`
- **SKILL: DSP** — `processBlock` structure, `juce::dsp` classes, `prepareToPlay`, dry/wet patterns
- **SKILL: Interface** — control types, APVTS attachments, layout patterns, visual rules
- **SKILL: Presets** (if `presetCount > 0`) — program system, ComboBox selector, preset data arrays
- Instrument-specific: voice rendering with `renderNextBlock`, ADSR, oscillator patterns
- Utility-specific: metering, gain staging, mid/side guidelines

### What Claude writes from scratch

- Parameters in `createParameterLayout()` (names, ranges, defaults)
- DSP in `processBlock()` (oscillators, filters, effects, modulations)
- UI layout in `PluginEditor` (controls, sections, sizing)
- Presets via JUCE program system (if `presetCount > 0`)
- Accent colour in `FoundryLookAndFeel.h`

### Quality enforcement

After build succeeds, `GenerationQualityEnforcer` checks via `GeneratedPluginValidator`:
1. Parameters exist in `createParameterLayout()`
2. `processBlock()` body has meaningful DSP (> 200 chars)
3. Every `ParameterID` has a matching control string in `PluginEditor.cpp`
4. Editor has sufficient visible controls (`addAndMakeVisible` calls)
5. Instrument plugins have `renderNextBlock` voice implementation

If validation fails → rewrite pass (max 2 attempts) → rebuild → re-validate.

---

## Claude Code Integration

### CLI invocation

```bash
claude \
  -p "<generation prompt>" \
  --dangerously-skip-permissions \
  --output-format stream-json \
  --verbose \
  --max-turns 50 \
  --model sonnet \
  --append-system-prompt "You MUST use tools (Read, Edit, Write, Bash) on every turn. Never respond with only text — always take action by reading or editing files."
```

Expert knowledge is delivered via `CLAUDE.md` written into the project directory. Claude reads it automatically on startup. The `--append-system-prompt` flag enforces tool usage on every turn, preventing planning-only turns. `--model sonnet` reduces thinking overhead for faster generation.

### BuildLoop

`BuildLoop.run()` is the shared build-fix loop used by both generate and refine pipelines:

```
Claude writes plugin code from scratch (using expert CLAUDE.md)
    │
    ▼
BuildLoop.run(maxAttempts: 3)
    │
    ├─ cmake --build
    │       │
    │   success?──► smokeTest() ──► pass ──► done
    │       │                  └──► fail ──► fix pass → retry
    │       │
    └─ fail ──► ClaudeCodeService.fix(errors) → retry
                (throws GenerationError.buildFailed after 3 failures)
    │
    ▼
GenerationQualityEnforcer.enforce()   ← validates content presence, triggers rewrite if needed
    │
    ▼
PluginManager.installPlugin()   ← copies to /Library, codesigns, kills AudioComponentRegistrar
    │
    ▼
BuildDirectoryCleaner.cleanAfterInstall()   ← removes /tmp dir after 10s grace period
```

### Smoke test

Current: verifies that an AU or VST3 bundle file exists in the build output.
Planned: `auval` validation (see issue #7).

### Timeouts

| Step | Timeout |
|---|---|
| Claude generation | 300s (5 min) |
| Claude fix pass | 180s |
| Claude quality rewrite | 240s |
| CMake build | 360s per attempt |
| Logo generation | 90s |

---

## Dependency Management

Checked on every launch via `DependencyChecker`:

| Dependency | Check | Install |
|---|---|---|
| Xcode CLI Tools | `xcode-select -p` | `xcode-select --install` |
| CMake | `which cmake` | `brew install cmake` or embedded |
| JUCE SDK | `~/Library/Application Support/Foundry/JUCE/` | Auto-download (~200MB) |
| Claude Code CLI | `which claude` | Manual: `npm install -g @anthropic-ai/claude-code` |

---

## Data Model

```swift
struct Plugin: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: PluginType           // .instrument | .effect | .utility
    var prompt: String
    var createdAt: Date
    var formats: [PluginFormat]    // .au | .vst3
    var installPaths: InstallPaths // au: String?, vst3: String?
    var iconColor: String          // hex e.g. "#C8C4BC"
    var logoAssetPath: String?     // path to PNG, nil = use type icon fallback
    var status: PluginStatus       // .installed | .failed | .building
    var buildDirectory: String?    // /tmp/foundry-build-* path, used by Refine
}
```

Persisted to `~/Library/Application Support/Foundry/plugins.json`.

### plugins.json schema

```json
{
  "plugins": [
    {
      "id": "uuid-v4",
      "name": "DrakeVox Synth",
      "type": "instrument",
      "prompt": "An RnB synth with Drake-style presets",
      "createdAt": "2026-03-12T14:30:00Z",
      "formats": ["AU", "VST3"],
      "installPaths": {
        "au": "/Library/Audio/Plug-Ins/Components/DrakeVoxSynth.component",
        "vst3": "/Library/Audio/Plug-Ins/VST3/DrakeVoxSynth.vst3"
      },
      "iconColor": "#C8C4BC",
      "logoAssetPath": null,
      "status": "installed",
      "buildDirectory": "/tmp/foundry-build-abc12345"
    }
  ]
}
```

---

## Storage Layout

```
~/Library/Application Support/Foundry/
├── plugins.json
├── JUCE/                          # JUCE SDK cache (~200MB)
├── PluginLogos/
│   └── <plugin-id>/
│       └── logo.png               # Generated by PluginLogoService
└── ImageModels/
    └── coreml-stable-diffusion-2-1-base-palettized/
        └── original_compiled/     # ~1.5GB, downloaded on first logo generation

/Library/Audio/Plug-Ins/           # System-level install (admin required)
├── Components/<Name>.component    # AU
└── VST3/<Name>.vst3

/tmp/foundry-build-<uuid>/         # Temp per generation, removed after install
```

---

## Plugin Logo Generation

Separate feature, triggered manually from the plugin detail view.

- **Engine:** Apple `ml-stable-diffusion` Swift package
- **Model:** `apple/coreml-stable-diffusion-2-1-base-palettized` (original_compiled)
- **Config:** `cpuAndGPU`, 20 steps, 512×512, `reduceMemory = true`
- **Timeout:** 90s
- **Prompt:** Auto-constructed from `plugin.name`, `plugin.type`, `plugin.prompt`
- **Storage:** `~/Library/Application Support/Foundry/PluginLogos/<id>/logo.png`
- **Fallback:** If `logoAssetPath` is nil or file missing → type icon + accent color

Model is downloaded on first use only. Failure to install does not block the main app.

---

## Install

Plugins are installed to `/Library/Audio/Plug-Ins/` (system-level) via AppleScript with admin privileges:

```
rm -rf '<dest>'
ditto '<src>' '<dest>'
xattr -cr '<dest>'
codesign --force --deep --sign - '<dest>'
killall AudioComponentRegistrar  # AU only
```

System-level install ensures visibility across all DAWs without per-app sandbox exceptions.

---

## MVP Scope

### In (v1)

- Full generate flow: prompt → quick options → generation progress → result
- Full refine flow: plugin detail → refine → progress → result
- Three archetypes: instrument, effect, utility (agent-expert with JUCE skills)
- FoundryLookAndFeel design system
- Build loop with 3 retries + content-presence validator + rewrite pass
- AU + VST3 install to `/Library`
- Plugin Library (grid, type icon or logo)
- Dependency checker + setup screen
- Error screen with retry/modify
- Plugin logo generation (local Stable Diffusion, manual trigger)
- Build directory cleanup (post-install + stale sweep on launch)
- Settings view

### Out (later)

- Integrated audio preview (AU host in-app)
- More archetypes (drum machine, sampler, multi-effect)
- Export/share plugins
- Community gallery
- `auval` smoke test (issue #7)
- Dynamically generated quick options

---

## Open Issues

| # | Title |
|---|---|
| #7 | Smoke test only checks bundle existence — upgrade to `auval` |
| #8 | Build-fix loop refactor (in progress) |
| #9 | Temp build dir cleanup (implemented via `BuildDirectoryCleaner`) |
| #10 | Build timeout 360s vs spec 120s |
| #11 | Spec/CLAUDE.md sync (this document) |

---

## Changelog

| Date | Change |
|---|---|
| 2026-03-12 | Initial design spec |
| 2026-03-15 | Added plugin logo generation spec |
| 2026-03-18 (v1) | Synced with implementation: programmatic templates, CLI args, install path, Refine flow, utility type |
| 2026-03-18 (v2) | Full rewrite from code — added BuildLoop, BuildDirectoryCleaner, GenerationQualityEnforcer, PipelineCallbacks, updated service table, storage layout, timeouts, install flow |
| 2026-03-18 (v3) | Template → agent-expert architecture: stubs + expert CLAUDE.md with JUCE skills, content-presence validation, `--model sonnet`, `--max-turns 50`, `--append-system-prompt` (closes #17) |
