# Design System Strategy: The Synthetic Instrument

## 1. Overview & Creative North Star
The Creative North Star for this system is **"The Technical Monolith."**

Moving away from the friendly, rounded "SaaS" aesthetic, this system treats the macOS interface as a piece of high-end studio rack gear. It is an intentional rejection of softness in favor of brutalist precision and engineering-grade clarity. The experience should feel less like a "web app" and more like a high-performance firmware interface.

The design breaks the standard template through **Rigid Asymmetry** and **Information Density**. By utilizing a hyper-dense dot grid and varying the width of functional columns, we create a layout that feels custom-machined for the specific task of audio synthesis.

## 2. Colors & Surface Logic
The palette is strictly monochrome, relying on the interplay between total darkness and clinical light to define hierarchy.

All colors are defined as `Color` extensions or static constants using `Color(.sRGB, red:green:blue:)`.

### The "No-Line" Rule
While the visual language permits 1pt borders (via `.overlay(Rectangle().stroke(..., lineWidth: 1))`), sectioning must primarily be achieved through **Background Shift**. To create a "carved" look, avoid using borders to separate main modules. Instead, use `Color(hex: 0x0E0E0E)` for the primary workspace and `Color(hex: 0x1F1F1F)` for sidebars. This creates a physical sense of "recessing" and "protruding" parts of the machine.

### Surface Hierarchy & Nesting
Treat the UI as a machined aluminum block. Apply with `.background(SurfaceColor)`.
- **Base Layer:** `Color(hex: 0x131313)` — the app window background
- **Primary Modules:** `Color(hex: 0x1B1B1B)` — main content containers
- **Nested Controls:** `Color(hex: 0x2A2A2A)` — controls inside modules
Each level of nesting should step up or down exactly one tier in the surface scale. This "Mechanical Depth" replaces the need for `.shadow()`.

### The "Glass & Gradient" Rule (Bespoke Implementation)
To maintain the "Teenage Engineering" spirit while adhering to the "No Glow" constraint, we use **Functional Translucency** instead of decorative `.ultraThinMaterial`. Floating panels (like HUDs or plugin overlays) should use the surface color at `.opacity(0.85)` combined with `.blur(radius: 20)` on the background layer. This ensures the "monochrome" stays pure while allowing the underlying technical data to peek through.

### Signature Textures
Apply a subtle dot-grid pattern using a `Canvas` view drawing 1pt circles in `Color(hex: 0x474747).opacity(0.15)` across the background. This serves as a "measurement floor," making the empty space feel intentional and engineered rather than vacant.

## 3. Typography
The typographic soul of this system is **High-Density Utility.** We favor smaller sizes and tighter `.tracking()` to mimic the labeling found on hardware synthesizers.

- **Display & Headlines:** `.custom("Space Grotesk", size:)`. These are your "Brand Marks." They should be used sparingly, often with `.textCase(.uppercase)` and `.tracking(-0.02 * fontSize)` to feel like stamped metal.
- **UI Labels & Controls:** `.custom("Inter", size:)`. This is the "User Interface." Set to `11pt` for most toggle and knob labels to maximize screen real estate.
- **Data & Readouts:** `.system(size:weight:design: .monospaced)` for all frequency values, dB levels, and AI seed strings. Pair with `.monospacedDigit()` so numbers don't "jump" during real-time audio modulation.

## 4. Elevation & Depth
In this system, elevation is a product of **Tonal Layering**, not light sources.

- **The Layering Principle:** To "lift" an element, step from `Color(hex: 0x1F1F1F)` to `Color(hex: 0x444444)` via `.background()`. The contrast change provides the signal of importance.
- **Ambient Shadows:** Standard `.shadow()` is prohibited. However, for floating modals, use a "Hard Offset" shadow: `.shadow(color: .black, radius: 0, x: 4, y: 4)`. This mimics the physical overlap of two plates of material.
- **The "Ghost Border":** For internal dividers within a container, use `.overlay(Rectangle().stroke(Color(hex: 0x474747).opacity(0.2), lineWidth: 1))`. It should be barely visible — felt rather than seen.
- **Zero-Radius Mandate:** All containers must use `Rectangle()` or `.clipShape(Rectangle())` — sharp corners everywhere. The only exception is `RoundedRectangle(cornerRadius: 2)` for interactive inputs to provide a microscopic hint of "touchability."

## 5. Components

### Buttons
- **Primary:** `.background(Color.white)` with `.foregroundStyle(Color(hex: 0x1A1C1C))`. Clipped to `Rectangle()`. High contrast is reserved for the "Execute" or "Generate" actions. Style with a custom `ButtonStyle`.
- **Secondary:** `.background(Color.clear)` with `.overlay(Rectangle().stroke(Color(hex: 0x919191), lineWidth: 1))`.
- **Tertiary/Ghost:** Text-only, using `.font(.system(size: 13, weight: .medium))` with `.textCase(.uppercase)`.

### Inputs & Sliders
- **Audio Sliders:** Build as custom `View` with `DragGesture`. A 1pt `Color(hex: 0x919191)` track (`.stroke(lineWidth: 1)`) with a solid `Color.white` 2pt-wide vertical `Rectangle` as the handle. No knobs — only faders.
- **Text Fields:** `Color(hex: 0x353535)` background. When focused, add a bottom-only 1pt `Color.white` border via `.overlay(alignment: .bottom) { Rectangle().frame(height: 1).foregroundStyle(.white) }`.

### Technical Lists
- **The "No Divider" Rule:** No `Divider()` between list items. Use `8pt` (`.padding(.vertical, 8)`) vertical padding and `Color(hex: 0x2A2A2A)` background on `.onHover` to indicate selection.

### Custom Components: The "Signal Monitor"
- **Waveform Display:** Use `Color.white` for the `Path` stroke and `Color(hex: 0x353535)` for the background grid inside a `Canvas` or `Shape`. Lines must be 1pt via `.stroke(lineWidth: 1)`. No `.fill()` or glow effects on the wave.

## 6. Do's and Don'ts

### Do
- **Embrace the Grid:** Align every element to the 4pt base unit using multiples of `4` in all `.padding()`, `.frame()`, and `.spacing()`. If an element is off by 1pt, the "Engineering" feel is lost.
- **Use Monospace for Variables:** Any data that changes (frequency, time, percentage) must use `.font(.system(size:design: .monospaced))`.
- **Intentional Negative Space:** Use large `.padding()` regions with `Color(hex: 0x0E0E0E)` backgrounds to separate "Control Groups" (Oscillators vs. Filters).

### Don't
- **No Softness:** Never use `cornerRadius` above `2`. No `.capsule` shaped buttons.
- **No Gradients:** No `LinearGradient` or `AngularGradient`. Color transitions must be stepped (a hard `.background()` change between grey and black) rather than smooth.
- **No "Vibrant" Colors:** Avoid using `.red` / error color unless the audio is actually clipping or a process has failed. The system stays monochrome to keep the user focused on the sound.
- **No 100% Opaque Borders:** Never use `Color.white` for a border; it is too loud. Use `Color(hex: 0x919191)` or `Color(hex: 0x474747)` at reduced `.opacity()`.
