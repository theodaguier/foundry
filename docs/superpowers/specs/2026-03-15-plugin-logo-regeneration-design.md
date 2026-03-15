# Foundry — Plugin Logo Regeneration Design

## Goal

Add a manual `Recreate Logo` action to the plugin detail dialog so users can generate a new logo image for an already-installed plugin without rerunning the plugin generation pipeline.

This is a Foundry-only asset flow:
- it does not modify AU/VST3 bundles
- it does not run automatically during plugin generation
- it only runs when the user explicitly requests a new logo from the detail dialog

## Context

The current Plugin Library shows a type-based SF Symbol with an accent color. That is reliable and cheap, but it does not let users create a logo-like visual identity for an existing plugin.

A local spike validated the technical path for image generation on Apple Silicon:
- engine: Apple's `StableDiffusion` Swift package
- model: `apple/coreml-stable-diffusion-2-1-base-palettized`
- working config: `cpuAndGPU`, `20` steps, `512x512`, `reduceMemory = true`
- observed on M1 Pro 16 GB: about `65s` wall time, about `3.6 GB` peak memory

Those numbers make this feature acceptable as a manual action, but not as a mandatory step in the main plugin generation pipeline.

## Non-Goals

- No automatic logo generation during plugin creation
- No multi-variant gallery or logo selection flow
- No prompt editing UI for v1
- No embedding of generated assets into AU/VST3 bundles
- No icon export to `.icns` or host-visible plugin branding changes
- No attempt to solve screenshot capture or library thumbnails beyond this plugin logo asset

## User Flow

The feature is exposed only from the plugin detail dialog.

1. User opens a plugin from the library.
2. User clicks `Recreate Logo`.
3. Foundry checks whether the image model resources are already installed.
4. If the model is missing, Foundry downloads and prepares it.
5. Foundry generates one logo image from the plugin's existing metadata.
6. On success, Foundry replaces the plugin's current visual in the detail dialog and library cards.
7. On failure or cancellation, Foundry keeps the current visual unchanged.

This flow remains independent from plugin code generation, build, install, and refine flows.

## UX States

The detail dialog gets a new action button: `Recreate Logo`.

The action launches a focused modal task flow with these states:

### Idle

- Existing plugin visual is shown
- `Recreate Logo` button is enabled

### Preparing

- Label: `Preparing logo generation`
- If model download is required, show deterministic progress text such as `Downloading image model…`
- Cancel is available

### Generating

- Label: `Generating logo…`
- Spinner/progress affordance is shown
- Cancel is available
- The detail dialog should not silently continue without visible feedback

### Success

- Dismiss progress UI
- Replace the plugin visual immediately
- Optionally show a small success confirmation such as `Logo updated`

### Failure

- Dismiss progress UI
- Show an error alert with a short actionable message
- Keep the previous visual unchanged

## Data Model Changes

`Plugin` gains one optional persisted field:

```swift
var logoAssetPath: String?
```

Rules:
- `nil` means Foundry should continue rendering the current type icon + accent color fallback
- a non-`nil` path points to a generated PNG managed by Foundry
- if the file is missing on disk, Foundry treats it as absent and falls back to the current icon treatment

The existing `iconColor` field remains in place as the default fallback visual.

## Storage Layout

Generated logos are stored in Application Support, not in plugin bundles:

```text
~/Library/Application Support/Foundry/
├── plugins.json
├── PluginLogos/
│   └── <plugin-id>/
│       └── logo.png
└── ImageModels/
    └── coreml-stable-diffusion-2-1-base-palettized/
        └── original_compiled/
```

Storage rules:
- write the logo atomically to a temporary file, then replace `logo.png`
- only update `plugins.json` after the image has been written successfully
- deleting a plugin should remove its corresponding `PluginLogos/<plugin-id>/` directory
- if a logo is regenerated, the new file replaces the previous `logo.png`

## Architecture

The implementation should introduce a dedicated service instead of pushing image concerns into `PluginManager` or `PluginDetailView`.

### `PluginLogoService`

Responsibilities:
- validate/download image model resources
- build the prompt from plugin metadata
- run Stable Diffusion locally
- write the generated PNG atomically
- return an updated `Plugin` with `logoAssetPath` set

Public surface:
- `prepareModelIfNeeded()`
- `generateLogo(for plugin: Plugin) async throws -> Plugin`
- `cancelCurrentGeneration()`

### `PluginLogoModelStore`

Responsibilities:
- own the model install path
- know whether the model is already available
- download the selected model archive
- unpack and validate required resources

This can start as a helper owned by `PluginLogoService` if a separate type feels premature, but the responsibilities should stay isolated from UI.

### `PluginManager`

Responsibilities remain unchanged except for:
- persisting the new `logoAssetPath`
- removing logo assets when a plugin is deleted

`PluginManager` should not know how generation works.

### `PluginDetailView`

Responsibilities:
- expose the `Recreate Logo` action
- host the view-local state machine for preparing/generating/error presentation
- call `PluginLogoService`
- update `AppState.plugins` via `PluginManager.update`

State synchronization requirement:
- the detail surface must not be backed only by a copied `Plugin` value
- it should resolve the current plugin from shared app state by `id`, or receive a binding-equivalent source of truth
- otherwise a successful regeneration may persist correctly while the open detail dialog still shows stale pre-generation data

## Rendering in the Library and Detail Views

Both plugin cards and the detail dialog should follow the same rendering order:

1. If `logoAssetPath` exists and resolves to a readable PNG, render that image.
2. Otherwise render the existing type icon + accent color fallback.

This prevents partial adoption where one screen shows the logo but another still shows the SF Symbol fallback.

## Model Choice

V1 uses Apple's local Stable Diffusion stack:
- package: `apple/ml-stable-diffusion` Swift package
- model: `apple/coreml-stable-diffusion-2-1-base-palettized`
- resource variant: compiled `original`
- runtime configuration: `cpuAndGPU`
- `reduceMemory = true`
- output size: `512x512`
- step count: `20`
- scheduler: equivalent to the validated spike path

Rationale:
- validated locally on the target platform
- integrates natively with Swift
- lighter and more realistic for a desktop app than FLUX/Qwen-class models
- still produces actual logo-like images rather than deterministic vectors

The feature should not attempt Neural Engine deployment in v1 because the validated spike did not produce a reliable result on the current M1 Pro machine with the chosen model variant.

## Prompt Construction

Users do not type a separate logo prompt in v1. Foundry constructs it automatically from existing plugin metadata.

Input fields:
- `plugin.name`
- `plugin.type`
- `plugin.prompt`

Positive prompt template:

```text
premium app icon logo for an audio plugin named <name>, abstract centered brand mark, single dominant symbol, clean geometric composition, high contrast, dark refined background, minimal, polished, iconic, <type-style-language>, inspired by: <plugin.prompt>, no text, no letters
```

Type-specific style language:
- instrument: brighter, more expressive, more energetic
- effect: more transformative, more textured, more tension
- utility: more precise, more technical, more restrained

Negative prompt template:

```text
text, letters, words, typography, photo, photorealistic, human, face, clutter, multiple subjects, complex scene, watermark, blurry, low contrast, UI screenshot, realistic object scene
```

The prompt builder should be deterministic so repeated runs differ because of the sampling seed, not because prompt assembly is unstable.

## Seed Strategy

V1 should use a stable base seed derived from the plugin identity and mix in a small random component per regeneration request.

Rationale:
- preserves some visual relationship to the plugin across retries
- still allows the user to request a fresh result
- avoids fully chaotic outputs

If this proves unnecessary, the implementation may simplify to a random seed per run, but the prompt must remain deterministic.

## Error Handling and Timeouts

Hard requirements:
- generation timeout: `90s`
- download timeout: explicit failure if networking stalls or the archive cannot be unpacked
- cancellation must stop the active task and leave the plugin unchanged
- failed generation must not overwrite the previous `logoAssetPath`

User-facing error categories:
- model download failed
- model resources invalid or incomplete
- generation timed out
- generation failed
- output image could not be written

Error copy should be short and operational, for example:
- `Couldn't download the image model. Check your connection and try again.`
- `Logo generation timed out.`
- `Couldn't save the generated logo.`

## Validation Rules

V1 keeps validation simple and reliable:
- generated file must exist
- generated file must be readable as an image
- generated image dimensions must match the requested size

If any validation fails, treat the run as failed and keep the previous visual.

V1 does not include OCR or semantic image-quality scoring. Those checks can be added later if text artifacts become a major issue in real use.

## Dependency and Setup Considerations

This feature introduces a new optional dependency domain distinct from the existing JUCE/CMake/Codex requirements.

Rules:
- the app should not require the image model to be installed on first launch
- the model is downloaded only when the user first triggers `Recreate Logo`
- failure to install the image model must not block the rest of Foundry

This keeps the base app lightweight and preserves the current setup flow for users who never use logo generation.

## Testing Strategy

### Unit-level

- prompt builder maps plugin metadata into stable positive/negative prompts
- storage paths resolve correctly for plugin IDs
- `PluginManager` preserves and reloads `logoAssetPath`
- missing logo file falls back cleanly

### Integration-level

- first run without model downloads resources and then generates a logo
- second run reuses cached model resources without downloading again
- successful generation updates both in-memory state and `plugins.json`
- deleting a plugin removes the persisted logo asset directory
- cancellation leaves plugin metadata untouched

### Manual QA

- regenerate logo from detail dialog for instrument, effect, and utility plugins
- close and relaunch the app to verify persisted logo rendering
- simulate network failure during first-time model install
- simulate disk write failure or insufficient disk space
- verify fallback rendering when `logo.png` is manually deleted

## Rollout

V1 ships as a manual per-plugin action only.

Future expansions can build on the same service:
- generate multiple logo variants
- allow a user-entered style hint
- batch regenerate for multiple plugins
- generate logos as an optional post-build step after plugin creation

## Open Decisions Resolved in This Spec

- Entry point: plugin detail dialog
- Trigger mode: manual only
- Output count: one logo per run
- Prompt source: automatic from plugin metadata
- Storage: Foundry-managed PNG in Application Support
- Fallback: keep current type icon + accent color
- Integration style: native Swift service using Apple's Stable Diffusion package

## Summary

This design adds a user-invoked, locally generated plugin logo flow without destabilizing Foundry's main plugin pipeline.

The feature is intentionally constrained:
- manual only
- one image
- automatic prompt construction
- Foundry-local asset storage
- strict fallback behavior on any failure

That keeps the implementation aligned with the validated local spike while leaving room for richer branding workflows later.
