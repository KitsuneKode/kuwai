import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

test('the dictation caption reads the in-field marker again when its wait ends, so a late marker never flashes the first word', () => {
  const target = read('shell/modules/voxtype/VoxTarget.qml');
  expect(target).toMatch(/id: settle;[^\n]*onTriggered: \{ Activities\.voxRecheckField\(\); caption\.want = caption\.wanted; \}/);
  const acts = read('shell/services/Activities.qml');
  expect(acts).toMatch(/function voxRecheckField\(\) \{ inField\.reload\(\); \}/);
  expect(acts).toMatch(/id: inField\n[^}]*blockLoading: true/);
});
