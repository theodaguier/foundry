# Foundry

**Generate audio plugins from a sentence.**

Foundry is a macOS desktop app that turns a natural language description into a real, installable AU/VST3 plugin — compiled locally, no code required.

> "A warm tape saturation with drive and tone controls"
> "A polyphonic pad synth with lush reverb and 5 presets"
> "A stereo utility with input gain, width, and a VU meter"

Foundry dispatches an AI coding agent (Claude Code CLI or Codex CLI) to write the JUCE C++, builds it with CMake, and installs it directly into your DAW.

> Currently in **private beta** on macOS. [Request access →](https://foundry.so)

---

## How it works

1. **Describe** your plugin in plain language
2. **Generate** — Foundry runs two agent passes (DSP, then UI) and compiles
3. **Wait** a few minutes while the build loop runs
4. **Open** the plugin in any AU or VST3-compatible DAW

---

## Requirements

| Dependency | Notes |
|---|---|
| macOS 13+ | Apple Silicon or Intel |
| Xcode Command Line Tools | `xcode-select --install` |
| CMake | `brew install cmake` |
| Claude Code CLI | Required — `npm install -g @anthropic-ai/claude-code` |
| Codex CLI | Optional — `npm install -g @openai/codex` |

JUCE 8 is downloaded and managed automatically on first run.

---

## Features

- **Three plugin archetypes** — instrument, effect, utility
- **Refine** — iterate on a generated plugin with a follow-up instruction
- **Plugin versioning** — every generate/refine creates a new archived version you can roll back to
- **Plugin Library** — browse, manage, rename, and reinstall generated plugins
- **Multi-agent support** — Claude Code CLI (default) or Codex CLI
- **FoundryLookAndFeel** — consistent dark minimal design applied to every generated plugin UI

---

## Tech stack

| Layer | Technology |
|---|---|
| Desktop shell | Tauri 2 (Rust) |
| Frontend | React 19 + TypeScript + Vite |
| Styling | Tailwind CSS v4 + shadcn/ui |
| Auth & telemetry | Supabase |
| AI agents | Claude Code CLI / Codex CLI |
| Build system | CMake + JUCE 8 |

---

## Project structure

```
foundry/
├── src/                    # React/TypeScript frontend
│   ├── components/
│   │   ├── app/            # Domain components
│   │   └── ui/             # shadcn/ui primitives
│   ├── pages/              # Route-level views
│   ├── stores/             # Zustand stores
│   └── hooks/ lib/ styles/
├── src-tauri/              # Rust backend
│   └── src/
│       ├── commands/       # Tauri IPC handlers
│       ├── models/         # Shared data types
│       ├── services/       # Core business logic
│       └── platform/       # Platform abstraction
└── landing/                # Astro landing page (foundry.so)
```

See [`CLAUDE.md`](./CLAUDE.md) for full architecture, data model, and pipeline details.

---

## Development setup

### Prerequisites

| Tool | Version | Install |
|---|---|---|
| Node.js | 22+ | [nodejs.org](https://nodejs.org) |
| Rust | stable | [rustup.rs](https://rustup.rs) |
| Xcode CLT (macOS) | latest | `xcode-select --install` |
| Visual Studio Build Tools (Windows) | 2022+ | `winget install Microsoft.VisualStudio.2022.BuildTools` |
| CMake | 3.25+ | `brew install cmake` (macOS) / `winget install Kitware.CMake` (Windows) |

### Clone and install

```bash
git clone https://github.com/theodaguier/foundry.git
cd foundry
npm install
```

### Environment variables

Create a `.env` file at the root (optional, for Supabase auth and analytics):

```env
VITE_PUBLIC_POSTHOG_PROJECT_TOKEN=   # PostHog analytics (optional)
VITE_PUBLIC_POSTHOG_HOST=            # PostHog host (optional)
```

Supabase credentials are compiled into the Rust binary via constants in `src-tauri/src/services/auth_service.rs`.

### Run in development

```bash
npm run tauri dev
```

This starts the Vite dev server and the Tauri Rust backend. Hot-reload is active for the frontend; Rust changes trigger a recompile.

### Build for production

```bash
npm run tauri build
```

Outputs a signed `.dmg` (macOS) or `.exe` installer (Windows) in `src-tauri/target/release/bundle/`.

### Useful scripts

| Command | Description |
|---|---|
| `npm run dev` | Start Vite dev server only |
| `npm run build` | TypeScript check + Vite build |
| `npm run typecheck` | Run `tsc --noEmit` |
| `npm test` | Run Vitest test suite |
| `npm run tauri dev` | Full desktop app in dev mode |
| `npm run tauri build` | Production desktop build |

### Runtime dependencies

These are needed to **use** the app (checked during onboarding):

| Dependency | Required | Notes |
|---|---|---|
| Xcode CLT (macOS) / VS Build Tools (Windows) | Yes | C++ compiler |
| CMake | Yes | Build system |
| Claude Code CLI | Yes | `npm install -g @anthropic-ai/claude-code` — requires an Anthropic API key |
| Codex CLI | No | `npm install -g @openai/codex` — optional alternative agent |
| JUCE 8 | Yes | Auto-downloaded on first run to `~/Library/Application Support/Foundry/JUCE/` |

---

## Releases

macOS builds are published as signed `.dmg` files on the [Releases](https://github.com/theodaguier/foundry/releases) page. After the first manual install, Foundry checks for updates in-app via the Tauri updater.

See [`docs/desktop-releases.md`](./docs/desktop-releases.md) for the CI flow, required secrets, and release checklist.

---

## License

JUCE is used under the [JUCE Personal License](https://juce.com/legal/juce-8-licence/) (free for projects under $50k revenue). Generated plugins are for personal use.
