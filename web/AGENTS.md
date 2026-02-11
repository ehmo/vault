# Web Agent Instructions

Static website for Vaultaire — landing page, AASA file for universal links, share link fallback page.

Hosted on Cloudflare Pages. No server-side logic — all pages are static HTML + Tailwind CSS.

## Dev

```bash
npm install
npm run dev    # watch mode — rebuilds CSS on change
npm run build  # production CSS build
```

## Structure

- `.well-known/apple-app-site-association` — AASA file for iOS universal links (must be served as `application/json`)
- `index.html` — Landing/marketing page
- `s/index.html` — Share link fallback (shown when user doesn't have the app)
- `styles/input.css` — Tailwind source
- `styles/output.css` — Generated (gitignored)

## Deployment

Cloudflare Pages auto-deploys from the `web/` directory. Build command: `npm run build`. Output directory: `.` (root of web/).

## AASA Requirements

The `apple-app-site-association` file MUST:
- Be served at `https://vaultaire.app/.well-known/apple-app-site-association`
- Have `Content-Type: application/json` (no file extension)
- Be accessible without redirects
- Contain the correct Team ID + Bundle ID: `UFV835UGV6.app.vaultaire.ios`
