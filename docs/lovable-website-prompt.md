# Lovable Website Prompt

Paste this into Lovable:

```text
Build a modern, premium marketing website for **Vaultaire: Encrypted Vault** (iOS app).
Goal: maximize App Store installs while clearly communicating privacy-by-design.

Work section-by-section (component-first), not as one giant rewrite. Use real copy (no lorem ipsum).

## Product truth (must stay accurate)
- Vaultaire is local-first encrypted storage on iPhone.
- Unlock with a pattern; different patterns can open different vaults.
- Wrong pattern should be framed as plausible deniability (appears as empty vault).
- No account required. No personal identity required to use core app.
- Optional encrypted iCloud backup and optional encrypted vault sharing exist.
- Do NOT claim "we have zero telemetry" or "zero dependencies."
- Do NOT use fear-mongering language or unverifiable superlatives like "unhackable."

## Core messaging to include verbatim
- "Protected by Design"
- "No accounts."
- "No personal data."
- "No backdoors."
- "Only your pattern can decrypt your files."
- "Hidden from all: Nobody can tell how many vaults you have."

## Visual direction
Aesthetic: modern, cinematic, trustworthy, privacy-tech, clean but bold.
Avoid generic template look.

Use this design system (semantic tokens):
- --bg-light: #D1D1E9
- --bg-dark: #20233C
- --surface-light: #FFFFFE
- --surface-dark: #323444
- --text-light: #2B2C34
- --text-dark: #E8E8F0
- --accent-light: #1F0D77
- --accent-dark: #CCC3F8
- --highlight-light: #E45858
- --highlight-dark: #FF6F6F

Typography:
- Headings: "Space Grotesk" (or similarly expressive modern sans)
- Body/UI: "Plus Jakarta Sans"
- Strong hierarchy, generous spacing, high contrast, mobile-first.

Motion:
- Subtle, meaningful animations only (hero reveal, section fade/stagger, CTA hover).
- Add a tasteful pattern-dot animation motif inspired by the app’s pattern lock.

## Pages to create
1) `/` Marketing landing page
2) `/privacy` Privacy policy page (clean readable legal layout)
3) `/terms` Terms page
4) `/s` share-link fallback page (if user opens link without app: explain + App Store CTA)

## Landing page structure
1. Sticky nav (logo, anchors, App Store CTA)
2. Hero:
   - H1 focused on privacy + control
   - Subheadline with local-first + pattern key concept
   - Primary CTA: "Download on the App Store"
   - Secondary CTA: "See how it works"
3. Trust strip with 3 lines:
   - No accounts.
   - No personal data.
   - No backdoors.
4. Feature sections/cards:
   - Pattern-Based Encryption
   - True Plausible Deniability
   - Hidden Vaults
   - Duress Vault
   - Encrypted iCloud Backup
   - Secure Vault Sharing
5. "How it works" 3-step timeline
6. Security architecture snapshot (plain-language, non-hype)
7. FAQ (6-8 items)
8. Final CTA block
9. Footer with legal links and support email placeholder

## SEO + accessibility requirements
- Single H1 per page
- Strong `<title>` and meta description per page
- OpenGraph + Twitter meta tags
- Canonical tags
- JSON-LD `SoftwareApplication` schema on home page
- Semantic HTML landmarks (`header/main/section/footer`)
- Proper alt text, focus states, keyboard accessibility
- Performance-conscious images and lazy loading where relevant

## Technical constraints
- React + Vite + TypeScript + Tailwind
- Build reusable components and keep design tokens centralized
- No inline hardcoded color utilities in components when token can be used
- Keep implementation clean, modular, and production-ready

Start with:
1) Design tokens + base layout shell
2) Home page core sections
3) Privacy + Terms + /s pages
4) Final polish pass (responsiveness, accessibility, SEO)
```
