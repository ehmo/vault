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

  await panel.locator('a[href="features/"]').first().click();
  await expect(page.locator('body')).not.toHaveClass(/mobile-nav-open/);

  await context.close();
});

test('desktop compact header keeps nav links on a single line', async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 1905, height: 370 } });
  const page = await context.newPage();
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  const metrics = await page.evaluate(() => {
    const links = Array.from(document.querySelectorAll('.nav-links a'));
    const maxLinkHeight = links.reduce((max, link) => Math.max(max, link.getBoundingClientRect().height), 0);
    const trustStripWidth = document.querySelector('.trust-strip')?.getBoundingClientRect().width ?? 0;
    const viewportWidth = window.innerWidth;
    return { maxLinkHeight, trustStripWidth, viewportWidth };
  });

  expect(metrics.maxLinkHeight).toBeLessThan(26);
  expect(Math.abs(metrics.trustStripWidth - metrics.viewportWidth)).toBeLessThan(3);

  await context.close();
});

test('faq width remains stable when expanded', async ({ page }) => {
  await page.goto('/#faq', { waitUntil: 'domcontentloaded' });
  const before = await page.locator('.faq-grid').evaluate((el) => el.getBoundingClientRect().width);
  await page.locator('.faq-item .faq-summary').first().click();
  const after = await page.locator('.faq-grid').evaluate((el) => el.getBoundingClientRect().width);
  expect(Math.abs(after - before)).toBeLessThan(1);
});

test('mobile phone mockup keeps desktop aspect ratio', async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  const ratio = await page.locator('.mockup-container').evaluate((el) => {
    const rect = el.getBoundingClientRect();
    return rect.width / rect.height;
  });

  expect(ratio).toBeGreaterThan(0.47);
  expect(ratio).toBeLessThan(0.49);

  await context.close();
});
