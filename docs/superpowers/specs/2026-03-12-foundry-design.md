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
  │  "Describe the plugin you want to create..."
  ▼ Submit
Quick Options
  │  3 hardcoded questions with sensible defaults:
  │  1. Format: AU / VST3 / Both (default: Both)
  │  2. Stereo / Mono (default: Stereo)
  │  3. Number of presets: 0 / 3 / 5 / 10 (default: 5)
  │  User can skip (defaults apply)
  ▼ Confirm (or skip)
Generation Progress
  │  1. Preparing project     ✓
  │  2. Generating DSP...     ⟳
  │  3. Generating UI
  │  4. Compiling
  │  5. Installing
  ▼ Done / Error
Result Screen (success)          Error Screen (failure)
  │  Plugin type icon              │  "Generation failed"
  │  "Open in DAW" button          │  Error summary
  │  "Regenerate" button           │  "Retry" / "Modify prompt"
  ▼                                ▼
Back to Home                     Back to Prompt Screen
```

- The flow is linear: 3 screens max between idea and result.
- Quick Options are hardcoded (not LLM-generated) with sensible defaults — skip applies defaults.
- The progress screen shows real status by parsing Claude Code CLI stdout in streaming.
- "Regenerate" relaunches the same prompt with variations, not a chat.
- On failure (after 3 build retries or timeout), the user sees an error screen with the option to retry or modify their prompt.

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

```bash
# Autonomous mode — Claude Code directly edits files in the project directory.
# The app launches claude in non-interactive mode with --allowedTools
# to restrict it to file editing and bash (for build commands).
claude --dangerously-skip-permissions \
  --system-prompt system.md \
  --allowedTools Edit,Write,Read,Bash \
  "Here is the JUCE project at /tmp/foundry-build-xxxx/.
   Generate a <user prompt>.
   Use FoundryLookAndFeel.
   When done, stop editing."
```

The app communicates with the Claude Code subprocess via its stdout/stderr streams. Claude Code runs in agentic mode (not `--print`) so it can directly read and write files in the project directory.

### System prompt contains:
- FoundryLookAndFeel API rules and component catalog
- Template structure and which files to edit
- Constraints: no external dependencies, stay within JUCE, AU+VST3 formats
- Code style conventions (parameter names, naming patterns)
- Curated JUCE API reference for common DSP patterns (oscillators, filters, envelopes)
- Example DSP snippets for typical use cases (subtractive synth, delay effect, etc.)

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
  Smoke test   Parse compiler errors,
  (render 1s   send back to Claude Code
  of audio,    (max 3 retries)
  check for         │
  silence/NaN)      │
     │              │
  ┌──┴──┐     After 3 failures:
Pass   Fail   show error screen with
  │     │     "Generation failed" message,
  ▼     ▼     option to retry or modify prompt
Copy   Send back
plugin to Claude Code
       (1 retry)
```

### Timeouts and resource limits:
- **Generation timeout:** 5 minutes per Claude Code session. If exceeded, the process is killed and the user sees a timeout error with option to retry.
- **Build timeout:** 2 minutes per build attempt.
- **Disk cleanup:** Temp build directories in `/tmp/foundry-build-*` are cleaned up after successful installation or after 24 hours.

### Progress parsing:
The app reads Claude Code's stdout stream and maps events to progress steps:
- File write/edit events → "Generating DSP" / "Generating UI"
- Bash tool calls containing `cmake` → "Compiling"
- Process exit with success → "Installing"
The exact parsing relies on Claude Code's streaming output format (JSON lines with tool use events).

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
- Type icon (synth/effect) with generated accent color
- Plugin name (generated by Claude or user-provided)
- Installed formats (AU/VST3)
- Creation date
- Actions on click: open folder, regenerate, delete

### Plugin metadata schema (`plugins.json`):

```json
{
  "plugins": [
    {
      "id": "uuid-v4",
      "name": "DrakeVox Synth",
      "type": "synth",
      "prompt": "Un synthé RnB avec des presets à la Drake",
      "createdAt": "2026-03-12T14:30:00Z",
      "formats": ["AU", "VST3"],
      "installPaths": {
        "au": "~/Library/Audio/Plug-Ins/Components/DrakeVoxSynth.component",
        "vst3": "~/Library/Audio/Plug-Ins/VST3/DrakeVoxSynth.vst3"
      },
      "iconColor": "#7C3AED",
      "status": "installed"
    }
  ]
}
```

Plugin cards use a **type-based icon** (synth/effect) with a generated accent color — no UI screenshot capture in MVP.

## Design Direction

- **Style:** Dark, minimal, clean — inspired by Glaze/Raycast
- **Generated plugins inherit the same visual identity** via `FoundryLookAndFeel`
- Rounded corners, subtle accent colors, clean sans-serif typography
- Consistent across the app and every plugin it produces

## MVP Scope

### In (v1):
- SwiftUI app with full flow: prompt → quick options → generation → result
- One JUCE "synth" template + one "effect" template
- Basic FoundryLookAndFeel (dark, minimal, knobs/sliders/labels)
- Claude Code as subprocess with structured system prompt
- Build loop with 3 retries max + smoke test (1s audio render, check for silence/NaN)
- Automatic AU + VST3 installation
- Plugin Library (simple grid with type icons, no screenshots)
- Dependency checker on first launch
- Error screen with retry/modify options
- macOS only

### Out (later):
- Conversational iteration on existing plugins
- Integrated audio preview (minimal AU host in-app)
- More templates (drum machine, sampler, multi-effect)
- Export/share plugins between users
- Community gallery (Glaze Store-style)
- Alternative UI themes for plugins
- Prompt analysis to estimate generation time
- Plugin UI screenshot capture for library cards
- Dynamically generated quick options (LLM-powered)

## JUCE Licensing

Foundry uses JUCE under the [JUCE Personal license](https://juce.com/legal/juce-8-licence/) (free for projects with revenue under $50k). Generated plugins are for personal use. If Foundry becomes a commercial product, a JUCE commercial license will be required. This is noted here as a known future consideration.

## Known Risks

| Risk | Mitigation |
|---|---|
| Claude Code generates non-compilable C++ | Template provides a compilable skeleton; Claude only fills in DSP/UI. Build-fix loop retries 3 times. System prompt includes curated JUCE API docs and example DSP snippets. |
| Plugin compiles but produces silence/noise/crashes | Post-build smoke test renders 1 second of audio and checks for silence, NaN, or inf values. Fails the build if detected. |
| Claude Code subprocess hangs | 5-minute timeout with process kill. User sees timeout error with retry option. |
| Large JUCE SDK download on first launch | SDK is ~200MB. App shows download progress. Cached in Application Support. |
| Claude Code CLI not installed | Only dependency requiring manual install. Clear onboarding instructions with link. |

## Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| App framework | SwiftUI | Native macOS integration, filesystem access, notifications, menu bar |
| AI backend | Claude Code CLI (subprocess) | Simple, leverages existing agent intelligence, no API reimplementation |
| Plugin framework | JUCE | Industry standard for AU/VST3, mature C++ framework |
| Build system | CMake | JUCE's recommended build approach |
| Generation model | Hybrid (template + free generation) | Template ensures compilation reliability, free generation allows creative DSP/UI |
| Plugin UI | Styled via shared FoundryLookAndFeel | Consistent visual identity, Foundry brand in every plugin |
| Iteration model | One-shot (with regenerate option) | Simpler UX, no chat state management |
