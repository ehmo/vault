const { test, expect } = require('@playwright/test');

test('home mockup animation progresses through unlock and vault states', async ({ page }) => {
  test.setTimeout(30000);
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  const path = page.locator('#drawing-path');
  const phoneScreen = page.locator('.phone-screen');

  await expect
    .poll(async () => {
      const d = await path.getAttribute('d');
      return d && d.trim().length > 0;
    }, { timeout: 10000, intervals: [200, 300, 500] })
    .toBeTruthy();

  await expect
    .poll(async () => await phoneScreen.evaluate((el) => el.classList.contains('mockup-unlocking')), {
      timeout: 15000,
      intervals: [250, 350, 500]
    })
    .toBeTruthy();

  await expect
    .poll(async () => await phoneScreen.evaluate((el) => el.classList.contains('mockup-vault')), {
      timeout: 10000,
      intervals: [250, 350, 500]
    })
    .toBeTruthy();
});
