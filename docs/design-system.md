# Foundry — Design System v1.0

## Typography

| Role | Font | Weight | Usage |
|------|------|--------|-------|
| Display / Titles | Archtype Stedelijk W00 | Regular · Bold | Plugin names, screen headings, splash |
| UI / Body / Meta | Azeret Mono | 300–700 | Labels, states, formats, buttons, nav, body, all-caps metadata |

**Rationale:** Stedelijk brings modernist/Bauhaus institutional weight to display. Azeret Mono gives precision and engineering character to the UI layer. The contrast creates tension between craft and technical precision.

**Fallback:**
```
Display: "Archtype Stedelijk W00", "Editorial New", Georgia, serif
UI:      "Azeret Mono", "IBM Plex Mono", "SF Mono", monospace
```

---

## Color

### Dark Mode
| Token | Value | Usage |
|-------|-------|-------|
| `--color-bg` | `#080808` | App background |
| `--color-surface` | `#111111` | Cards, panels |
| `--color-surface-raised` | `#1A1A1A` | Hover states, inspector |
| `--color-border` | `#2A2A2A` | Dividers, card borders |
| `--color-border-mid` | `#383838` | Stronger separators |
| `--color-text-primary` | `#F7F7F7` | Primary text |
| `--color-text-secondary` | `#666666` | Metadata, labels |
| `--color-text-muted` | `#3A3A3A` | Disabled, placeholders |

### Light Mode
| Token | Value | Usage |
|-------|-------|-------|
| `--color-bg` | `#FAFAFA` | App background |
| `--color-surface` | `#FFFFFF` | Cards, panels |
| `--color-surface-raised` | `#F2F2F2` | Hover states |
| `--color-border` | `#E0E0E0` | Dividers |
| `--color-border-mid` | `#CCCCCC` | Stronger separators |
| `--color-text-primary` | `#111111` | Primary text |
| `--color-text-secondary` | `#888888` | Metadata, labels |
| `--color-text-muted` | `#BBBBBB` | Disabled, placeholders |

### Accent (both modes)
| Token | Value | Usage |
|-------|-------|-------|
| `--color-danger` | `#E5302A` | Error states · destructive actions · build failures only. Never decorative. |

**Palette philosophy:** Strict monochrome. No accent colors except danger red, used sparingly and semantically only.

---

## Spacing (4px base)

```
--space-1:   4px
--space-2:   8px
--space-3:  12px
--space-4:  16px
--space-5:  20px
--space-6:  24px
--space-8:  32px
--space-10: 40px
--space-12: 48px
--space-16: 64px
```

---

## Type Scale

| Token | Size | Font | Weight | Usage |
|-------|------|------|--------|-------|
| `--text-3xl` | 56px | Stedelijk | 700 | Splash / hero display |
| `--text-2xl` | 40px | Stedelijk | 700 | Screen titles |
| `--text-xl` | 28px | Stedelijk | 600 | Section headings |
| `--text-lg` | 20px | Azeret Mono | 500 | Prominent labels |
| `--text-md` | 14px | Azeret Mono | 400 | Body text |
| `--text-base` | 11px | Azeret Mono | 400 | Secondary body |
| `--text-sm` | 9px | Azeret Mono | 400–500 | All-caps metadata, badges |
| `--text-xs` | 8px | Azeret Mono | 400 | Micro labels |

Metadata labels always ALL-CAPS with letter-spacing 0.1em+.

---

## Motion

| Token | Duration | Usage |
|-------|----------|-------|
| `--duration-fast` | 120ms | State changes, button press, badge |
| `--duration-base` | 200ms | Tab switches, hover reveals, modal |
| `--duration-slow` | 350ms | Inspector panel, sheet entrance, page transitions |
| `--ease-out` | `cubic-bezier(0.16, 1, 0.3, 1)` | All entries |
| `--ease-in-out` | `cubic-bezier(0.4, 0, 0.2, 1)` | Transitions between states |

**Principle:** Every animation is purposeful. No decorative motion. All animations interruptible.

---

## Hardware Frame

Foundry presents as a physical instrument, not a generic macOS window.

- **Outer border:** 1.5px, `--color-border-mid`, border-radius 12px
- **Inner highlight:** top edge `linear-gradient` at 6% white opacity
- **Box shadow:** `inset 0 1px 0 rgba(255,255,255,0.06)` + outer drop shadow
- **Titlebar:** separate surface `--color-surface`, height 44px

---

## Components

### Plugin Card
- Background: `--color-surface`
- Border: `1px solid --color-border`
- Border-radius: `6px`
- Artwork area: grid dot background, symbol centered, height 80px
- Title: Azeret Mono, `--text-lg`, `--color-text-primary`, weight 600
- Meta: Azeret Mono, `--text-sm`, `--color-text-secondary`, ALL-CAPS

### Buttons — Pill shape (`border-radius: 100px`)
- Primary: background `--color-text-primary`, color `--color-bg`, weight 600
- Secondary: transparent, border `--color-border-mid`, color `--color-text-primary`
- Ghost: transparent, border `--color-border`, color `--color-text-secondary`
- Danger: transparent, border `rgba(229,48,42,0.3)`, color `--color-danger`

### Inspector Panel
- Width: 280px, slides from right
- Background: `--color-surface-raised`
- Border-left: `1px solid --color-border`
- Duration: `--duration-slow` + `--ease-out`

### Progress — Radial arc
- Segmented radial SVG, 5 build steps
- Track: `--color-border`, Fill: `--color-text-primary`
- Center: percentage + "BUILD" label in Azeret Mono

### Badges
- Border-radius: `2px` (not pill — square-ish for precision feel)
- Font: Azeret Mono, 9px, ALL-CAPS, letter-spacing 0.08em
- States: default, active (filled white), error (red border)

---

## Grid & Background Texture

Subtle dot/line grid at very low opacity (2–3%) on artwork areas and empty states.
```
background-image:
  linear-gradient(rgba(255,255,255,0.025) 1px, transparent 1px),
  linear-gradient(90deg, rgba(255,255,255,0.025) 1px, transparent 1px);
background-size: 40px 40px;
```

---

## Platform
macOS SwiftUI — dark + light mode. 4px base grid. Desktop density (not mobile).

