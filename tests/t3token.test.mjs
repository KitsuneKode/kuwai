import { test, expect } from 'bun:test';
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

const mod = new URL('../bin/kuwai_t3token.mjs', import.meta.url).pathname;
function tokens(files) {
  const state = mkdtempSync(tmpdir() + '/t3tok-');
  mkdirSync(state + '/kuwai');
  for (const [name, [text, mode]] of Object.entries(files)) {
    writeFileSync(`${state}/kuwai/${name}`, text);
    chmodSync(`${state}/kuwai/${name}`, mode);
  }
  const r = spawnSync('node', ['-e', `import(${JSON.stringify(mod)}).then(m => console.log(JSON.stringify([m.t3Token('read'), m.t3Token('operate')])))`],
    { encoding: 'utf8', env: { PATH: '/usr/bin:/bin', HOME: state, XDG_STATE_HOME: state } });
  return JSON.parse(r.stdout);
}

test('readers and the approver each get their own token', () => {
  expect(tokens({ 't3-token': ['reader', 0o600], 't3-operate-token': ['approver', 0o600] })).toEqual(['reader', 'approver']);
});
test('one token serves both until an operate token exists', () => {
  expect(tokens({ 't3-token': ['only', 0o600] })).toEqual(['only', 'only']);
});
test('a token file others can read is ignored', () => {
  expect(tokens({ 't3-token': ['leaky', 0o644] })).toEqual(['', '']);
});
