const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..', '..');

function collectHtmlFiles(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === 'playwright-report' || entry.name === 'test-results') continue;
      if (entry.name === 'demos') continue;
      collectHtmlFiles(full, out);
      continue;
    }
    if (entry.isFile() && entry.name.endsWith('.html')) {
      out.push(full);
    }
  }
  return out;
}

const htmlFiles = collectHtmlFiles(ROOT).filter((file) => !file.includes('redesign-draft.html'));

test('production pages contain no inline style attributes', () => {
  for (const file of htmlFiles) {
    const content = fs.readFileSync(file, 'utf8');
    assert.ok(!/\sstyle="/i.test(content), `Inline style attribute found in ${path.relative(ROOT, file)}`);
  }
});

test('production pages contain no legacy script includes', () => {
  const legacy = ['theme-toggle.js', 'compare-icon-fallback.js', 'mobile-nav.js'];
  for (const file of htmlFiles) {
    const content = fs.readFileSync(file, 'utf8');
    for (const scriptName of legacy) {
      assert.ok(!content.includes(scriptName), `Legacy script ${scriptName} referenced in ${path.relative(ROOT, file)}`);
    }
  }
});

test('all app-store links use current app id', () => {
  for (const file of htmlFiles) {
    const content = fs.readFileSync(file, 'utf8');
    const links = content.match(/https:\/\/apps\.apple\.com\/app\/vaultaire\/id\d+/g) || [];
    for (const href of links) {
      assert.ok(href.endsWith('id6758529311'), `Unexpected App Store ID in ${path.relative(ROOT, file)}: ${href}`);
    }
  }
});

test('pages do not double-initialize Alpine components', () => {
  for (const file of htmlFiles) {
    const content = fs.readFileSync(file, 'utf8');
    assert.ok(!/x-init="init\(\)"/.test(content), `x-init found in ${path.relative(ROOT, file)}; init() must run once`);
  }
});

test('pages load alpine-app.js before alpine.min.js', () => {
  for (const file of htmlFiles) {
    const content = fs.readFileSync(file, 'utf8');
    const appIdx = content.indexOf('/assets/alpine-app.js');
    const alpineIdx = content.indexOf('/assets/alpine.min.js');
    assert.ok(appIdx >= 0, `Missing /assets/alpine-app.js in ${path.relative(ROOT, file)}`);
    assert.ok(alpineIdx >= 0, `Missing /assets/alpine.min.js in ${path.relative(ROOT, file)}`);
    assert.ok(appIdx < alpineIdx, `Incorrect Alpine script order in ${path.relative(ROOT, file)}`);
  }
});

test('home mockup uses only local placeholder assets', () => {
  const indexPath = path.join(ROOT, 'index.html');
  const content = fs.readFileSync(indexPath, 'utf8');
  assert.ok(!content.includes('placehold.co'), 'External placehold.co dependency found in index.html');
  assert.ok(/assets\/mockup\/thumb-01\.svg/.test(content), 'Local mockup placeholders not found in index.html');
});
