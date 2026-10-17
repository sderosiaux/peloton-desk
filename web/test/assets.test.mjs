import test from 'node:test';
import assert from 'node:assert/strict';
import { versionAssets } from '../../tools/web-assets.mjs';

test('a changed bundle gets a new URL while unchanged assets remain cached', () => {
  const html = '<link href="/style.css"><script src="/app.js"></script>';
  const old = versionAssets(html, {'app.js': 'old timer', 'style.css': 'style'});
  const next = versionAssets(html, {'app.js': 'automatic timer', 'style.css': 'style'});
  assert.notEqual(old.match(/src="([^"]+)"/)[1], next.match(/src="([^"]+)"/)[1]);
  assert.equal(old.match(/href="([^"]+)"/)[1], next.match(/href="([^"]+)"/)[1]);
  assert.equal(next, versionAssets(html, {'app.js': Buffer.from('automatic timer'), 'style.css': 'style'}));
  assert.match(next, /\/app\.js\?v=[a-f0-9]{16}/);
});
