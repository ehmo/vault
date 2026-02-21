const { test, expect } = require('@playwright/test');

test('theme toggle persists across navigation', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  const root = page.locator('html');
  const toggle = page.locator('#theme-toggle');
  await expect(root).toHaveAttribute('data-theme', /dark|light/);
  await expect(toggle).toBeVisible();

  const initialTheme = await root.getAttribute('data-theme');
  await toggle.click();

  const flipped = initialTheme === 'light' ? 'dark' : 'light';
  await expect(root).toHaveAttribute('data-theme', flipped);

  await page.goto('/manifesto/', { waitUntil: 'domcontentloaded' });
  await expect(root).toHaveAttribute('data-theme', flipped);
});

test('mobile nav opens/closes and keeps UX state sane', async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  const menuBtn = page.locator('#mobileMenuBtn');
  const panel = page.locator('#mobileNavExpand');

  await page.waitForSelector('#mobileMenuBtn', { state: 'visible' });
  await expect(menuBtn).toBeVisible();
  await menuBtn.click();
  await expect(panel).toHaveClass(/open/);
  await expect(page.locator('body')).toHaveClass(/mobile-nav-open/);

  await panel.locator('a[href="index.html#features"]').first().click();
  await expect(page.locator('body')).not.toHaveClass(/mobile-nav-open/);

  await context.close();
});
