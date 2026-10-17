import { createHash } from 'node:crypto';

// The Android WebView keeps static assets across APK upgrades. Tie each URL to
// its bytes so a fresh page cannot combine new markup with an old JS bundle.
export function versionAssets(html, assets) {
  for (const [name, bytes] of Object.entries(assets)) {
    const digest = createHash('sha256').update(bytes).digest('hex').slice(0, 16);
    html = html.replaceAll(`"/${name}"`, `"/${name}?v=${digest}"`);
  }
  return html;
}
