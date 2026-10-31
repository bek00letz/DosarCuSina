# AGENTS.md — Dosar cu Șină

## Apple Craftsmanship & Polish Standard

Any piece of software, interface, component, script, or artifact created in this workspace must look, feel, and function like something Apple shipped.

This is not about superficial aesthetics, but about the uncompromising, obsessive attention to the subtle details that elevate a product from merely functional to undeniably polished, intuitive, and tactile.

### 1. The Core Philosophy
- **Restraint and Intentionality**: Every element, border, gradient, and margin must have a clear reason to exist. If an element doesn't serve the user or clarity, eliminate it. Chrome should recede so content takes center stage.
- **The "Invisible" Polish**: The best design details are the ones the user feels rather than notices—fluid transitions, forgiving touch targets, instantaneous responses, and seamless state preservation.
- **Respect for the Human**: Never confuse, startle, or overwhelm the user. Protect user agency, avoid dark patterns, avoid gratuitous modal interruptions, and respect system preferences (`prefers-color-scheme`, `prefers-reduced-motion`, `prefers-contrast`).

### 2. Visual & Typographic Hierarchy
- **Typography as Architecture**:
  - Native system font stacks (`-apple-system`, `SF Pro Display`, `SF Pro Text`, `system-ui`).
  - Strict typographic scale with intentional line heights (`leading`), letter spacing (`tracking`), and contrast hierarchies (primary, secondary, tertiary labels).
  - Proper typographic punctuation: real quotes (“ ”), apostrophes (’), em dashes (—), and ellipsis (…).
- **Concentric Geometry**:
  - Nested corners must be mathematically concentric: $R_{\text{inner}} = R_{\text{outer}} - \text{padding}$.
  - Apple continuous squircle curves.
- **Subtle Depth & Elevation**:
  - Soft, multi-layered ambient drop shadows rather than harsh single-offset dark shadows.
  - Delicate hairline borders (0.5pt subtle overlays matching dynamic contrast) to define surfaces against any background.

### 3. Motion, Physics & Tactility
- **Natural, Organic Spring Physics**:
  - Fluid spring curves (`cubic-bezier(0.25, 1, 0.5, 1)` or fluid springs).
  - Transitions grounded physically—elements expand from their origin and settle with weight.
- **Micro-Interactions & State Polish**:
  - Instant response to touch and hover with haptic feedback (`UIImpactFeedbackGenerator`).
  - Zero layout shifts (CLS).

### 4. Project Guidelines
- Architecture: SwiftUI + SwiftData (iOS 17+ / 18+).
- Local-first architecture with CloudKit sync.
- Hybrid OCR: VisionKit on-device + Gemini API for structured extraction.
