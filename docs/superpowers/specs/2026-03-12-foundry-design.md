# Foundry — Design Spec

## Vision

Foundry is a macOS app that lets music producers and sound designers create custom audio plugins (AU/VST3) by describing them in natural language. The app generates a real, compilable JUCE plugin locally using Claude Code as an autonomous audio developer. No coding required.

**Positioning:** "Glaze for audio plugins" — local-first, private, conversational plugin creation.

## Architecture

```
┌─────────────────────────────────────────────┐
│           Foundry.app (SwiftUI)             │
│                                             │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Prompt  │→ │ Project  │→ │  Claude   │  │
│  │  View   │  │ Assembler│  │  Code CLI │  │
│  └─────────┘  └──────────┘  └─────┬─────┘  │
│                                   │         │
│  ┌─────────┐  ┌──────────┐  ┌────▼──────┐  │
│  │ Plugin  │← │  Build   │← │  Code     │  │
│  │ Library │  │  Runner  │  │  Output   │  │
│  └─────────┘  └──────────┘  └───────────┘  │
└─────────────────────────────────────────────┘
         │                          │
         ▼                          ▼
   ~/Library/Audio/          JUCE Templates
   Plug-Ins/{AU,VST3}       (embedded in app bundle)
```

### Modules

1. **Prompt View** — Text input + dynamically generated quick options.
2. **Project Assembler** — Copies the appropriate JUCE template to a temp build directory, injects context (user prompt, design system reference, build config).
3. **Claude Code CLI** — Subprocess running `claude` in non-interactive mode. Receives a structured mission, edits C++/JUCE code (DSP, UI, presets).
4. **Build Runner** — Runs CMake + Xcode build. On failure, parses errors and sends them back to Claude Code for correction (max 3 retries).
5. **Plugin Library** — Grid view of all generated plugins with metadata, preview, and quick actions.

## User Flow

```
Home (Plugin Library)
  │
  ▼ [+ Create]
Prompt Screen
  │  "Décris le plugin que tu veux créer..."
  ▼ Submit
Quick Options (optional)
  │  2-3 dynamic questions based on the prompt
  │  (e.g. "How many presets?", "Stereo or mono?", "AU, VST3, or both?")
  ▼ Confirm (or skip)
Generation Progress
  │  1. Preparing project     ✓
  │  2. Generating DSP...     ⟳
  │  3. Generating UI
  │  4. Compiling
  │  5. Installing
  ▼ Done
Result Screen
  │  Plugin UI preview
  │  "Open in DAW" button
  │  "Regenerate" button
  ▼
Back to Home
```

- The flow is linear: 3 screens max between idea and result.
- Quick Options are skippable — the user can let Claude decide everything.
- The progress screen shows real status by parsing Claude Code CLI stdout in streaming.
- "Regenerate" relaunches the same prompt with variations, not a chat.

## JUCE Templates & Design System

### Template Structure (embedded in app bundle)

```
Foundry.app/Resources/templates/
├── base/                      # Shared across all plugins
│   ├── CMakeLists.txt         # Pre-configured build system (AU + VST3)
│   ├── FoundryLookAndFeel.h   # Design system: colors, fonts, knobs, sliders
│   ├── FoundryPresetManager.h # Preset save/load/browse
│   └── JuceLibraryCode/
├── synth/                     # Synthesizer template
│   ├── PluginProcessor.h/cpp  # Skeleton with audio bus config
│   └── PluginEditor.h/cpp     # UI scaffolding
└── effect/                    # Effect template
    ├── PluginProcessor.h/cpp
    └── PluginEditor.h/cpp
```

### What the template provides (fixed):
- Working CMake build system
- `FoundryLookAndFeel` — design system (dark, minimal, Glaze-inspired: rounded corners, accent colors, clean typography)
- Preset manager (save/load/browse)
- Audio bus configuration (mono/stereo)

### What Claude Code generates (free):
- DSP in `PluginProcessor` (oscillators, filters, effects, modulations)
- UI layout in `PluginEditor` (which knobs, where, how many, labels)
- Presets (XML files with parameter values)
- Audio parameters (names, ranges, defaults)

### The contract:
Claude Code receives a system prompt that says: "Use `FoundryLookAndFeel` for all components, do not create your own colors/fonts, respect this API for parameters." This guarantees visual consistency across all generated plugins.

## Claude Code Integration

### Invocation

```swift
// Non-interactive subprocess
claude --print --output-format json \
  --system-prompt <system.md> \
  "Here is the JUCE project at /tmp/foundry-build-xxxx/.
   Generate a <user prompt>.
   Use FoundryLookAndFeel.
   When done, stop editing."
```

### System prompt contains:
- FoundryLookAndFeel API rules
- Template structure and which files to edit
- Constraints: no external dependencies, stay within JUCE, AU+VST3 formats
- Code style conventions (parameter names, naming patterns)

### Build-fix loop:

```
Project Assembler copies template → /tmp/foundry-build-xxxx/
          │
          ▼
   Claude Code edits files
          │
          ▼
   Build Runner runs: cmake --build
          │
     ┌────┴────┐
  Success    Failure
     │         │
     ▼         ▼
  Copy         Parse errors,
  .vst3/.component    send back to Claude Code
  to ~/Library/       (max 3 retries)
  Audio/Plug-Ins/
```

### Progress parsing:
The app reads Claude Code's stdout in streaming, detects patterns (file edits, generation completion) to update the progress bar in real time.

## Dependency Management (First Launch)

On first launch (and verified on each subsequent launch), the app checks:

| Dependency | Check | Install method |
|---|---|---|
| Xcode CLI Tools | `xcode-select -p` | `xcode-select --install` (system prompt) |
| CMake | `which cmake` | `brew install cmake` or embedded binary |
| JUCE SDK | Check `~/Library/Application Support/Foundry/JUCE/` | Download + extract automatically |
| Claude Code CLI | `which claude` | User must install manually (`npm install -g @anthropic-ai/claude-code`) — shown in onboarding |

The setup screen is a clean visual checklist, not a terminal.

## Plugin Library (Home Screen)

Grid of generated plugins. Each card shows:
- Screenshot of the plugin UI (captured post-generation)
- Plugin name (generated by Claude or user-provided)
- Type (synth/effect) + installed formats
- Creation date
- Actions on click: open folder, regenerate, delete

Metadata stored in: `~/Library/Application Support/Foundry/plugins.json`

## Design Direction

- **Style:** Dark, minimal, clean — inspired by Glaze/Raycast
- **Generated plugins inherit the same DA** via `FoundryLookAndFeel`
- Rounded corners, subtle accent colors, clean sans-serif typography
- Consistent across the app and every plugin it produces

## MVP Scope

### In (v1):
- SwiftUI app with full flow: prompt → quick options → generation → result
- One JUCE "synth" template + one "effect" template
- Basic FoundryLookAndFeel (dark, minimal, knobs/sliders/labels)
- Claude Code as subprocess with structured system prompt
- Build loop with 3 retries max
- Automatic AU + VST3 installation
- Plugin Library (simple grid)
- Dependency checker on first launch
- macOS only

### Out (later):
- Conversational iteration on existing plugins
- Integrated audio preview (minimal AU host in-app)
- More templates (drum machine, sampler, multi-effect)
- Export/share plugins between users
- Community gallery (Glaze Store-style)
- Alternative UI themes for plugins
- Prompt analysis to estimate generation time

## Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| App framework | SwiftUI | Native macOS integration, filesystem access, notifications, menu bar |
| AI backend | Claude Code CLI (subprocess) | Simple, leverages existing agent intelligence, no API reimplementation |
| Plugin framework | JUCE | Industry standard for AU/VST3, mature C++ framework |
| Build system | CMake | JUCE's recommended build approach |
| Generation model | Hybrid (template + free generation) | Template ensures compilation reliability, free generation allows creative DSP/UI |
| Plugin UI | Styled via shared FoundryLookAndFeel | Consistent DA, Foundry brand identity in every plugin |
| Iteration model | One-shot (with regenerate option) | Simpler UX, no chat state management |
