---
name: SmartLook-AI
description: A boutique fitting-room mirror, rebuilt as an e-commerce platform — warm light, brass hardware, real layered depth.
colors:
  primary: "#7c2635"
  primary-light: "#a34353"
  primary-dark: "#551621"
  brass: "#b3843f"
  brass-light: "#dab876"
  brass-dark: "#86611f"
  success: "#4c7a5a"
  warning: "#b3843f"
  danger: "#a3402f"
  info: "#5b7089"
  bg: "#f5efe3"
  surface: "#fffbf3"
  text-primary: "#2a1c15"
  text-secondary: "#74604f"
  text-muted: "#a3907c"
  bg-dark-mode: "#201216"
  surface-dark-mode: "#2b181c"
  text-primary-dark-mode: "#f4e7d9"
typography:
  display:
    fontFamily: "Bodoni Moda, Times New Roman, serif"
    fontWeight: 500
    letterSpacing: "-0.01em"
  body:
    fontFamily: "Hanken Grotesk, -apple-system, BlinkMacSystemFont, sans-serif"
    fontWeight: 400
rounded:
  sm: "6px"
  md: "9px"
  lg: "14px"
  xl: "18px"
spacing:
  sm: "0.5rem"
  md: "1rem"
  lg: "1.75rem"
  xl: "2.5rem"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#fdf3e7"
    rounded: "{rounded.md}"
    padding: "0.7rem 1.35rem"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "0.65rem 1.25rem"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.lg}"
    padding: "1.75rem"
---

# Design System: SmartLook-AI

## Overview

**Creative North Star: "El Espejo" (The Mirror) — the boutique fitting-room**

SmartLook-AI's interface behaves like a three-way fitting-room mirror in a real boutique: warm, directional light; brass hardware; a velvet-curtain dark mode; surfaces that stand proud of the page rather than float behind blurred glass. This was chosen deliberately against two category ruts — the flat white SaaS product-grid template, and the neon/glassmorphism "AI product" look — because the product's actual mechanism (AR virtual try-on + an AI stylist) is literally about seeing yourself, well-lit, in front of a mirror. Depth comes from real layered material — a brass top edge, a directional shadow, a specular highlight on a button — never from `backdrop-filter` blur used as decoration.

The system serves two registers from one world: **Persuade** surfaces (home, auth, the chat "attendant") run the world at full warmth and commitment; **Operate** surfaces (the admin, encargado, and proveedor back-offices) inherit the same tokens and the brass top-edge card language at lower visual noise, prioritizing scanability for daily catalog/inventory/reservation work. Proveedor's sidebar carries a sage-green identity accent (a legitimate role differentiation, not a stray color) instead of burgundy, so staff can tell at a glance which panel they're in.

**Key Characteristics:**
- Warm ivory "vitrina" light by default; a wine-charcoal "curtain" dark mode, never a generic navy/black.
- Brass is structural (borders, dividers, focus rings, specular highlights), never merely decorative gold.
- One committed saturated accent — a deep burgundy — carries CTAs, prices, and primary actions.
- No gradient text, no kicker/eyebrow labels, no unicode-glyph icons: every icon is drawn SVG, every heading speaks for itself.

## Colors

The palette reads as a lit boutique interior: warm ivory grounds, one committed burgundy accent, brass as the metallic structural note, and status colors pulled into the same warm family instead of stock Tailwind hues.

### Primary
- **Burgundy** (`#7c2635`, light `#a34353`, dark `#551621`): the single committed saturated color. Carries primary buttons, active nav states, prices, links, and the `.AI` wordmark suffix. Used at 30–60% of persuade surfaces (home hero, auth), restrained to small marks (active nav row, price text) on operate surfaces.

### Secondary
- **Brass** (`#b3843f`, light `#dab876`, dark `#86611f`): the structural metallic accent. Every card's top edge, every layout's sidebar border, the navbar's bottom border, focus rings, and specular highlights on filled buttons. Brass is never a text-fill gradient — it is hardware, always a border, ring, or icon color.

### Tertiary
- **Sage** (`#4c7a5a`) doubles as both the `success` status color and the Proveedor role's identity accent (its sidebar border, active nav state, and badges). Distinguishes the supplier panel from admin/encargado without introducing a new hue family.

### Neutral
- **Warm ivory** (`#f5efe3` page / `#fffbf3` surface): the light-mode ground — soft, lit, never stark white.
- **Ink** (`#2a1c15` primary text, `#74604f` secondary, `#a3907c` muted): warm near-black text, never pure gray.
- **Curtain** (`#201216` page / `#2b181c` surface, `#f4e7d9` text): the dark-mode ground — a wine-tinted near-black, not navy.
- **Warning** (`#b3843f`, shares brass's hue), **Danger** (`#a3402f`, muted brick), **Info** (`#5b7089`, dusty denim slate): status colors recolored into the warm family instead of stock red/amber/blue.

### Named Rules
**The Hardware Rule.** Brass is always a border, ring, or icon color — never a text-fill gradient, never a flat background wash on its own. If brass is filling a shape, it needs a directional highlight (an inset light streak) or it reads as flat mustard, not metal.

**The One Accent Rule.** Only burgundy carries saturated fills at scale (buttons, active states, prices). A second saturated color competing for the same weight (e.g., a bright blue "info" badge at button size) breaks the boutique's calm.

## Typography

**Display Font:** Bodoni Moda (with Times New Roman, serif fallback)
**Body Font:** Hanken Grotesk (with system sans fallback)

**Character:** A high-contrast Didone display face (the register of engraved brass boutique signage and fashion-house wordmarks) paired with a warm, legible humanist grotesk for body and UI — kept to exactly two faces so operate surfaces (dense admin tables) stay calm and scannable.

### Hierarchy
- **Display** (weight 500–600, 2.5–3.3rem, line-height ~1.15): hero headlines, auth showcase headline. Italic display for emphasized phrases (e.g. "Realidad Aumentada e IA") in brass-light, never a gradient fill.
- **Headline** (weight 600, 1.8–2rem): section titles (`.section-title`, dashboard `h1`).
- **Title** (weight 600, 1.2–1.45rem): card/modal titles, product names.
- **Body** (weight 400, 0.85–1.05rem, line-height 1.5–1.6): descriptions, paragraphs.
- **Label** (weight 600–700, 0.68–0.78rem, letter-spacing 0.05–0.09em, uppercase): table headers, nav group labels, badges — never a standalone kicker sitting above a heading.

### Named Rules
**The No-Kicker Rule.** No uppercase label ever sits alone above a heading as a "kicker." A heading carries its own weight; supporting context becomes a badge next to content, not a caption above it.

## Layout

`.page-container` centers content at a 1280px max-width with 2rem side padding (1.1–1.25rem on mobile ≤640px). Admin/encargado/proveedor shells use a fixed 240–250px sidebar that pushes content on desktop and becomes a fixed overlay with a backdrop scrim below 900px width. Product and stat grids use `repeat(auto-fit/auto-fill, minmax(...))` so columns reflow fluidly rather than snapping at fixed breakpoints. The hero section is inset with a small margin and its own rounded frame (`var(--radius-xl)`) rather than running edge-to-edge, reinforcing the "framed mirror" read.

## Elevation & Depth

Hybrid: solid surfaces (no `backdrop-filter` blur as decoration) carry depth through a **brass top edge plus a layered, offset, soft-blur shadow** — never a flat 1px border alone, never a glass/frosted panel. This is the system's answer to "3D": real layered material, not blur tricks. Interactive elevation (card hover, button hover) lifts with `translateY` and swaps a subtle shadow for a stronger one; it never introduces a new border color under hover.

### Shadow Vocabulary
- **`--shadow-subtle`** (`0 10px 28px rgba(42,28,21,.1)`): resting cards, stat tiles.
- **`--shadow-card`** (`0 22px 44px rgba(42,28,21,.14)`): hovered cards, modals, floating sidebars on mobile.
- **`--shadow-panel`** (`0 1px 0 rgba(255,255,255,.6) inset, 0 16px 32px rgba(42,28,21,.12)`): the `.card` class — an inset top highlight simulating a panel standing proud of the wall, plus a cast shadow.

### Named Rules
**The Standing Panel Rule.** A `.card` always pairs its brass top border with `--shadow-panel`, never one without the other — that combination is what reads as "standing off the wall" instead of a flat outlined box.

## Shapes

Rectangular-refined with soft corners — a mirror frame, not a pill-shaped SaaS control. Radius scale: `sm` 6px (inputs, small chips), `md` 9px (buttons), `lg` 14px (cards, modals — within the 12–16px band that avoids the "ghost card" look), `xl` 18px (hero frame). Fully round (`50%`/`999px`) is reserved for small circular controls (icon buttons, avatars, the chat FAB) and pill badges/chips — never for primary buttons or cards.

## Components

### Buttons
- **Shape:** `border-radius: var(--radius-md)` (9px).
- **Primary:** burgundy gradient fill, 1px brass-dark border, an inset top highlight (`inset 0 1px 0 rgba(255,214,158,.35)`) simulating a specular catch of light, plus a burgundy-tinted drop shadow. Lifts 2px on hover.
- **Secondary:** transparent/overlay fill, `border-strong` border that turns brass on hover — a "ghost" button, never a second filled color competing with primary.
- **Danger:** low-opacity brick-red fill with a matching border; reserved for destructive actions.

### Cards / Containers
- **Corner style:** 14px (`--radius-lg`).
- **Background:** `--bg-card` (solid ivory / curtain surface, no transparency).
- **Border:** 1px `--border-color` on the sides/bottom, 2px brass on top only — the "standing panel" signature.
- **Shadow strategy:** `--shadow-panel` at rest, `--shadow-card` + `translateY(-3px to -6px)` on hover where interactive.
- **Internal padding:** 1.5–1.75rem.

### Inputs / Fields
- **Style:** warm overlay background, 1px `--border-color`, `--radius-sm` (6px).
- **Focus:** border turns burgundy plus a 3px brass-tinted glow ring (`box-shadow: 0 0 0 3px var(--border-glow)`), never a hard blue browser-default outline.

### Navigation
- **Top navbar:** solid ivory/curtain surface, 2px brass bottom border (not a blurred glass header), circular icon buttons, Bodoni Moda wordmark with the `.AI` suffix in solid burgundy (never a gradient text fill).
- **Sidebars (admin/encargado/proveedor):** 2px brass (or sage, for proveedor) right border; active nav row is a solid filled pill in the role's accent color with a subtle inset highlight, not a left-accent bar.
- **Mobile:** sidebar becomes a fixed 260–270px overlay with a scrim backdrop below 900px; navbar wraps to two rows below 768px.

### Product Card (signature component)
The catalog's product tile: an ivory panel with a brass-on-hover border, a category pill badge, a stock-status pill (dot + label, colored by `success`/`warning`/`danger`), and — on hover — a soft radial brass "spotlight" glow that fades in behind the product image, like a vanity bulb switching on over the garment. This is the system's signature interaction, distinct from a generic image-zoom hover.

## Do's and Don'ts

### Do:
- **Do** use the brass top-border + `--shadow-panel` pairing for every standalone panel/card.
- **Do** keep burgundy as the only saturated fill at button/badge scale; recolor any new "info" or category accent into the warm family (sage, brass, dusty denim) rather than reaching for stock red/blue/green.
- **Do** draw every icon as inline SVG through the existing `IconComponent` (`app-icon`) — never a unicode glyph or emoji.
- **Do** set headings in Bodoni Moda (inherited automatically from the global `h1–h6` rule) and body/UI text in Hanken Grotesk.

### Don't:
- **Don't** use `backdrop-filter` blur as a decorative "glass" panel treatment — the system's depth vocabulary is layered solid material, not frosted glass.
- **Don't** add a kicker/eyebrow label above a heading, anywhere, for any reason.
- **Don't** fill text with a gradient for emphasis — use `.text-accent` (solid burgundy) or weight/size instead.
- **Don't** use a colored `border-left`/`border-right` accent bar on cards, list items, or nav rows — active/selected state is a filled background, not a stripe.
- **Don't** introduce a new saturated hue for a one-off status or category color — extend the existing warm family (burgundy / brass / sage / dusty denim / brick).
