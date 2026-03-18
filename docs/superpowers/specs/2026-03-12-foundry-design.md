# Foundry — Design Spec

> **Last updated:** 2026-03-18
> **Status:** Reflects current implementation. See changelog at the bottom for revisions.

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
   /Library/Audio/           Programmatic JUCE
   Plug-Ins/{AU,VST3}        templates (in Swift)
```

### Modules

1. **Prompt View** — Text input + quick options (hardcoded: format, stereo/mono, preset count).
2. **Project Assembler** — Writes JUCE project files programmatically to a temp dir. No bundle assets — templates are generated in Swift at runtime and written to `/tmp/foundry-build-<uuid>/`.
3. **Claude Code CLI** — Subprocess running `claude` in non-interactive mode (`-p`, `--output-format stream-json`, `--max-turns 30`). The system prompt is delivered via a `CLAUDE.md` file written into the project dir, not via `--system-prompt`.
4. **Build Runner** — Runs CMake + Xcode build. On failure, parses errors and sends them back to Claude Code for correction (max 3 retries).
5. **Plugin Library** — Grid view of all generated plugins with metadata, logo, and quick actions.

## User Flow

```
Home (Plugin Library)
  │
  ▼ [+ Create]
Prompt Screen
  │  "Describe the plugin you want to create..."
  ▼ Submit
Quick Options
  │  3 questions with sensible defaults:
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

─── Refine Flow (from Plugin Library) ─────────────────────
Plugin Detail → [Refine] → RefineView → RefineProgressView → Result
```

- The generate flow is linear: 3 screens max between idea and result.
- "Regenerate" relaunches the same prompt with variations, not a chat.
- **Refine** is a separate flow that modifies an existing plugin using its preserved `buildDirectory`.
- On failure (after 3 build retries or timeout), the user sees an error screen with the option to retry or modify their prompt.

## Plugin Types

Three archetypes are supported:

| Type | Keyword detection | Template base |
|---|---|---|
| `instrument` | synth, keys, pad, oscillator, arpeggiator… | Polyphonic `juce::Synthesiser` with ADSR voices |
| `effect` | reverb, delay, distortion, filter, chorus… | Stereo/mono processor with gain + mix |
| `utility` | analyzer, meter, width, gain staging, tool… | Pass-through with input/output gain + stereo width |

Type is inferred from the user prompt by `ProjectAssembler.inferPluginType()`. The inference is keyword-based and intentionally conservative (defaults to `effect`).

## Template System

### How it works (implementation)

Templates are **not** bundle assets. `ProjectAssembler.swift` writes all files programmatically in Swift:

- `CMakeLists.txt` — pre-configured for AU + VST3, correct for all three archetypes
- `Source/PluginProcessor.h/.cpp` — working skeleton with `AudioProcessorValueTreeState`, starter parameters marked with `FOUNDRY_TEMPLATE_PLACEHOLDER`
- `Source/PluginEditor.h/.cpp` — working UI skeleton with starter knobs, also marked
- `Source/FoundryLookAndFeel.h` — full design system (dark, knobs, sliders, labels)
- `CLAUDE.md` — system prompt for this specific generation (prompt, archetype, interface style, rules, DSP snippets)

### What Claude generates (free)

- DSP in `PluginProcessor` (oscillators, filters, effects, modulations)
- UI layout in `PluginEditor` (which knobs, where, how many, labels)
- Presets (via JUCE program system in `PluginProcessor`)
- Audio parameters (names, ranges, defaults)
- Accent colour in `FoundryLookAndFeel.h`

### Quality enforcement

After generation, `GeneratedPluginValidator` checks:
1. No `FOUNDRY_TEMPLATE_PLACEHOLDER` markers remain
2. Every parameter ID has a matching editor control
3. The parameter set is not identical to the archetype baseline

If validation fails, a rewrite pass is triggered (max 2 attempts) before the plugin is considered failed.

### The contract

The `CLAUDE.md` written into the project says: "Use `FoundryLookAndFeel` for all components, do not create your own colors/fonts, respect this API for parameters." This guarantees visual consistency across all generated plugins.

## Claude Code Integration

### Invocation

```bash
claude \
  -p "<generation prompt>" \
  --dangerously-skip-permissions \
  --output-format stream-json \
  --verbose \
  --max-turns 30
```

> Note: The system prompt is delivered via `CLAUDE.md` written into the project's working directory, not via `--system-prompt`. Claude Code reads `CLAUDE.md` automatically when it starts in that directory.

The app communicates with the Claude Code subprocess via its stdout stream (JSON lines, parsed in `ClaudeCodeService.parseLine()`). Tool use events are mapped to UI progress steps.

### CLAUDE.md (project-level) contains

- Plugin archetype and interface direction
- Which files to read and edit
- DSP rules (smoothing, bus config, no external deps)
- UI rules (control types, grouping, colour constraints)
- Preset implementation instructions (if preset count > 0)
- Curated JUCE API patterns (oscillators, filters, parameter layout)

### Build-fix loop

```
ProjectAssembler writes files → /tmp/foundry-build-<uuid>/
          │
          ▼
   Claude Code edits files (--max-turns 30)
          │
          ▼
   GeneratedPluginValidator checks quality
          │ (if fails → rewrite pass, then rebuild)
          ▼
   BuildRunner: cmake --build (max 3 attempts)
          │
     ┌────┴────┐
  Success    Failure
     │         │
     ▼         ▼
  Smoke test   Parse compiler errors,
  (bundle      send back to Claude Code
  existence)   (max 3 retries)
     │
  ┌──┴──┐
Pass   Fail → error screen
  │
  ▼
Install to /Library/Audio/Plug-Ins/
(via AppleScript with admin privileges)
```

> **Known issue #7:** Smoke test currently only checks bundle existence. Planned upgrade: use `auval` to validate the plugin loads and renders audio without NaN/Inf/silence.

### Timeouts and resource limits

- **Generation timeout:** 5 minutes per Claude Code session
- **Build timeout:** 360s per attempt (target: 120s — see issue #10)
- **Fix pass timeout:** 180s
- **Quality rewrite timeout:** 240s
- **Disk cleanup:** Temp build dirs are currently not cleaned up after generation (see issue #9)

### Progress parsing

The app reads Claude Code's stdout stream (JSON lines) and maps tool use events to progress steps:
- `Write`/`Edit` tool on `PluginProcessor.*` → "Generating DSP"
- `Write`/`Edit` tool on `PluginEditor.*` or `FoundryLookAndFeel.h` → "Generating UI"
- Bash tool containing `cmake` → "Compiling"
- Process exit with success → "Installing"

## Dependency Management (First Launch)

On first launch, the app checks:

| Dependency | Check | Install method |
|---|---|---|
| Xcode CLI Tools | `xcode-select -p` | `xcode-select --install` (system prompt) |
| CMake | `which cmake` | `brew install cmake` or embedded binary |
| JUCE SDK | Check `~/Library/Application Support/Foundry/JUCE/` | Download + extract automatically |
| Claude Code CLI | `which claude` | User must install manually (`npm install -g @anthropic-ai/claude-code`) |

## Plugin Library (Home Screen)

Grid of generated plugins. Each card shows:
- Logo image (if generated) or type icon with accent color
- Plugin name
- Installed formats (AU/VST3)
- Creation date
- Actions on click: open folder, refine, regenerate, delete

### Plugin metadata schema (`plugins.json`)

```json
{
  "plugins": [
    {
      "id": "uuid-v4",
      "name": "DrakeVox Synth",
      "type": "instrument",
      "prompt": "Un synthé RnB avec des presets à la Drake",
      "createdAt": "2026-03-12T14:30:00Z",
      "formats": ["AU", "VST3"],
      "installPaths": {
        "au": "/Library/Audio/Plug-Ins/Components/DrakeVoxSynth.component",
        "vst3": "/Library/Audio/Plug-Ins/VST3/DrakeVoxSynth.vst3"
      },
      "iconColor": "#C8C4BC",
      "logoAssetPath": "~/Library/Application Support/Foundry/PluginLogos/<id>/logo.png",
      "status": "installed",
      "buildDirectory": "/tmp/foundry-build-abc12345"
    }
  ]
}
```

## Design Direction

- **Style:** Dark, minimal, clean — inspired by Glaze/Raycast
- **Generated plugins inherit the same visual identity** via `FoundryLookAndFeel`
- Rounded corners, muted accent colors, monospaced typography for parameter labels

## MVP Scope

### In (v1)

- SwiftUI app with full flow: prompt → quick options → generation → result
- Three JUCE archetypes: instrument, effect, utility
- FoundryLookAndFeel (dark, minimal, knobs/sliders/labels)
- Claude Code as subprocess with CLAUDE.md system prompt
- Build loop with 3 retries max + quality validation + rewrite pass
- AU + VST3 installation to `/Library/Audio/Plug-Ins/` (admin required)
- Plugin Library (grid with type icons or generated logos)
- Dependency checker on first launch
- Error screen with retry/modify options
- **Refine flow** — modify existing plugins via follow-up instructions
- **Plugin logo generation** — local Stable Diffusion (Apple CoreML), manual trigger from detail view
- macOS only

### Out (later)

- Integrated audio preview (minimal AU host in-app)
- More templates (drum machine, sampler, multi-effect)
- Export/share plugins between users
- Community gallery (Glaze Store-style)
- Alternative UI themes for plugins
- Prompt analysis to estimate generation time
- Dynamically generated quick options (LLM-powered)

## JUCE Licensing

Foundry uses JUCE under the [JUCE Personal license](https://juce.com/legal/juce-8-licence/) (free for projects with revenue under $50k). Generated plugins are for personal use.

## Known Risks

| Risk | Mitigation |
|---|---|
| Claude Code generates non-compilable C++ | Template provides a compilable skeleton; Claude only fills in DSP/UI. Build-fix loop retries 3 times. |
| Plugin compiles but produces silence/noise | Smoke test (bundle existence today; `auval` planned — issue #7). |
| Claude Code subprocess hangs | 5-minute timeout with process kill. |
| Large JUCE SDK download on first launch | ~200MB. App shows download progress. Cached in Application Support. |
| Claude Code CLI not installed | Only dependency requiring manual install. Clear onboarding instructions. |
| Admin password prompt on install | Required for `/Library` install path. No silent alternative for system-wide DAW visibility. |
| Temp dirs fill `/tmp` | Cleanup not yet implemented — issue #9. |

## Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| App framework | SwiftUI | Native macOS integration, filesystem access |
| AI backend | Claude Code CLI (subprocess) | Simple, leverages existing agent intelligence |
| Plugin framework | JUCE | Industry standard for AU/VST3 |
| Build system | CMake | JUCE's recommended build approach |
| Template delivery | Programmatic (Swift) | No bundle maintenance, versionable, easy to update |
| System prompt delivery | CLAUDE.md in project dir | Self-documenting, inspectable post-generation |
| Install target | `/Library/Audio/Plug-Ins/` | System-wide DAW visibility; requires admin |
| Iteration model | One-shot + Refine flow | Simpler UX for initial generation; targeted edits via Refine |
| Plugin UI | Styled via FoundryLookAndFeel | Consistent visual identity across all generated plugins |

## Changelog

| Date | Change |
|---|---|
| 2026-03-15 | Added plugin logo generation spec (`2026-03-15-plugin-logo-regeneration-design.md`) |
| 2026-03-18 | Synced spec with implementation: programmatic templates, CLI invocation, install path, Refine flow, utility type, `buildDirectory` field, quality validator, known issues |
