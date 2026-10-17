import { build } from 'esbuild';
import { mkdir, copyFile, cp, readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { versionAssets } from './web-assets.mjs';
await mkdir('.local/web', { recursive: true });
await build({ entryPoints: ['web/app.js'], outfile: '.local/web/app.js', bundle: true,
  minify: true, format: 'esm', target: 'chrome90', legalComments: 'eof',
  banner: { js: '/*! Includes noVNC 1.7.0 (MPL-2.0). Source: sources/noVNC-1.7.0.tar.gz; notices: licenses/SOURCES.txt. */' } });
await build({ entryPoints: ['web/voice.js'], outfile: '.local/web/voice.js', bundle: true, minify: true, format: 'esm', target: 'chrome90' });
for (const name of ['style.css', 'voice.css']) await copyFile(`web/${name}`, `.local/web/${name}`);
for (const [page, names] of [['index.html', ['app.js', 'style.css']], ['voice.html', ['voice.js', 'style.css', 'voice.css']]]) {
  const assets = Object.fromEntries(await Promise.all(names.map(async name => [name, await readFile(`.local/web/${name}`)])));
  await writeFile(`.local/web/${page}`, versionAssets(await readFile(`web/${page}`, 'utf8'), assets));
}
await cp('node_modules/@novnc/novnc/LICENSE.txt', '.local/web/noVNC-LICENSE.txt');
await mkdir('.local/web/licenses', { recursive: true });
for(const file of ['LICENSE.MPL-2.0','LICENSE.BSD-2-Clause','LICENSE.BSD-3-Clause'])
  await copyFile(`node_modules/@novnc/novnc/docs/${file}`,`.local/web/licenses/${file}`);
await copyFile('node_modules/@novnc/novnc/vendor/pako/LICENSE','.local/web/licenses/pako-MIT.txt');
await copyFile('node_modules/@novnc/novnc/AUTHORS','.local/web/licenses/noVNC-AUTHORS.txt');
// Preserve the DES attribution even if minification drops its ordinary comment.
const des = await readFile('node_modules/@novnc/novnc/core/crypto/des.js', 'utf8');
await writeFile('.local/web/licenses/noVNC-DES-notice.txt', des.slice(0, des.indexOf('*/') + 2) + '\n');
await mkdir('.local/web/sources', { recursive: true });
execFileSync('tar', ['-czf', '.local/web/sources/noVNC-1.7.0.tar.gz', '-C', 'node_modules/@novnc/novnc',
  'core', 'vendor', 'LICENSE.txt', 'AUTHORS', 'docs/LICENSE.MPL-2.0', 'docs/LICENSE.BSD-2-Clause', 'docs/LICENSE.BSD-3-Clause']);
await writeFile('.local/web/licenses/SOURCES.txt', 'noVNC 1.7.0 (MPL-2.0), unmodified upstream source:\n../sources/noVNC-1.7.0.tar.gz\nhttps://github.com/novnc/noVNC/tree/v1.7.0\nOther notices: ../noVNC-LICENSE.txt and this licenses directory.\n');
console.log('Web app built in .local/web');
