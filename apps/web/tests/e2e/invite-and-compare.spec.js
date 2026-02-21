const { test, expect } = require('@playwright/test');

test('invite page builds deep-link from hash token', async ({ page }) => {
  await page.goto('/s/#demo-token-123', { waitUntil: 'domcontentloaded' });

  const openInApp = page.locator('#open-in-app');
  await expect(openInApp).toBeVisible();
  await expect(openInApp).toHaveAttribute('href', 'vaultaire://s?p=demo-token-123#demo-token-123');

  const root = page.locator('html');
  const darkHero = page.locator('#hero-logo-dark');
  const lightHero = page.locator('#hero-logo-light');

  await expect(root).toHaveAttribute('data-theme', /dark|light/);
  const beforeTheme = await root.getAttribute('data-theme');
  await page.locator('#theme-toggle').click();
  const afterTheme = await root.getAttribute('data-theme');
  expect(afterTheme).not.toBe(beforeTheme);

  if (afterTheme === 'light') {
    await expect(lightHero).toBeVisible();
  } else {
    await expect(darkHero).toBeVisible();
  }
});

test('compare page cards have loaded icon assets', async ({ page }) => {
  await page.goto('/compare/', { waitUntil: 'domcontentloaded' });

  const cards = page.locator('.compare-card');
  await expect(cards.first()).toBeVisible();

  const iconHealth = await page.locator('.compare-card img').evaluateAll((images) =>
    images.map((img) => ({
      src: img.getAttribute('src') || '',
      naturalWidth: img.naturalWidth,
      naturalHeight: img.naturalHeight
    }))
  );

  expect(iconHealth.length).toBeGreaterThan(0);
  for (const icon of iconHealth) {
    expect(icon.naturalWidth, `broken icon src: ${icon.src}`).toBeGreaterThan(0);
    expect(icon.naturalHeight, `broken icon src: ${icon.src}`).toBeGreaterThan(0);
  }
});
