#!/usr/bin/env bash
set -euo pipefail

# Deploy Vaultaire website to Cloudflare Pages
#
# Usage: ./scripts/deploy-web.sh [--preview]
#   --preview  Deploy to a preview URL instead of production
#
# Steps: build CSS -> deploy to Cloudflare Pages
#
# Config:
PROJECT_NAME="vaultaire-web"
WEB_DIR="apps/web"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BRANCH="main"
if [[ "${1:-}" == "--preview" ]]; then
	BRANCH="preview-$(date +%s)"
	echo "==> Preview deploy (branch: $BRANCH)"
else
	echo "==> Production deploy (branch: main)"
fi

# --- Build CSS ---
echo "==> Building Tailwind CSS..."
cd "$WEB_DIR"
npx @tailwindcss/cli -i styles/input.css -o styles/output.css --minify
cd "$REPO_ROOT"

# --- Deploy ---
echo "==> Deploying to Cloudflare Pages..."
DEPLOY_OUTPUT=$(cd "$WEB_DIR" && npx wrangler pages deploy . \
	--project-name "$PROJECT_NAME" \
	--branch "$BRANCH" \
	--commit-dirty=true 2>&1)

echo "$DEPLOY_OUTPUT"

# --- Extract URL ---
URL=$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[^ ]+\.pages\.dev' | tail -1 || true)
if [[ -n "$URL" ]]; then
	echo ""
	echo "==> Done. Deployed to: $URL"
	if [[ "$BRANCH" == "production" ]]; then
		echo "    Live at: https://vaultaire.app"
	fi
else
	echo ""
	echo "==> Deploy finished. Check output above for URL."
fi
