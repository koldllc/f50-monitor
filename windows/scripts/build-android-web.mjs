import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const vite = resolve(here, '../node_modules/vite/bin/vite.js');
const result = spawnSync(process.execPath, [vite, 'build'], {
  cwd: resolve(here, '..'),
  env: { ...process.env, F50_ANDROID: '1' },
  stdio: 'inherit'
});

if (result.error) throw result.error;
process.exit(result.status ?? 1);
