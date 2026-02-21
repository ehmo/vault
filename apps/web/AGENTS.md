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
- Shared interactive behavior (theme toggle, mobile nav, compare icon fallback, home/invite runtime) lives in `assets/alpine-app.js` and is initialized via Alpine (`assets/alpine.min.js` + `x-data="vaultaireApp()"`).
- Competitor icons are stored locally in `assets/compare-icons/` (App Store sourced) and should be referenced by relative paths from compare pages, not hotlinked from `is1-ssl.mzstatic.com`.
- Keep page-specific styles in `styles/pages/*.css` and import them from `styles/input.css` so all CSS is emitted through `styles/output.css`.
- Avoid adding new inline `<style>` blocks in production pages; treat the Tailwind input/import graph as the single stylesheet entrypoint.

## Deployment

Cloudflare Pages project `vaultaire-web`:
- Build command: `npm run build`
- Build output directory: `.` (root of apps/web/)
- Root directory: `apps/web/`

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
- Keep SEO baseline files explicit in repo root: `robots.txt` (allow crawl + sitemap link), `sitemap.xml` (real XML file + `/sitemap.xml` XML content-type header), and root favicon assets (`/favicon.png`, `/apple-touch-icon.png`) linked from page heads.
- Invite fallback page (`/s`) should use native iOS Smart App Banner only (no custom in-page app-store banner UI) with a static `<meta name="apple-itunes-app" content="app-id=6758529311">`. Do not mutate the Smart App Banner meta tag at runtime via JavaScript.
- Safari keeps same-domain universal links in-browser by design. On `/s`, the manual `Open in Vaultaire` action should deep-link to custom scheme first (include invite token in both `#fragment` and `?p=` for resilience), then optionally fall back to `https://vaultaire.app/s...` if app handoff does not occur.
- For animation-heavy pages (home hero/mockup), pause RAF/timer loops on `visibilitychange`/`pagehide` and resume on `pageshow`; otherwise detached DOM + listener retention appears in heap snapshots during navigation.
- In Alpine pages, do not combine `x-init="init()"` with a component `init()` method; Alpine already auto-runs `init()` and double-wiring causes duplicated listeners (for example theme toggle double-flip).
- Keep hero/mockup placeholder media local (`assets/mockup/*`) instead of third-party placeholder hosts to avoid extra DNS/network latency and flaky external dependencies.
- Scope non-home page CSS under page-specific body classes (`.page-privacy`, `.page-terms`, `.page-manifesto`, `.page-invite`, `.page-compare`) so later imports do not leak `main/h1/section` rules back into home and break header/hero layout.
