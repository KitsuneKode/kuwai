import { describe, expect, test } from 'bun:test';
import { actionable, arrange, step, first, last, typeahead, place } from '../../shell/components/ui/contextMenu.mjs';

const item = (text, more = {}) => ({ kind: 'item', text, visible: true, enabled: true, ...more });
const sep = (more = {}) => ({ kind: 'separator', visible: true, ...more });
const label = text => ({ kind: 'label', text, visible: true });

describe('context menu', () => {
  test('hidden entries and stray separators are not drawn', () => {
    const a = item('Review'), b = item('Approve', { visible: false }), c = item('Copy name');
    const shown = arrange([sep(), label('linux-zen'), a, sep(), b, sep(), c, sep()]);
    expect(shown.map(e => e.kind === 'separator' ? '—' : e.text)).toEqual(['linux-zen', 'Review', '—', 'Copy name']);
    expect(arrange([sep(), sep()])).toEqual([]);
    expect(arrange(null)).toEqual([]);
  });

  test('only enabled items and checkboxes can be chosen', () => {
    expect(actionable(item('a'))).toBe(true);
    expect(actionable({ kind: 'checkbox', enabled: true })).toBe(true);
    expect(actionable(item('a', { enabled: false }))).toBe(false);
    expect(actionable(label('a'))).toBe(false);
    expect(actionable(sep())).toBe(false);
  });

  test('arrows skip what cannot be chosen and wrap round', () => {
    const e = [label('pkg'), item('Review'), sep(), item('Approve', { enabled: false }), item('Copy name')];
    expect(first(e)).toBe(1);
    expect(last(e)).toBe(4);
    expect(step(e, 1, 1)).toBe(4);
    expect(step(e, 4, 1)).toBe(1);
    expect(step(e, 1, -1)).toBe(4);
    expect(step([label('x'), sep()], -1, 1)).toBe(-1);
  });

  test('a typed letter lights the next row that starts with it', () => {
    const e = [item('Review'), item('Copy name'), item('Copy version'), item('Open on AUR')];
    expect(typeahead(e, -1, 'c')).toBe(1);
    expect(typeahead(e, 1, 'C')).toBe(2);
    expect(typeahead(e, 2, 'c')).toBe(1);
    expect(typeahead(e, 0, 'z')).toBe(0);
    expect(typeahead(e, 0, ' ')).toBe(0);
  });

  test('the card opens at the point and flips where it would run out', () => {
    expect(place(100, 50, 200, 150, 780, 560, 8)).toEqual({ x: 100, y: 50, ox: 0, oy: 0 });
    expect(place(700, 50, 200, 150, 780, 560, 8)).toEqual({ x: 500, y: 50, ox: 1, oy: 0 });     // flips left
    expect(place(100, 500, 200, 150, 780, 560, 8)).toEqual({ x: 100, y: 350, ox: 0, oy: 1 });   // flips up
    expect(place(100, 60, 200, 150, 780, 170, 8)).toEqual({ x: 100, y: 12, ox: 0, oy: 0 });     // no room either way: kept inside
    expect(place(5, 2, 200, 100, 780, 560, 8)).toEqual({ x: 8, y: 8, ox: 0, oy: 0 });
  });
});
