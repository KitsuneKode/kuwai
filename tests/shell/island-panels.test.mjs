// The island's panels are listed once (Island.titles); IslandBar maps each
// name to its component. A panel added to one and not the other opened
// nothing, or had no name to go back to.
import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';

const root = new URL('../../shell/', import.meta.url);
const island = readFileSync(new URL('services/Island.qml', root), 'utf8');
const bar = readFileSync(new URL('modules/island/IslandBar.qml', root), 'utf8');
const keys = src => [...src.matchAll(/(\w+):/g)].map(m => m[1]);

test('every titled panel has a component, and every component a title', () => {
  const titles = keys(island.match(/readonly property var titles: \(\{([^}]*)\}\)/)[1]);
  const comps = keys(bar.match(/sourceComponent: \(\{([^}]*)\}\)\[win\.shownPanel\]/)[1]);
  expect(titles.length).toBeGreaterThan(10);
  expect([...comps].sort()).toEqual([...titles].sort());
});

test('the names are written out nowhere else in the island bar', () => {
  expect(bar).not.toMatch(/calendar: "Calendar"/);
  expect(island).toMatch(/readonly property var panels: Object\.keys\(titles\)/);
});
