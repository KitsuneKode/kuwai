import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

test('a shell that starts while the screens are dimmed puts them back at once', () => {
  const shell = read('shell/shell.qml');
  expect(shell).toMatch(/readonly property var \w+: Dim\n/);
  const dim = read('shell/services/Dim.qml');
  expect(dim).toMatch(/Component\.onCompleted: if \(saved\.text\(\) !== ""\) up\(\)/);
});

test('nothing else is relied on to wake the dim service: the saver only reads it while showing', () => {
  const saver = read('shell/modules/screensaver/Screensaver.qml');
  expect(saver).toMatch(/running: root\.showing && !Dim\.wanted/);
});
