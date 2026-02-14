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
- Background: `#D1D1E9` (light) / `#1A1B2E` (dark)
- Surface: `#FFFFFE` (light) / `#2D2E3A` (dark)
- Text: `#2B2C34` (light) / `#E8E8F0` (dark)
- Accent: `#6246EA` (indigo-purple)
- Highlight: `#E45858` (coral red)

Defined in `styles/input.css` as `@theme` variables, used as `bg-vault-bg`, `text-vault-text`, etc.

## Deployment

Cloudflare Pages project `vaultaire-web`:
- Build command: `npm run build`
- Build output directory: `.` (root of web/)
- Root directory: `web/`

Deploy manually: `npx wrangler pages deploy . --project-name vaultaire-web`

## AASA Requirements

The `apple-app-site-association` file MUST:
- Be served at `https://vaultaire.app/.well-known/apple-app-site-association`
- Have `Content-Type: application/json` (configured in `_headers`)
- Be accessible without redirects
- Contain the correct Team ID + Bundle ID: `UFV835UGV6.app.vaultaire.ios`
