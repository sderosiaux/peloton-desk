import { build } from 'esbuild';
import { mkdir, copyFile, cp } from 'node:fs/promises';
await mkdir('.local/web', { recursive: true });
await build({ entryPoints: ['web/app.js'], outfile: '.local/web/app.js', bundle: true,
  minify: true, format: 'esm', target: 'chrome90', legalComments: 'eof' });
for (const name of ['index.html', 'style.css']) await copyFile(`web/${name}`, `.local/web/${name}`);
await cp('node_modules/@novnc/novnc/LICENSE.txt', '.local/web/noVNC-LICENSE.txt');
await mkdir('.local/web/licenses', { recursive: true });
for(const file of ['LICENSE.MPL-2.0','LICENSE.BSD-2-Clause','LICENSE.BSD-3-Clause'])
  await copyFile(`node_modules/@novnc/novnc/docs/${file}`,`.local/web/licenses/${file}`);
await copyFile('node_modules/@novnc/novnc/vendor/pako/LICENSE','.local/web/licenses/pako-MIT.txt');
await copyFile('node_modules/@novnc/novnc/AUTHORS','.local/web/licenses/noVNC-AUTHORS.txt');
console.log('Web app built in .local/web');
