# Foundry

**Generate audio plugins from a sentence.**

Foundry is a desktop app for macOS and Windows that turns a natural language description into a real, installable plugin — compiled locally, no code required.

> "A warm tape saturation with drive and tone controls"  
> "A polyphonic pad synth with lush reverb and 5 presets"  
> "A stereo utility with input gain, width, and a VU meter"

Foundry writes the C++, builds it with JUCE, and installs it directly into your DAW.

---

## How it works

1. **Describe** your plugin in plain language
2. **Generate** the platform-supported plugin format automatically (AU/VST3 on macOS, VST3 on Windows)
3. **Wait** ~2–5 minutes while Foundry generates and compiles
4. **Open** the plugin in any compatible DAW

Under the hood: Claude Code CLI writes the JUCE C++ code, CMake builds it, and Foundry installs it to the correct platform plugin directory.

---

## Requirements

| Dependency | How to install |
|---|---|
| macOS 13+ | Xcode Command Line Tools, CMake, Claude Code CLI, managed JUCE install |
| Windows 11+ | Visual Studio 2022 Build Tools (Desktop C++), CMake, Claude Code CLI, managed JUCE install |
| Optional | Codex CLI (`npm install -g @openai/codex`) |

---

## Features

- **Three plugin archetypes** — instrument, effect, utility — Claude writes each from scratch using expert JUCE knowledge
- **Refine** — modify an existing generated plugin with a follow-up instruction without starting from scratch
- **Plugin logo generation** — generate a custom logo image for any plugin using local Stable Diffusion
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
