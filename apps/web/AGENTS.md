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

- Shared chrome styles: `styles/site-shared.css` (header, nav, footer, buttons, responsive nav).
- Use `.btn-nav` for compact header CTA sizing — don't repeat inline button styles.
- Shared interactive behavior (theme toggle, mobile nav, compare icon fallback, home/invite runtime): `assets/alpine-app.js`, initialized via Alpine (`assets/alpine.min.js` + `x-data="vaultaireApp()"`).
- Competitor icons: stored locally in `assets/compare-icons/` — reference by relative path, never hotlink from `is1-ssl.mzstatic.com`.
- Page-specific styles: `styles/pages/*.css`, imported from `styles/input.css` so all CSS emits through `styles/output.css`.
- No new inline `<style>` blocks in production pages — treat the Tailwind input/import graph as the single stylesheet entrypoint.

## Deployment

Cloudflare Pages project `vaultaire-web`:
- Build command: `npm run build`
- Build output directory: `.` (root of apps/web/)
- Root directory: `apps/web/`

Deploy manually: `npx wrangler pages deploy . --project-name vaultaire-web`

Wrangler prints a unique deployment URL after each deploy. In dirty git trees, add `--commit-dirty=true`.

## AASA Requirements

The `apple-app-site-association` file MUST:
- Be served at `https://vaultaire.app/.well-known/apple-app-site-association`
- Have `Content-Type: application/json` (configured in `_headers`)
- Be accessible without redirects
- Contain the correct Team ID + Bundle ID: `UFV835UGV6.app.vaultaire.ios`

## Brand & Design Learnings

### Brand & Copy
- Product name is always `Vaultaire` (never `vaultaire`, never `VAULTAIRE`).
- Keep the primary nav item set in sync across ALL pages including `index.html`. If Compare exists in secondary pages, include it on the home header nav too.
- For all-caps headings: positive letter-spacing (`0.02em`–`0.03em`), never negative. Body/legal copy: `1rem`+, `line-height: 1.6`.

### Navigation & Links
- Use explicit static links (`../terms/index.html`, `manifesto/index.html`) — not router-style paths — so pages work on static hosts and direct file previews.
- Path depth for nav links and shared scripts:
  - Top-level pages: `./` or root-relative
  - Compare top-level (`/compare/<slug>/`): `../`
  - Compare detail (`/compare/<slug>/review/`): `../../`
  - Further nested: `../../../`
- Compare detail breadcrumb display text and `BreadcrumbList` item #3 label must always start with `Vaultaire vs ...` (never just `vs ...`).

### CSS Architecture
- Scope non-home page CSS under page-specific body classes (`.page-privacy`, `.page-terms`, `.page-manifesto`, `.page-invite`, `.page-compare`) to prevent `main`/`h1`/`section` rules leaking into home and breaking header/hero layout.
- Compare-specific layout goes in `compare/styles.css`; always import `styles/site-shared.css` for shared chrome so header/footer/theme behavior stays identical.
- Attach `assets/compare-fallback-icon.svg` as a local fallback on all competitor icon `<img>` elements — App Store icon URLs fail intermittently.

### SEO
- Keep SEO baseline files explicit in repo root: `robots.txt` (allow crawl + sitemap link), `sitemap.xml` (real XML + `/sitemap.xml` content-type header in `_headers`), root favicons (`/favicon.png`, `/apple-touch-icon.png`) linked from page heads.

### iOS Smart App Banner (`/s` page)
- Use native iOS Smart App Banner only (`<meta name="apple-itunes-app" content="app-id=6758529311">`). No custom in-page App Store banner UI. Do not mutate the meta tag at runtime via JavaScript.
- The banner renders a native **1px separator line** at its bottom edge (iOS system UI). This line **cannot be removed via CSS** — it is not a web border or backdrop-filter artifact. Any attempt via `border-bottom`, `backdrop-filter`, or `background` on the header will fail. The only way to remove the line is to remove the `<meta name="apple-itunes-app">` tag.
- Safari keeps same-domain universal links in-browser. The manual "Open in Vaultaire" action should deep-link to the custom scheme first (include invite token in both `#fragment` and `?p=` for resilience), then optionally fall back to `https://vaultaire.app/s...`.

### Home Hero & Mockup
- Logo assets: `/assets/vault-logo.png` (dark theme), `/assets/vault-logo-light.png` (light theme).
- Reuse the exact home header/footer chrome (nav spacing, theme glyph toggle, angular "Get App" button, footer brand block) across every page to avoid visual drift.
- Keep hero/mockup placeholder media local (`assets/mockup/*`) — no third-party placeholder hosts.
- Pause RAF/timer animation loops on `visibilitychange`/`pagehide`, resume on `pageshow`. Also pause when hero is off-screen via `IntersectionObserver` — not only on tab-hide — to reduce long-session CPU/memory churn.
- In Alpine pages, do not combine `x-init="init()"` with a component `init()` method — Alpine auto-runs `init()` and double-wiring causes duplicate listeners (e.g., theme toggle double-flip).
- Theme toggle: use inline SVG (sun/moon), not glyph characters (`☀︎/☽`) — glyphs have font-metric drift across browsers. At icon-only breakpoints, force a fixed `44×44` button with centered content.
- Phone mockup circular controls (`+`): use geometric bars/pseudo-elements, not text glyphs. Font metrics drift by browser. Keep FAB around `40×40` to match iOS proportions.
- Hero phone mockup proportions: drive `width` from the same `--mockup-h` variable (`width = height * 0.48`) — never set fixed `width` and constrained `height` together at desktop/tablet breakpoints. This keeps proportions stable on short viewports (e.g., 1024×800).
- Keep trust-strip `margin-top: 0` (no overlap into the hero section) so the hero phone never collides with the strip at edge resolutions.
