import { test, expect } from 'bun:test';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';

const src = readFileSync(new URL('../../shell/services/Calendar.qml', import.meta.url), 'utf8');
const m = /command: \["sh", "-c", (`[\s\S]*?`), "sh", root\.cacheDir, root\.listPath\]/.exec(src);

test('calendar links come from the list file, never the arguments, and plain http is skipped', () => {
  expect(m).toBeTruthy();
  const script = eval(m[1]);
  const d = mkdtempSync(tmpdir() + '/cal-');
  writeFileSync(d + '/a.ics', 'BEGIN:VCALENDAR\nEND:VCALENDAR\n');
  const bin = d + '/bin';
  spawnSync('mkdir', [bin]);
  writeFileSync(bin + '/curl', '#!/bin/sh\necho "$@" >> ' + d + '/curl-args\ncat >> ' + d + '/curl-stdin\nexit 1\n', { mode: 0o755 });
  writeFileSync(d + '/list', `# mine\nhttp://plain.invalid/x.ics\nhttps://sec.invalid/private-token.ics\nhttps://bad"quote.invalid\n${d}/a.ics\n`);
  const r = spawnSync('sh', ['-c', script, 'sh', d + '/cache', d + '/list'], { encoding: 'utf8', env: { PATH: `${bin}:/usr/bin:/bin`, HOME: d } });
  expect(r.status).toBe(0);
  expect(r.stdout).toContain('BEGIN:VCALENDAR');
  const args = readFileSync(d + '/curl-args', 'utf8');
  expect(args).not.toContain('private-token');
  expect(args).toContain('--proto =https');
  const stdin = readFileSync(d + '/curl-stdin', 'utf8');
  expect(stdin).toBe('url = "https://sec.invalid/private-token.ics"\n');
});
