import { test, expect } from 'bun:test';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const shell = new URL('../../shell/', import.meta.url).pathname;
function names(dir) {
  const out = [];
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) out.push(...names(p));
    else if (f.endsWith('.qml')) out.push([f.slice(0, -4), p.slice(shell.length)]);
  }
  return out;
}

test('no service shares its name with a component or a module type', () => {
  const services = new Set(readdirSync(join(shell, 'services')).filter(f => f.endsWith('.qml')).map(f => f.slice(0, -4)));
  const clash = [...names(join(shell, 'modules')), ...names(join(shell, 'components'))].filter(([n]) => services.has(n)).map(([, p]) => p);
  expect(clash).toEqual([]);
});
