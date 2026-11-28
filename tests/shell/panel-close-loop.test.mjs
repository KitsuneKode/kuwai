import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';

const bar = readFileSync(new URL('../../shell/modules/island/IslandBar.qml', import.meta.url), 'utf8');

test('a closing panel keeps the size it had open: its hidden content can no longer re-size it and feed a layout loop', () => {
  expect(bar).toMatch(/readonly property size livePanelSize: panelLoader\.item/);
  expect(bar).toMatch(/property size panelSize: Qt\.size\(Theme\.panelS, 300\)\n/);
  expect(bar).toMatch(/Binding on panelSize \{ value: win\.livePanelSize; when: win\.panelHere; restoreMode: Binding\.RestoreNone \}/);
  expect(bar).not.toMatch(/readonly property size panelSize:/);
});

test('the panel content is sized from the held size, and its fade still reads the shape against it', () => {
  expect(bar).toMatch(/width: win\.panelSize\.width\n\s*height: win\.panelSize\.height/);
  expect(bar).toMatch(/opacity: k \* win\.fitIn\(width, height\)\.shown/);
  expect(bar).toMatch(/visible: opacity > 0\.01 \|\| win\.panelHere/);
});
