# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

Foundry is a macOS desktop app (Tauri 2 + React/TypeScript) that generates real, compilable AU/VST3 audio plugins from a natural language description. It dispatches to an AI coding agent (Claude Code CLI or Codex CLI) as a subprocess to write C++/JUCE code, then builds and installs the plugin locally.

**Status:** Active development. Core pipeline, refine flow, plugin versioning, telemetry, and Supabase auth are implemented and working.

## Tech Stack

| Layer            | Technology                                            |
| ---------------- | ----------------------------------------------------- |
| Desktop shell    | Tauri 2 (Rust)                                        |
| Frontend         | React 19 + TypeScript + Vite                          |
| Styling          | Tailwind CSS v4 + shadcn/ui                           |
| State management | Zustand                                               |
| Routing          | react-router-dom v7                                   |
| Backend (Rust)   | Tokio async, Serde, Reqwest                           |
| Auth & telemetry | Supabase (REST + Auth v2)                             |
| AI agents        | Claude Code CLI (`claude`) and/or Codex CLI (`codex`) |
| Build system     | CMake + JUCE 8.0.12 (auto-managed)                    |

## Repository Layout

```
accra/
├── src/                        # React/TypeScript frontend
│   ├── App.tsx
│   ├── main.tsx
│   ├── components/
│   │   ├── app/                # Domain components
│   │   │   ├── sidebar.tsx
│   │   │   ├── sidebar-plugin-row.tsx
│   │   │   ├── plugin-detail-view.tsx
│   │   │   ├── plugin-artwork-view.tsx
│   │   │   ├── version-history-view.tsx
│   │   │   ├── filter-tab-bar.tsx
│   │   │   └── foundry-logo.tsx
│   │   └── ui/                 # shadcn/ui primitives
│   ├── pages/                  # Route-level views
│   │   ├── Prompt.tsx
│   │   ├── Refine.tsx
│   │   ├── Settings.tsx
│   │   ├── Error.tsx
│   │   ├── generation-progress.tsx
│   │   ├── build-queue.tsx
│   │   ├── onboarding.tsx
│   │   ├── profile.tsx
│   │   └── auth/
│   ├── stores/                 # Zustand stores
│   │   ├── app-store.ts
│   │   ├── build-store.ts
│   │   └── settings-store.ts
│   ├── hooks/
│   ├── lib/
│   └── styles/
└── src-tauri/                  # Rust backend
    ├── src/
    │   ├── lib.rs              # Tauri setup + command registration
    │   ├── main.rs
    │   ├── state.rs            # AppState (plugins mutex, cancel token, SupabaseAuth)
    │   ├── commands/           # Tauri IPC command handlers
    │   │   ├── auth.rs
    │   │   ├── dependencies.rs
    │   │   ├── filesystem.rs
    │   │   ├── generation.rs
    │   │   ├── onboarding.rs
    │   │   ├── plugins.rs
    │   │   ├── settings.rs
    │   │   └── telemetry.rs
    │   ├── models/             # Shared data types
    │   │   ├── agent.rs        # GenerationAgent, AgentModel, AgentProvider
    │   │   ├── config.rs       # GenerationConfig, RefineConfig
    │   │   ├── plugin.rs       # Plugin, PluginVersion, PluginType, PluginFormat
    │   │   └── telemetry.rs    # GenerationTelemetry, TelemetryBuilder, TelemetryRow
    │   ├── services/           # Core business logic
    │   │   ├── agent_service.rs
    │   │   ├── auth_service.rs
    │   │   ├── build_directory_cleaner.rs
    │   │   ├── build_environment.rs
    │   │   ├── build_runner.rs
    │   │   ├── claude_code_service.rs
    │   │   ├── codex_service.rs
    │   │   ├── dependency_checker.rs
    │   │   ├── foundry_paths.rs
    │   │   ├── generation_pipeline.rs
    │   │   ├── model_catalog.rs
    │   │   ├── onboarding.rs
    │   │   ├── plugin_manager.rs
    │   │   ├── project_assembler.rs
    │   │   └── telemetry_service.rs
    │   └── platform/           # Platform abstraction layer
    │       ├── mod.rs          # Public API — services use only this
    │       ├── macos.rs
    │       ├── linux.rs
    │       ├── windows.rs
    │       └── types.rs        # DependencySpec, InstallDir, InstallOperation, BundleMapping
    ├── Cargo.toml
    └── tauri.conf.json
```

## Service Layer Reference

| File                      | Role                                                                          |
| ------------------------- | ----------------------------------------------------------------------------- |
| `generation_pipeline`     | Orchestrates generate and refine flows end-to-end                             |
| `project_assembler`       | Writes `CMakeLists.txt` + `CLAUDE.md` + `AGENTS.md` + `juce-kit/` to temp dir |
| `agent_service`           | Unified dispatcher — routes `run`/`fix` calls to Claude Code or Codex         |
| `claude_code_service`     | Launches Claude CLI subprocess, parses stream-json events                     |
| `codex_service`           | Launches Codex CLI subprocess, parses its event format                        |
| `build_runner`            | Low-level CMake configure + build + smoke test                                |
| `build_environment`       | Checks dependencies, auto-downloads JUCE 8.0.12 if needed                     |
| `build_directory_cleaner` | Sweeps stale `/tmp/foundry-build-*` on launch and after install               |
| `model_catalog`           | Detects installed CLIs, exposes `AgentProvider`/`AgentModel` catalog          |
| `plugin_manager`          | Persists `plugins.json`, handles install/uninstall/rename                     |
| `telemetry_service`       | Saves `GenerationTelemetry` locally + syncs to Supabase                       |
| `auth_service`            | Supabase auth (sign-up, OTP verify, refresh, sign-out, profile CRUD)          |
| `onboarding`              | Reads/writes `onboarding_completed_at` in Supabase profile                    |
| `foundry_paths`           | Canonical `~/Library/Application Support/Foundry/` paths                      |
| `platform`                | Platform abstraction — shell env, CLI resolution, install dirs, codesign      |

## Data Model

```rust
// models/plugin.rs
struct Plugin {
    id: String,
    name: String,
    plugin_type: PluginType,       // instrument | effect | utility
    prompt: String,
    created_at: String,
    formats: Vec<PluginFormat>,    // AU | VST3
    install_paths: InstallPaths,   // { au: Option<String>, vst3: Option<String> }
    icon_color: String,            // hex "#RRGGBB"
    logo_asset_path: Option<String>,
    status: PluginStatus,          // installed | failed | building
    build_directory: Option<String>, // archived build for Refine
    generation_log_path: Option<String>,
    agent: Option<GenerationAgent>,  // Claude Code | Codex
    model: Option<AgentModel>,
    current_version: i32,
    versions: Vec<PluginVersion>,
}

struct PluginVersion {
    id: String,
    plugin_id: String,
    version_number: i32,
    prompt: String,
    created_at: String,
    build_directory: Option<String>,
    install_paths: InstallPaths,
    icon_color: String,
    is_active: bool,
    agent: Option<GenerationAgent>,
    model: Option<AgentModel>,
    telemetry_id: Option<String>,
}
```

## Key Design Decisions

- **Multi-agent architecture:** `agent_service` abstracts over Claude Code CLI and Codex CLI. The generation pipeline is backend-agnostic — it calls `agent_service::run()` and `agent_service::fix()`, which dispatch to the correct CLI. Refine uses the same agent that built the original plugin.
- **Model catalog:** `model_catalog` detects which CLIs are installed at runtime and builds an `AgentProvider` list. Users can override with a `models.json` file in Application Support. No stale cache — detection is always fresh.
- **Split generation (DSP pass + UI pass):** Code generation runs as two separate agent invocations. The DSP pass (`generate_processor` mode) creates `PluginProcessor.h/.cpp`. The UI pass (`generate_ui` mode) creates `PluginEditor.h/.cpp` + `FoundryLookAndFeel.h`. Each pass has a targeted prompt; the UI pass receives the parameter manifest extracted from the processor.
- **Repair passes:** After each generation pass, missing files and structural validation issues trigger a repair pass before proceeding. The pipeline fails fast if repair doesn't resolve the issues.
- **Build loop:** Unlimited retries on `generate`, capped at 3 on `refine`. The build loop calls `agent_service::fix()` with the raw compiler errors after each failed attempt. Only infrastructure failures (CLI not found, etc.) abort without a fix attempt.
- **Plugin versioning:** Each generate/refine creates a new `PluginVersion`. The build dir is archived to `PluginBuilds/<plugin_id>/v<n>/` in Application Support. Refine restores from the archived dir, locks `CMakeLists.txt`, runs the agent, then re-archives.
- **Telemetry:** `TelemetryBuilder` accumulates timing, token usage, build attempt logs, and outcome during the pipeline. On completion, `telemetry_service::save()` writes a local JSON file and fires a background Supabase sync if the user is authenticated.
- **Supabase auth:** Email + OTP (no password). Sessions are persisted to `auth_session.json` in Application Support and refreshed via the Supabase token endpoint.
- **Auto-managed JUCE:** `build_environment` downloads JUCE 8.0.12 from GitHub releases into `~/Library/Application Support/Foundry/JUCE/8.0.12/` if not present. Users can also set an override path. The environment is checked at the start of every generation.
- **Platform abstraction:** All platform-specific code lives in `platform/`. Services never use `#[cfg]` directly. Install paths, bundle extensions, CMake flags, shell environment, CLI resolution, and codesigning are all routed through `platform::*`.
- **Install path:** Default macOS paths are `/Library/Audio/Plug-Ins/Components/` (AU) and `/Library/Audio/Plug-Ins/VST3/` (VST3). Users can override per-format in Settings. `platform::install_plugin_bundles()` handles elevation/copy and `platform::post_install_refresh()` refreshes the Audio Unit cache.
- **Knowledge kit:** `project_assembler` writes `CLAUDE.md` (for Claude Code), `AGENTS.md` (for Codex), and `juce-kit/*.md` reference files to the temp build dir. No C++ stubs — the agent writes all source files from scratch.
- **Creative profile:** `infer_creative_profile()` derives a deterministic `CreativeProfile` (signature interaction, control strategy, UI direction, sonic hook) from the plugin name + prompt using a stable hash. Used to vary generation without random noise.
- **Event-driven pipeline:** The frontend listens to Tauri events emitted during the pipeline (`pipeline:step`, `pipeline:log`, `pipeline:name`, `pipeline:build_attempt`, `pipeline:complete`, `pipeline:error`). No polling.

## Generation Pipeline (in order)

```
run_generation(GenerationConfig)
  └─ execute_generation()
       1. build_environment::prepare_build_environment()  → check/install deps + JUCE
       2. generate_local_plugin_name()                    → deterministic name from prompt
       3. project_assembler::assemble()                   → write temp dir with CMake + CLAUDE.md + AGENTS.md + juce-kit/
       4. agent_service::run(..., "generate_processor")   → DSP pass: PluginProcessor.h/.cpp
          └─ repair pass if processor files missing
       5. extract_parameter_manifest()                    → read APVTS parameter IDs from processor
       6. agent_service::run(..., "generate_ui")          → UI pass: PluginEditor.h/.cpp + FoundryLookAndFeel.h
          └─ emergency UI prompt if stalled
          └─ repair pass if UI files missing or validation fails
       7. run_build_loop(max_attempts=None)               → cmake configure + build, unlimited retries with fix passes
       8. install_plugin()                                → copy bundles to plugin dirs + post-install refresh
       9. archive_build()                                 → copy to PluginBuilds/<id>/v1/
      10. plugin_manager::save_plugins()                  → persist to plugins.json
      11. (10s delay) remove temp build dir
```

```
run_refine(RefineConfig)
  └─ execute_refine()
       1. Restore archived build dir (already on disk at plugin.build_directory)
       2. Backup Source/ → Source.backup/
       3. Lock CMakeLists.txt (set read-only)
       4. agent_service::run(..., "refine")              → single targeted modification pass
       5. Unlock CMakeLists.txt
       6. Invalidate stale CMake cache if project dir changed
       7. run_build_loop_with_skip(max_attempts=3)       → cmake build, skip configure on retries
       8. install_plugin()                               → replace installed bundles
       9. archive_build()                                → copy to PluginBuilds/<id>/v<n>/
      10. Create new PluginVersion, mark previous versions inactive
      11. plugin_manager::save_plugins()
      12. Clean Source.backup/
```

## Tauri IPC Commands

All frontend–backend communication goes through Tauri `invoke()` calls. Registered commands:

| Module         | Commands                                                                                                                                         |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `auth`         | `check_session`, `send_otp`, `verify_otp`, `sign_up`, `sign_out`, `get_profile`, `update_card_variant`, `assign_card_variant_batch`              |
| `plugins`      | `load_plugins`, `delete_plugin`, `rename_plugin`, `install_version`, `clear_build_cache`                                                         |
| `generation`   | `start_generation`, `start_refine`, `cancel_build`                                                                                               |
| `dependencies` | `check_dependencies`, `get_build_environment`, `prepare_build_environment`, `set_juce_override_path`, `clear_juce_override_path`, `install_juce` |
| `settings`     | `get_model_catalog`, `refresh_model_catalog`, `get_install_paths`, `set_install_path`, `reset_install_path`                                      |
| `telemetry`    | `load_telemetry`, `load_all_telemetry`                                                                                                           |
| `filesystem`   | `show_in_finder`                                                                                                                                 |
| `onboarding`   | `get_onboarding_state`, `complete_onboarding`, `install_dependency`                                                                              |

## Tauri Events (backend → frontend)

| Event                    | Payload                          | When                                                  |
| ------------------------ | -------------------------------- | ----------------------------------------------------- |
| `pipeline:step`          | `{ step: string }`               | Pipeline stage changes                                |
| `pipeline:log`           | `{ timestamp, message, style? }` | Log line (style: `active`, `success`, `error`, `nil`) |
| `pipeline:name`          | `{ name: string }`               | Plugin name resolved                                  |
| `pipeline:build_attempt` | `{ attempt: number }`            | Build loop iteration starts                           |
| `pipeline:complete`      | `{ plugin: Plugin }`             | Pipeline finished successfully                        |
| `pipeline:error`         | `{ message: string }`            | Pipeline failed                                       |

## Pipeline Steps (sent via `pipeline:step`)

`preparingEnvironment` → `preparingProject` → `generatingDSP` → `generatingUI` → `compiling` → `installing`

## Storage Layout

```
~/Library/Application Support/Foundry/
├── plugins.json                     # Plugin library
├── auth_session.json                # Persisted Supabase session
├── environment.json                 # Build environment config (JUCE paths, install overrides)
├── models.json                      # Optional user override for model catalog
├── JUCE/
│   └── 8.0.12/                      # Auto-downloaded JUCE SDK
├── PluginBuilds/
│   └── <plugin-id>/
│       ├── v1/                      # Archived build dir (Source/ + CMakeLists.txt + juce-kit/)
│       └── v2/                      # After first refine
├── Telemetry/
│   └── <telemetry-id>.json          # One file per generation/refine run
└── tmp/                             # Temp downloads (JUCE zip, etc.)

/tmp/foundry-build-<uuid>/           # Active temp build dir (cleaned 10s after install)
├── CMakeLists.txt
├── CLAUDE.md                        # Mission brief for Claude Code
├── AGENTS.md                        # Mission brief for Codex
├── juce-kit/
│   ├── juce-api.md
│   ├── dsp-patterns.md
│   ├── ui-patterns.md
│   ├── look-and-feel.md
│   ├── build-rules.md
│   └── presets.md
└── Source/                          # Created by agent from scratch
    ├── PluginProcessor.h
    ├── PluginProcessor.cpp
    ├── PluginEditor.h
    ├── PluginEditor.cpp
    └── FoundryLookAndFeel.h
```

## Plugin Types

| Type         | Detection keywords                                      |
| ------------ | ------------------------------------------------------- |
| `instrument` | synth, keys, pad, oscillator, sampler, piano            |
| `utility`    | analyzer, meter, width, gain staging, tuner             |
| `effect`     | (default) reverb, delay, distortion, filter, compressor |

## Agent Invocation Details

**Claude Code CLI:**

```
claude -p "<prompt>"
  --dangerously-skip-permissions
  --output-format stream-json
  --verbose
  --max-turns <mode-dependent>
  --model <model-flag>
  --append-system-prompt "..."
```

**Codex CLI:**

```
codex exec "<prompt>"
  --model <model-flag>
  --approval-policy full-auto
  --quiet
  (working dir set to project dir)
```

Both CLIs are routed through `agent_service`, which calls the correct backend based on the `agent` identifier string.

## Timeouts

| Step                  | Timeout                 | Type                                                |
| --------------------- | ----------------------- | --------------------------------------------------- |
| All agent invocations | 900s (15min)            | Watchdog — advances immediately on completion event |
| Idle heartbeat check  | Every 60s               | Kills process if no output for 60s                  |
| CMake configure       | 60s                     | Hard timeout                                        |
| CMake build           | 120s per attempt        | Hard timeout                                        |
| Temp dir cleanup      | 10s delay after install | `tokio::time::sleep`                                |

## Build Environment

`build_environment::prepare_build_environment()` is called at the start of every generation:

1. Checks required platform dependencies (Xcode CLT, CMake, Claude Code CLI) via `platform::required_dependencies()`
2. Resolves JUCE path — checks user override first, then managed path (`JUCE/8.0.12/`)
3. If JUCE missing and `auto_repair=true`, downloads JUCE 8.0.12 zip from GitHub releases and extracts it
4. Returns `BuildEnvironmentStatus { state: "ready" | "blocked", issues: [...], juce_path, juce_version }`

Codex CLI is optional — its absence does not block the build environment.

## Supabase Schema (relevant tables)

| Table                  | Key columns                                                        |
| ---------------------- | ------------------------------------------------------------------ |
| `profiles`             | `id` (user_id), `email`, `onboarding_completed_at`, `card_variant` |
| `generation_telemetry` | All `TelemetryRow` fields — one row per generate/refine run        |

## CI/CD — Desktop Release Workflow

The release pipeline is in `.github/workflows/desktop-release.yml`. It builds macOS (Apple Silicon + Intel) and Windows artifacts, signs them, and uploads to the GitHub Release.

### Triggering a release

Releases are managed by **release-please**. On every push to `main`, release-please maintains an auto-updating PR (`chore(main): release X.Y.Z`). Merging that PR:
1. Bumps versions in `tauri.conf.json`, `Cargo.toml`, etc.
2. Creates a GitHub Release + tag (`vX.Y.Z`)
3. Triggers the `Desktop Release` workflow automatically

You can also trigger it manually via `gh workflow run desktop-release.yml --field release_tag=vX.Y.Z`.

### GitHub Actions Secrets required

| Secret | Description |
|--------|-------------|
| `TAURI_SIGNING_PRIVATE_KEY` | Base64-encoded private key output from `tauri signer generate` (the full blob, not the decoded content) |
| `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | Password chosen during `tauri signer generate` (leave empty if no password was set) |
| `APPLE_CERTIFICATE` | Base64-encoded `.p12` Apple Developer certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the `.p12` file |
| `KEYCHAIN_PASSWORD` | Any string — used as the temporary macOS keychain password on the runner |
| `WINDOWS_CERTIFICATE` | Base64-encoded `.pfx` Windows code signing certificate |
| `WINDOWS_CERTIFICATE_PASSWORD` | Password for the `.pfx` file |

macOS and Windows code signing are **optional** — if the certificate import fails, the workflow emits a warning and continues with unsigned artifacts.

### Rotating the updater signing key

1. Run `tauri signer generate` and set a password
2. Update `TAURI_SIGNING_PRIVATE_KEY` in GitHub Secrets with the **Private** base64 blob
3. Update `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` with the password
4. Update `plugins.updater.pubkey` in `src-tauri/tauri.conf.json` with the **Public** base64 blob (the raw base64 output, NOT the decoded `untrusted comment: ...` text)

> ⚠️ Changing the pubkey breaks auto-update for users on the previous key — they will need to manually download the new version.

### Workflow internals

- `scripts/prepare-tauri-signing-key.mjs` — validates and normalizes `RAW_TAURI_SIGNING_PRIVATE_KEY`, writes the base64 key to a temp file, then exports it as `TAURI_SIGNING_PRIVATE_KEY` (the env var Tauri reads during bundling)
- The workflow checks out the **release tag**, not `main` — fixes to CI only take effect starting with the next tag after the fix lands on `main`

## Known Issues / Open Items

- Smoke test only checks bundle existence (`.component`/`.vst3`), not audio validity
- Codex CLI support is new — stream parsing covers the main event types but edge cases may exist
- `PluginBundleInspector` is not yet a separate service; bundle location logic lives in `build_runner::locate_bundle`
- Logo generation (`PluginLogoService`) was removed; `logo_asset_path` is always `None`
- Windows and Linux platform implementations exist but are untested end-to-end
