import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

test('the dictation ring reads the target window again at every take start, since shuush swaps the file and a watch on it goes stale', () => {
  const target = read('shell/modules/voxtype/VoxTarget.qml');
  expect(target).toMatch(/id: targetFile\n\s+path: root\.runtime \+ "\/voxtype\/target_window"/);
  expect(target).toMatch(/onOnChanged: \{ if \(on\) \{ targetFile\.reload\(\); look\.restart\(\); \}/);
  expect(target).toMatch(/function onVoxSinceChanged\(\) \{ targetFile\.reload\(\); \}/);
});
