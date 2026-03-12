# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Foundry is a macOS app (SwiftUI) that lets users create custom audio plugins (AU/VST3) by describing them in natural language. It generates real, compilable JUCE plugins locally using Claude Code CLI as an autonomous subprocess. No coding required from the end user.

**Status:** Pre-implementation — design spec finalized, no source code yet.

## Architecture

Five modules inside a SwiftUI app:

1. **Prompt View** — Text input + hardcoded quick options (format, stereo/mono, preset count)
2. **Project Assembler** — Copies JUCE template to `/tmp/foundry-build-xxxx/`, injects context
3. **Claude Code CLI** — Subprocess (`claude --dangerously-skip-permissions`) running in agentic mode, edits C++/JUCE files
4. **Build Runner** — CMake + Xcode build with error parsing, 3 retries, smoke test (1s audio render checking for silence/NaN/Inf)
5. **Plugin Library** — Grid view of generated plugins with metadata stored in `plugins.json`

Flow: Prompt → Quick Options → Generation Progress → Result/Error → Plugin Library (home)

## Tech Stack

- **App:** Swift / SwiftUI (macOS only)
- **Plugins:** C++ / JUCE framework
- **Build:** CMake → Xcode
- **AI:** Claude Code CLI as subprocess (non-interactive, stdout stream parsing)
- **Plugin formats:** AU + VST3, installed to `~/Library/Audio/Plug-Ins/`

## Key Design Decisions

- **Hybrid generation:** JUCE templates provide compilable skeletons (CMakeLists.txt, FoundryLookAndFeel, preset manager); Claude generates DSP logic, UI layout, presets, and parameters
- **One-shot model:** No conversational iteration — "Regenerate" relaunches same prompt with variation
- **FoundryLookAndFeel:** Shared design system (dark, minimal, Glaze-inspired) enforced via system prompt contract — all generated plugins must use it
- **Build-fix loop:** Max 3 build retries + 1 smoke test retry. On failure after retries, show error screen
- **Timeouts:** 5 min generation, 2 min per build attempt
- **Dependencies:** Xcode CLI Tools, CMake (brew), JUCE SDK (~200MB cached in `~/Library/Application Support/Foundry/JUCE/`), Claude Code CLI (manual npm install)

## Template Structure (planned, embedded in app bundle)

```
Resources/templates/
├── base/           # Shared: CMakeLists.txt, FoundryLookAndFeel.h, FoundryPresetManager.h
├── synth/          # PluginProcessor.h/cpp, PluginEditor.h/cpp
└── effect/         # PluginProcessor.h/cpp, PluginEditor.h/cpp
```

## Design Spec

Full specification at `docs/superpowers/specs/2026-03-12-foundry-design.md` — covers architecture, user flow, template system, Claude Code integration, dependency management, plugin metadata schema, MVP scope, and known risks. **Read this before implementing any feature.**
