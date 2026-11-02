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
  - Nested corners must be mathematically concentric: $R_{\text{inner}} = R_{\text{outer}} - \text{padding}$. Never have sharp-cornered children inside rounded containers.
  - Standard Apple squircle/continuous corner curves (`corner-smoothing: 60%` / smooth continuous curvature).
- **Subtle Depth & Elevation**:
  - Soft, multi-layered ambient drop shadows rather than harsh single-offset dark shadows.
  - Delicate hairline borders (0.5pt subtle overlays matching dynamic contrast) to define surfaces against any background.

### 3. Motion, Physics & Tactility
- **Natural, Organic Spring Physics**:
  - Fluid spring curves (`cubic-bezier(0.25, 1, 0.5, 1)` or fluid springs).
  - Transitions grounded physically—elements expand from their origin and settle with weight.
- **Micro-Interactions & State Polish**:
  - Instant response to touch and hover with haptic feedback (`UIImpactFeedbackGenerator`).
  - Zero layout shifts (CLS): reserve space for dynamic content, images, and asynchronous data.

---

## 4. Public Repository Security & Privacy Policies

The GitHub repository for *Dosar cu Șină* is **public**. Every contributor and AI agent must adhere strictly to these non-negotiable security mandates:

### 4.1 Zero-Secrets & Zero-PII Policy
- **No Hardcoded Credentials**: Never commit API keys, private tokens, passwords, keystores, or certificates.
- **Bring Your Own Key (BYOK)**: Any external API key (such as Google Gemini) must be:
  - Stored exclusively on the user's physical device in the **iOS Keychain** (`kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it never leaves the device).
  - For local developer builds, read from an untracked local file (`ios/Config.xcconfig`) created from `ios/Config.xcconfig.template`.
- **Sanitized Mock Data**: Never include real names, email addresses, phone numbers, vehicle registration numbers (VIN/plates), or real Romanian personal identification data (CNP, adrese) in previews, tests, or mock files. Use realistic placeholders (e.g., `B-123-ABC`, `ENGIE Romania S.A.`, `VW Golf 2018`).
- **Local-First & Zero Central Database**:
  - Data remains on the user's device (`SwiftData` on iOS, `Room` on Android).
  - Cloud synchronization uses the user's private Apple ID (`CloudKit` private database) or personal Google Drive AppData folder. The developer hosts **no central user database** and has zero access to user records.

---

## 5. The Confidential Security Vault (`private/`)

During development, security vulnerabilities, edge-case bug traces, exploit vectors, and sensitive architectural notes will be identified. These **must never be published online**.

### 5.1 Rules for `private/`
1. **Strictly Local-Only**: The entire `private/` directory and its contents are excluded via `.gitignore` and enforced by `.git/hooks/pre-commit`.
2. **Where to Document Findings**:
   - Log identified security flaws, severity, and reproduction steps in `private/VULNERABILITY_REGISTER.md`.
   - Log sensitive crash logs, internal stack traces with file paths, or race condition repros in `private/INTERNAL_BUGS.md`.
3. **Defense-in-Depth Enforcement**:
   - The `.git/hooks/pre-commit` script actively scans every staged commit. If any file matching `private/`, `.private/`, `internal/`, or sensitive credential patterns is detected, **the commit is automatically aborted**.

---

## 6. App Store Distribution & Feature Tiering Policy

To comply with **Apple App Store Review Guidelines** (Guidelines 2.1 & 3.1.1):
- **100% Free App**: The app is free to download and use with zero paywalls.
- **Complete Offline Utility**: The core app must be 100% functional without an API key (unlimited assets, events, offline Vision OCR, widgets, cash-flow projections).
- **Pro AI Mode**: Unlocked exclusively through the user's free Gemini API key (BYOK). The UI must never block users who choose not to add a key.

---

## 7. Git Commit Policy & Development Workflow

To maintain a clean, professional, and audit-ready public Git history, all commits must follow this standard.

### 7.1 Conventional Commit Format
Use structured commit messages in the imperative mood:

```text
<type>(<scope>): <short description in imperative present tense>

[optional body explaining WHY the change was made]
```

#### Allowed Types:
- `feat`: A new user-facing feature, screen, or capability (e.g., `feat(scanner): add live vision preview and byok prompt sheet`).
- `fix`: A bug fix or correction (e.g., `fix(events): correct countdown calculation for leap years`).
- `docs`: Documentation updates (e.g., `docs(spec): document custom modules engine schema`).
- `refactor`: Code restructuring without changing functional behavior (e.g., `refactor(models): modularize asset category helper`).
- `chore`: Project maintenance, `.gitignore`, build settings, or templates (e.g., `chore(security): add pre-commit hook`).
- `test`: Adding or modernizing unit or UI tests.

### 7.2 Commit Atomicity & Rules
- **One Logical Unit Per Commit**: Do not mix a bug fix with a feature addition or unrelated formatting changes.
- **No In-Progress Breakages**: The codebase must build cleanly (`swiftc -parse` or `xcodebuild`) at every commit.
- **Review Staged Files Explicitly**: Always run `git status` or inspect staged diffs before committing to verify that no accidental temporary files, credentials, or private vault notes are included.

### 7.3 Documentation Synchronization Map
Whenever changes occur, document them in their designated source of truth:
1. **Product Features & Architecture**: Update [`SPEC.md`](file:///Users/play/Developer/DosarCuSina/SPEC.md).
2. **Public Instructions & Onboarding**: Update [`README.md`](file:///Users/play/Developer/DosarCuSina/README.md).
3. **Engineering & Quality Standards**: Update [`AGENTS.md`](file:///Users/play/Developer/DosarCuSina/AGENTS.md).
4. **Vulnerabilities & Attack Surface**: Document locally in [`private/VULNERABILITY_REGISTER.md`](file:///Users/play/Developer/DosarCuSina/private/VULNERABILITY_REGISTER.md).
5. **Private Bugs & Crash Stack Traces**: Document locally in [`private/INTERNAL_BUGS.md`](file:///Users/play/Developer/DosarCuSina/private/INTERNAL_BUGS.md).
