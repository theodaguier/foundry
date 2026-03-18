# Foundry

**Generate audio plugins from a sentence.**

Foundry is a macOS app that turns a natural language description into a real, installable AU/VST3 plugin — compiled locally, no code required.

> "A warm tape saturation with drive and tone controls"  
> "A polyphonic pad synth with lush reverb and 5 presets"  
> "A stereo utility with input gain, width, and a VU meter"

Foundry writes the C++, builds it with JUCE, and installs it directly into your DAW.

---

## How it works

1. **Describe** your plugin in plain language
2. **Choose** format (AU / VST3 / both), stereo or mono, number of presets
3. **Wait** ~2–5 minutes while Foundry generates and compiles
4. **Open** the plugin in any AU/VST3-compatible DAW

Under the hood: Claude Code CLI writes the JUCE C++ code, CMake builds it, and Foundry installs it to `/Library/Audio/Plug-Ins/`.

---

## Requirements

| Dependency | How to install |
|---|---|
| macOS 13+ (Apple Silicon recommended) | — |
| Xcode Command Line Tools | `xcode-select --install` |
| CMake | `brew install cmake` |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` |
| JUCE SDK | Downloaded automatically on first launch |

---

## Features

- **Three plugin archetypes** — instrument, effect, utility — Claude writes each from scratch using expert JUCE knowledge
- **Refine** — modify an existing generated plugin with a follow-up instruction without starting from scratch
- **Plugin logo generation** — generate a custom logo image for any plugin using local Stable Diffusion (Apple CoreML, no cloud)
- **Plugin Library** — browse, manage, and re-open all generated plugins
- **FoundryLookAndFeel** — consistent dark minimal design system across every generated plugin UI

---

## Project structure

```
Foundry/
├── App/                  # App entry point, ContentView
├── Components/           # Reusable UI components (PluginCard, StepListView…)
├── Models/               # Plugin, AppState
├── Services/             # Pipeline, ClaudeCodeService, BuildRunner, ProjectAssembler…
└── Views/                # All screens (PromptView, GenerationProgressView, PluginDetailView…)
```

See [`CLAUDE.md`](./CLAUDE.md) for architecture details, data model, and development notes.

---

## Status

Active development. Core pipeline is functional. Known issues and planned improvements are tracked in [GitHub Issues](https://github.com/theodaguier/foundry/issues).

---

## License

JUCE is used under the [JUCE Personal License](https://juce.com/legal/juce-8-licence/) (free for projects under $50k revenue). Generated plugins are for personal use.
