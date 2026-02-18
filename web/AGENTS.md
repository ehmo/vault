# Web Agent Instructions

Static website for Vaultaire — landing page, legal pages, AASA file, share link fallback.

Hosted on Cloudflare Pages. No server-side logic — all pages are static HTML + Tailwind CSS v4.

## Domains

- **Primary**: `vaultaire.app` (hardcoded in iOS app — AASA, paywall links, App Store listing)
- **Redirect**: `vaultaire.com` → 301 → `vaultaire.app`

## Dev

```bash
npm install
npm run dev    # watch mode — rebuilds CSS on change
npm run build  # production CSS build
```

Preview locally: `npx serve .` (after `npm run build`)

## Structure

- `_headers` — Cloudflare Pages headers (AASA content-type, security headers)
- `_redirects` — Cloudflare Pages redirect rules
- `.well-known/apple-app-site-association` — AASA for iOS universal links
- `index.html` — Landing/marketing page
- `s/index.html` — Share link fallback (shown when user doesn't have the app)
- `privacy/index.html` — Privacy policy (linked from iOS app paywall)
- `terms/index.html` — Terms of use (linked from iOS app paywall)
- `favicon.svg` — SVG favicon (lock icon)
- `styles/input.css` — Tailwind source with Vaultaire design tokens
- `styles/output.css` — Generated (gitignored)

## Design Tokens

Matches iOS app (`VaultTheme.swift`):
- Background: `#D1D1E9` (light) / `#20233C` (dark)
- Surface: `#FFFFFE` (light) / `#323444` (dark)
- Text: `#2B2C34` (light) / `#E8E8F0` (dark)
- Accent: `#1F0D77` (light) / `#CCC3F8` (dark)
- Highlight: `#E45858` (light) / `#FF6F6F` (dark)

Defined in `styles/input.css` as `@theme` variables, used as `bg-vault-bg`, `text-vault-text`, etc.

## Shared Frontend Assets

- Shared cross-page chrome styles live in `styles/site-shared.css` (header, nav, footer, buttons, responsive nav behavior).
- Use `.btn-nav` (in `styles/site-shared.css`) for compact header CTA sizing instead of repeating inline button styles.
- Shared theme toggle behavior lives in `assets/theme-toggle.js` (`vaultaire-theme` localStorage key, `☀︎/☽` icon swap, `vaultaire-themechange` event).
- Shared competitor icon fallback behavior lives in `assets/compare-icon-fallback.js` (replace duplicated per-page inline scripts on compare pages).
- Competitor icons are stored locally in `assets/compare-icons/` (App Store sourced) and should be referenced by relative paths from compare pages, not hotlinked from `is1-ssl.mzstatic.com`.
- Keep per-page `<style>` blocks focused on page-specific layout/content only.
- `index.html` still contains an embedded style block for the hero/mockup experience; when changing global chrome (header/footer/mobile spacing), mirror equivalent adjustments there so home does not drift from shared pages.

## Deployment

Cloudflare Pages project `vaultaire-web`:
- Build command: `npm run build`
- Build output directory: `.` (root of web/)
- Root directory: `web/`

Deploy manually: `npx wrangler pages deploy . --project-name vaultaire-web`

Deployment notes:
- Wrangler prints a unique deployment URL (for example `https://<hash>.vaultaire-web.pages.dev`) after each successful deploy.
- In dirty git working trees, add `--commit-dirty=true` to silence wrangler's uncommitted-changes warning.

## AASA Requirements

The `apple-app-site-association` file MUST:
- Be served at `https://vaultaire.app/.well-known/apple-app-site-association`
- Have `Content-Type: application/json` (configured in `_headers`)
- Be accessible without redirects
- Contain the correct Team ID + Bundle ID: `UFV835UGV6.app.vaultaire.ios`

## Brand Learnings

- Use the iOS app logo assets directly in web pages: `/assets/vault-logo.png` for dark theme and `/assets/vault-logo-light.png` for light theme.
- Keep product naming/casing consistent everywhere: `Vaultaire`.
- Prefer explicit static links (`../terms/index.html`, `manifesto/index.html`) over router-style paths so pages work both on static hosts and direct file previews.
- Reuse the exact home-page header/footer chrome (nav spacing, theme glyph toggle `☀︎/☽`, angular `Get App` button, footer brand block) across every page to avoid visual drift.
- For nested compare pages (`/compare/<slug>/review/`), header nav links and shared script paths must use `../../../` depth; top-level compare pages use `../`, comparison detail pages use `../../`.
- Keep compare-specific layout in `compare/styles.css`, but always import and rely on `styles/site-shared.css` for shared chrome so header/footer/theme behavior stays identical across pages.
- Compare icon URLs from App Store can fail intermittently; attach a local fallback (`/assets/compare-fallback-icon.svg`) for all competitor icon images so cards/lists never render broken placeholders.
- For all-caps headings, keep positive tracking (around `0.02em`-`0.03em`) and avoid negative letter-spacing; keep body/legal copy at `1rem`+ with line-height near `1.6` for readability.
- Keep the primary nav item set in sync across all pages, including home. If compare exists in secondary pages, include `Compare` on `index.html` header nav too.
- For compare detail pages, breadcrumb display text and BreadcrumbList item #3 label must always start with `Vaultaire vs ...` (never just `vs ...`).
