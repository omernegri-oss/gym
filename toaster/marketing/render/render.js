const { chromium } = require(process.env.PW || 'playwright');
(async () => {
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--allow-file-access-from-files'] });
  const errors = [];
  const shots = [['thumb', 1920, 1080, 'thumbnail.png'], ['icon', 512, 512, 'icon.png']];
  for (const [mode, w, h, out] of shots) {
    const page = await browser.newPage({ viewport: { width: w, height: h } });
    page.on('pageerror', e => errors.push(String(e)));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    await page.goto('file://' + process.cwd() + '/thumbnail.html?mode=' + mode);
    await page.waitForSelector('body[data-ready="1"]', { timeout: 120000 });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(500);
    await page.screenshot({ path: out });
  }
  console.log('errors', JSON.stringify(errors));
  await browser.close();
})();
