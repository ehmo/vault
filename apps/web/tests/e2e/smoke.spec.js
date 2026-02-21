const { test, expect } = require('@playwright/test');

const ROUTES = [
  '/',
  '/manifesto/',
  '/privacy/',
  '/terms/',
  '/s/',
  '/compare/',
  '/compare/vaultaire-vs-private-photo-vault/',
  '/compare/vaultaire-vs-private-photo-vault/review/',
  '/compare/vaultaire-vs-keepsafe/',
  '/compare/vaultaire-vs-keepsafe/review/',
  '/compare/vaultaire-vs-privault/',
  '/compare/vaultaire-vs-privault/review/',
  '/compare/vaultaire-vs-spv/',
  '/compare/vaultaire-vs-spv/review/',
  '/compare/vaultaire-vs-secret-photo-album/',
  '/compare/vaultaire-vs-secret-photo-album/review/',
  '/compare/vaultaire-vs-pv-secret-photo-album/',
  '/compare/vaultaire-vs-pv-secret-photo-album/review/',
  '/compare/vaultaire-vs-calculator-hide-photos/',
  '/compare/vaultaire-vs-calculator-hide-photos/review/',
  '/compare/vaultaire-vs-secret-photo-vault/',
  '/compare/vaultaire-vs-secret-photo-vault/review/',
  '/compare/vaultaire-vs-hide-it-pro/',
  '/compare/vaultaire-vs-hide-it-pro/review/',
  '/compare/vaultaire-vs-safe-lock/',
  '/compare/vaultaire-vs-safe-lock/review/'
];

for (const route of ROUTES) {
  test(`smoke: ${route} renders without JS errors`, async ({ page }) => {
    const jsErrors = [];
    page.on('pageerror', (error) => jsErrors.push(String(error)));

    const response = await page.goto(route, { waitUntil: 'domcontentloaded' });
    expect(response?.ok(), `expected ${route} to return 2xx`).toBeTruthy();

    await expect(page.locator('header')).toBeVisible();
    await expect(page.locator('footer')).toBeVisible();
    await expect(page.locator('body')).toHaveAttribute('x-data', 'vaultaireApp()');

    // Let deferred Alpine handlers settle.
    await page.waitForTimeout(200);
    expect(jsErrors, `runtime errors on ${route}: ${jsErrors.join('\n')}`).toHaveLength(0);
  });
}

test('all App Store links use the current app id', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const links = await page.locator('a[href*="apps.apple.com/app/vaultaire"]').evaluateAll((els) =>
    els.map((el) => el.getAttribute('href') || '')
  );
  expect(links.length).toBeGreaterThan(0);
  for (const href of links) {
    expect(href).toContain('id6758529311');
  }
});
